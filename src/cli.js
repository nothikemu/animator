/**
 * Command-line interface and pipeline orchestration.
 *
 *   main(argv)                → parses the terminal arguments, sets up the UI,
 *                               signal handling and exit codes.
 *   generateAnimation(opts)   → runs the three phases (analyze → render →
 *                               encode). Also exported for programmatic use;
 *                               without a reporter it runs silently.
 */

import fs from 'node:fs';
import fsp from 'node:fs/promises';
import path from 'node:path';
import process from 'node:process';
import { parseArgs } from 'node:util';
import { AnimatorError, throwIfAborted } from './utils/errors.js';
import { createTempDir, installSignalHandlers, isShuttingDown, runCleanup, shutdownSignal } from './utils/cleanup.js';
import { Terminal, formatBytes, formatDuration } from './utils/terminal.js';
import { collectDiff, DEFAULT_MAX_FILE_BYTES } from './utils/git.js';
import { createFileModel, createTimeline, hashSeed, toPagePayload } from './engines/timeline.js';
import { FrameRenderer, defaultWorkerCount } from './engines/renderer.js';
import { encodeVideo, finalizeOutput, formatFromPath, locateFfmpeg, SUPPORTED_FORMATS } from './engines/encoder.js';
import { DEFAULT_THEME, THEMES, resolveTheme } from './engines/themes.js';

const PACKAGE = JSON.parse(fs.readFileSync(new URL('../package.json', import.meta.url), 'utf8'));
export const VERSION = PACKAGE.version;

const SIZE_PRESETS = {
  '480p': [854, 480],
  '540p': [960, 540],
  '720p': [1280, 720],
  '1080p': [1920, 1080],
  '1440p': [2560, 1440],
  '4k': [3840, 2160],
  '2160p': [3840, 2160],
  square: [1080, 1080],
};

const DEFAULTS = Object.freeze({
  output: 'animation.mp4',
  size: { mp4: [1920, 1080], gif: [1280, 720] },
  fps: { mp4: 60, gif: 30 },
  theme: DEFAULT_THEME,
  fontSize: 22,
  speed: 1,
  maxDuration: 30,
  maxFiles: 8,
  crf: 18,
  batchSize: 120,
});

const MAX_GIF_FPS = 50;

const OPTION_SPEC = {
  repo: { type: 'string', short: 'r' },
  base: { type: 'string', short: 'b' },
  target: { type: 'string', short: 't' },
  output: { type: 'string', short: 'o' },
  format: { type: 'string', short: 'f' },
  size: { type: 'string', short: 's' },
  fps: { type: 'string' },
  theme: { type: 'string' },
  background: { type: 'string' },
  'font-size': { type: 'string' },
  title: { type: 'string' },
  speed: { type: 'string' },
  'max-duration': { type: 'string', short: 'd' },
  'max-files': { type: 'string' },
  'all-files': { type: 'boolean' },
  seed: { type: 'string' },
  crf: { type: 'string' },
  workers: { type: 'string', short: 'w' },
  'batch-size': { type: 'string' },
  'keep-frames': { type: 'boolean' },
  'list-themes': { type: 'boolean' },
  quiet: { type: 'boolean', short: 'q' },
  verbose: { type: 'boolean' },
  'no-color': { type: 'boolean' },
  help: { type: 'boolean', short: 'h' },
  version: { type: 'boolean', short: 'v' },
};

/** @param {string} message @param {string} [hint] */
function usageError(message, hint = 'Run `git-commit-animator --help` to see all options.') {
  return new AnimatorError(message, { code: 'E_USAGE', hint, exitCode: 2 });
}

/**
 * @param {string | undefined} value
 * @param {string} flag
 * @param {{ min: number, max: number, integer?: boolean }} limits
 */
function parseNumber(value, flag, { min, max, integer = false }) {
  if (value === undefined) return undefined;
  const n = Number(value);
  if (!Number.isFinite(n) || (integer && !Number.isInteger(n)) || n < min || n > max) {
    throw usageError(`${flag} must be ${integer ? 'an integer' : 'a number'} between ${min} and ${max} (got "${value}").`);
  }
  return n;
}

/** @param {string} value */
export function parseSize(value) {
  const preset = SIZE_PRESETS[value.toLowerCase()];
  if (preset) return [...preset];
  const m = /^(\d{2,5})\s*[x×*:]\s*(\d{2,5})$/i.exec(value.trim());
  if (!m) throw usageError(`Invalid --size "${value}".`, `Use WIDTHxHEIGHT (e.g. 1600x900) or a preset: ${Object.keys(SIZE_PRESETS).join(', ')}.`);
  return [Number(m[1]), Number(m[2])];
}

const COLOR_RE = /^(?:#[\da-f]{3,4}|#[\da-f]{6}|#[\da-f]{8}|[a-z]{3,20}|(?:rgb|hsl)a?\([\d\s.,%/-]+\))$/i;

/** @param {string} value */
export function parseBackground(value) {
  const colors = value.split(/\s*,\s*(?![^()]*\))/).map((c) => c.trim()).filter(Boolean);
  if (colors.length < 1 || colors.length > 2 || !colors.every((c) => COLOR_RE.test(c))) {
    throw usageError(`Invalid --background "${value}".`, 'Pass one or two CSS colors, e.g. --background "#0ea5e9,#22c55e".');
  }
  return colors.length === 1 ? [colors[0], colors[0]] : colors;
}

/**
 * Splits revision positionals: `A B`, `A..B`, `A...B` or a single commit.
 * @param {string[]} revs
 */
function parseRevisions(revs) {
  if (revs.length === 0) return {};
  if (revs.length > 2) throw usageError(`Too many revisions: ${revs.join(' ')}`, 'Pass at most two revisions, or put file paths after `--`.');
  if (revs.length === 2) return { base: revs[0], target: revs[1] };
  const [rev] = revs;
  const symmetric = /^(.*?)\.\.\.(.*)$/.exec(rev);
  if (symmetric) return { base: symmetric[1] || 'HEAD', target: symmetric[2] || 'HEAD', symmetric: true };
  const range = /^(.*?)\.\.(.*)$/.exec(rev);
  if (range) return { base: range[1] || 'HEAD', target: range[2] || 'HEAD' };
  return { target: rev };
}

/**
 * Parses raw terminal arguments into normalized options.
 * @param {string[]} argv
 */
export function parseCliArgs(argv) {
  let parsed;
  try {
    parsed = parseArgs({ args: argv, options: OPTION_SPEC, allowPositionals: true, strict: true, tokens: true });
  } catch (error) {
    const unknown = /Unknown option '([^']+)'/.exec(error.message);
    if (unknown) throw usageError(`Unknown option ${unknown[1]}.`);
    const missing = /Option '([^']+)' argument missing/.exec(error.message);
    if (missing) throw usageError(`Option ${missing[1]} needs a value.`);
    throw usageError(error.message.split('\n')[0]);
  }
  const { values, tokens } = parsed;
  const terminator = tokens.find((t) => t.kind === 'option-terminator');
  const revs = [];
  const pathspec = [];
  for (const token of tokens) {
    if (token.kind !== 'positional') continue;
    if (terminator && token.index > terminator.index) pathspec.push(token.value);
    else revs.push(token.value);
  }

  const flags = {
    help: Boolean(values.help),
    version: Boolean(values.version),
    listThemes: Boolean(values['list-themes']),
    quiet: Boolean(values.quiet),
    verbose: Boolean(values.verbose),
    noColor: Boolean(values['no-color']),
  };
  if (flags.help || flags.version || flags.listThemes) return { ...flags, options: null };

  const positional = parseRevisions(revs);
  if ((positional.base && values.base) || (positional.target && values.target)) {
    throw usageError('Revisions were given both as arguments and as --base/--target.', 'Use one style, e.g. `git-commit-animator A B` or `--base A --target B`.');
  }

  const options = normalizeOptions({
    repo: values.repo,
    base: values.base ?? positional.base ?? null,
    target: values.target ?? positional.target ?? null,
    symmetric: Boolean(positional.symmetric),
    pathspec,
    output: values.output,
    format: values.format,
    size: values.size,
    fps: parseNumber(values.fps, '--fps', { min: 1, max: 120, integer: true }),
    theme: values.theme,
    background: values.background,
    fontSize: parseNumber(values['font-size'], '--font-size', { min: 8, max: 64 }),
    title: values.title,
    speed: parseNumber(values.speed, '--speed', { min: 0.1, max: 20 }),
    maxDuration: parseNumber(values['max-duration'], '--max-duration', { min: 2, max: 900 }),
    maxFiles: parseNumber(values['max-files'], '--max-files', { min: 1, max: 200, integer: true }),
    allFiles: Boolean(values['all-files']),
    seed: parseNumber(values.seed, '--seed', { min: 0, max: 2 ** 32 - 1, integer: true }),
    crf: parseNumber(values.crf, '--crf', { min: 0, max: 51, integer: true }),
    workers: parseNumber(values.workers, '--workers', { min: 1, max: 32, integer: true }),
    batchSize: parseNumber(values['batch-size'], '--batch-size', { min: 1, max: 5000, integer: true }),
    keepFrames: Boolean(values['keep-frames']),
  });
  return { ...flags, options };
}

/**
 * Applies smart defaults and validates option combinations. Accepts both raw
 * strings (from the CLI) and typed values (programmatic use).
 *
 * @param {Record<string, any>} input
 */
export function normalizeOptions(input = {}) {
  const warnings = [];
  const repo = path.resolve(input.repo ?? process.cwd());

  let format = input.format ? String(input.format).toLowerCase() : null;
  if (format && !SUPPORTED_FORMATS[format]) throw usageError(`Unsupported --format "${input.format}".`, 'Choose mp4 or gif.');

  let output = input.output ? String(input.output) : null;
  if (output) {
    const fromExt = formatFromPath(output);
    if (!path.extname(output) && format) output += `.${format}`;
    else if (!fromExt && !format) {
      throw usageError(`Cannot tell the format of "${output}".`, 'Use a .mp4 or .gif file name, or pass --format mp4|gif.');
    } else if (fromExt && format && fromExt !== format) {
      throw usageError(`--output "${output}" does not match --format ${format}.`);
    }
    format ??= fromExt ?? 'mp4';
  } else {
    format ??= 'mp4';
    output = format === 'mp4' ? DEFAULTS.output : `animation.${format}`;
  }
  output = path.resolve(process.cwd(), output);

  const [width, height] = input.size ? (Array.isArray(input.size) ? input.size : parseSize(String(input.size))) : DEFAULTS.size[format];
  if (width < 320 || height < 180 || width > 3840 || height > 3840) {
    throw usageError(`--size ${width}x${height} is out of range.`, 'Width/height must be between 320x180 and 3840x3840.');
  }
  if (format === 'mp4' && (width % 2 || height % 2)) {
    throw usageError(`--size ${width}x${height} has an odd dimension.`, 'H.264 with yuv420p requires even width and height, e.g. 1280x720.');
  }

  let fps = input.fps ?? DEFAULTS.fps[format];
  if (format === 'gif' && fps > MAX_GIF_FPS) {
    warnings.push(`GIF frame delays are limited to 1/100 s; using ${MAX_GIF_FPS} fps instead of ${fps}.`);
    fps = MAX_GIF_FPS;
  }

  const themeName = input.theme ? String(input.theme).toLowerCase() : DEFAULTS.theme;
  if (!THEMES[themeName]) throw usageError(`Unknown theme "${input.theme}".`, `Available themes: ${Object.keys(THEMES).join(', ')}.`);
  const background = input.background ? (Array.isArray(input.background) ? input.background : parseBackground(String(input.background))) : null;

  return {
    repo,
    base: input.base || null,
    target: input.target || null,
    symmetric: Boolean(input.symmetric),
    pathspec: input.pathspec ?? [],
    output,
    format,
    width,
    height,
    fps,
    theme: themeName,
    background,
    fontSize: input.fontSize ?? DEFAULTS.fontSize,
    title: input.title ? String(input.title) : null,
    speed: input.speed ?? DEFAULTS.speed,
    maxDuration: input.maxDuration ?? DEFAULTS.maxDuration,
    maxFiles: input.maxFiles ?? DEFAULTS.maxFiles,
    allFiles: Boolean(input.allFiles),
    seed: input.seed ?? null,
    crf: input.crf ?? DEFAULTS.crf,
    workers: input.workers ?? null,
    batchSize: input.batchSize ?? DEFAULTS.batchSize,
    keepFrames: Boolean(input.keepFrames),
    maxFileBytes: input.maxFileBytes ?? DEFAULT_MAX_FILE_BYTES,
    warnings,
  };
}

/** Reporter used for programmatic calls: swallows all UI output. */
const SILENT_REPORTER = {
  s: new Proxy({}, { get: () => (x) => String(x) }),
  icon: () => '',
  banner() {},
  phase() {},
  detail() {},
  item() {},
  info() {},
  warn() {},
  debug() {},
  line() {},
  spinner: () => ({ stop() {}, setText() {} }),
  progress: () => ({ update() {}, done() {}, fail() {} }),
  success() {},
};

/**
 * Runs the complete pipeline.
 *
 * @param {Record<string, any>} rawOptions Options (see normalizeOptions).
 * @param {{ reporter?: any, signal?: AbortSignal }} [context]
 */
export async function generateAnimation(rawOptions, { reporter, signal = shutdownSignal } = {}) {
  const options = rawOptions?.warnings ? rawOptions : normalizeOptions(rawOptions);
  const ui = reporter ?? SILENT_REPORTER;
  const { s } = ui;
  const startedAt = performance.now();
  const formatLabel = options.format === 'gif' ? 'GIF Animation' : 'MP4 Video';
  const TOTAL = 3;

  for (const warning of options.warnings) ui.warn(warning);

  // Preflight: verify the encoder before spending time on rendering.
  const ffmpegInfo = await locateFfmpeg(options.format);
  ui.debug(`ffmpeg ${ffmpegInfo.version} via ${ffmpegInfo.source} (${ffmpegInfo.path})`);

  let temp = null;
  let renderer = null;
  try {
    // ---- [1/3] Analyze ---------------------------------------------------
    ui.phase(1, TOTAL, 'analyze', 'Analyzing Git Commits...');
    const diff = await collectDiff({
      repoPath: options.repo,
      base: options.base,
      target: options.target,
      symmetric: options.symmetric,
      pathspec: options.pathspec,
      maxFiles: options.maxFiles,
      includeGenerated: options.allFiles,
      maxFileBytes: options.maxFileBytes,
    });
    throwIfAborted(signal);

    const { repo, base, target, files, skipped, branch } = diff;
    ui.detail('Repository', `${s.bold(repo.name)} ${s.dim(repo.root)}`);
    ui.detail('Commits', `${s.yellow(base.shortHash)} ${ui.icon('arrow')} ${s.yellow(target.shortHash)}${target.subject ? `  ${s.dim(`"${truncate(target.subject, 60)}"`)}` : ''}`);
    if (base.isEmptyTree) ui.detail('', s.dim('(root commit: animating from an empty tree)'));
    if (options.pathspec.length) ui.detail('Paths', options.pathspec.join(' '));

    const totalAdd = files.reduce((n, f) => n + f.additions, 0);
    const totalDel = files.reduce((n, f) => n + f.deletions, 0);
    ui.detail('Changes', `${files.length} file${files.length === 1 ? '' : 's'}  ${s.green(`+${totalAdd}`)} ${s.red(`-${totalDel}`)}`);
    const LIST_LIMIT = 10;
    for (const f of files.slice(0, LIST_LIMIT)) {
      const rename = f.status === 'R' && f.oldPath !== f.path ? s.dim(` (from ${f.oldPath})`) : '';
      ui.item(`${f.path}${rename}  ${s.green(`+${f.additions}`)} ${s.red(`-${f.deletions}`)}`);
    }
    if (files.length > LIST_LIMIT) ui.item(s.dim(`…and ${files.length - LIST_LIMIT} more`));
    if (skipped.length) {
      const reasons = [...new Set(skipped.map((k) => k.reason))].join(', ');
      ui.line(`      ${s.dim(`${ui.icon('skip')} Skipped ${skipped.length} file${skipped.length === 1 ? '' : 's'} (${reasons})`)}`);
      for (const k of skipped) ui.debug(`skipped ${k.path}: ${k.reason}`);
    }

    if (!files.length) {
      const generatedOnly = skipped.some((k) => k.reason.startsWith('lockfile'));
      throw new AnimatorError('There are no text changes to animate between these commits.', {
        code: 'E_NOTHING_TO_ANIMATE',
        hint: generatedOnly
          ? 'Only lockfiles/generated files changed. Pass --all-files to include them.'
          : 'Pick a different range, e.g. `git-commit-animator HEAD~3 HEAD`, or check your pathspec.',
      });
    }

    const models = files.map((file, i) => createFileModel(file, i));
    const payloads = models.map(toPagePayload);
    const theme = resolveTheme(options.theme, options.background);

    temp = await createTempDir();
    const framesDir = path.join(temp.path, 'frames');
    await fsp.mkdir(framesDir);
    ui.debug(`working directory: ${temp.path}`);

    // ---- [2/3] Render ----------------------------------------------------
    const workers = options.workers ?? defaultWorkerCount();
    const spinner = ui.spinner('Launching headless Chrome…');
    renderer = new FrameRenderer({
      width: options.width,
      height: options.height,
      fontSize: options.fontSize,
      theme,
      payloads,
      framesDir,
      workers,
      batchSize: options.batchSize,
      signal,
      meta: {
        repoName: options.title ?? repo.name,
        branch,
        baseHash: base.shortHash,
        targetHash: target.shortHash,
        subject: target.subject,
        tabs: models.map((m) => ({ name: m.name, language: m.language.name, status: m.status, additions: m.additions, deletions: m.deletions })),
      },
      onStatus: (message) => spinner.setText(message),
      onDebug: (message) => ui.debug(message),
    });
    let started;
    try {
      started = await renderer.start();
    } catch (error) {
      spinner.stop('Headless Chrome could not start', false);
      throw error;
    }
    spinner.stop(`Headless Chrome ready ${s.dim(`(${started.workers} parallel renderer${started.workers === 1 ? '' : 's'})`)}`);
    if (!started.fontLoaded) ui.warn('Bundled JetBrains Mono failed to load; using the system monospace font.');

    const seed = options.seed ?? hashSeed(`${base.hash}:${target.hash}`);
    const timeline = createTimeline(models, {
      fps: options.fps,
      visibleLines: started.visibleLines,
      speed: options.speed,
      maxDuration: options.maxDuration,
      seed,
    });
    ui.debug(`timeline: ${timeline.stats.keystrokes} keystrokes, ${timeline.stats.hunks} hunks, ${(timeline.durationMs / 1000).toFixed(2)}s, seed ${seed}`);
    if (timeline.stats.typingScale < 0.67) {
      const factor = 1 / timeline.stats.typingScale;
      ui.warn(`Typing sped up ${factor.toFixed(1)}× to fit --max-duration ${options.maxDuration}s (raise it for a slower take).`);
      if (factor > 8) {
        const biggest = [...models].sort((a, b) => b.additions - a.additions)[0];
        ui.info(s.dim(`Tip: this diff is very large for one video. Focus on one file, e.g. \`-- ${biggest.path}\`, or a smaller range.`));
      }
    } else if (timeline.stats.compressed) {
      ui.debug(`timeline compressed to fit --max-duration (typing scale ${timeline.stats.typingScale.toFixed(2)})`);
    }

    ui.phase(2, TOTAL, 'render', `Rendering ${timeline.totalFrames.toLocaleString('en-US')} Frames...`);
    ui.detail('Output', `${options.width}×${options.height} @ ${options.fps}fps · ${formatDuration(timeline.durationMs)} · theme ${options.theme}`);
    const firstView = timeline.frames().next().value;
    const background = await renderer.captureBackground(firstView);
    const renderBar = ui.progress({ total: timeline.totalFrames, unit: 'frames' });
    let rendered;
    try {
      rendered = await renderer.render(timeline.frames(), timeline.totalFrames, (p) => renderBar.update(p.done));
    } catch (error) {
      renderBar.fail();
      throw error;
    }
    renderBar.done(`${rendered.frames.toLocaleString('en-US')} frames ${s.dim(`(${rendered.unique.toLocaleString('en-US')} rendered, ${(rendered.frames - rendered.unique).toLocaleString('en-US')} deduplicated)`)}`);
    const clip = started.clip;
    await renderer.close();
    renderer = null;
    throwIfAborted(signal);

    // ---- [3/3] Encode ----------------------------------------------------
    ui.phase(3, TOTAL, 'encode', `Compiling ${formatLabel}...`);
    const tempOutput = path.join(temp.path, `output.${options.format}`);
    const encodeBar = ui.progress({ total: rendered.frames, unit: 'frames' });
    try {
      await encodeVideo({
        ffmpegPath: ffmpegInfo.path,
        format: options.format,
        framesDir,
        background,
        clip,
        fps: options.fps,
        width: options.width,
        height: options.height,
        frameCount: rendered.frames,
        output: tempOutput,
        crf: options.crf,
        signal,
        onProgress: (fraction) => encodeBar.update(Math.round(fraction * rendered.frames)),
        onDebug: (message) => ui.debug(message),
      });
    } catch (error) {
      encodeBar.fail();
      throw error;
    }
    encodeBar.done(options.format === 'gif' ? 'GIF encoded (2-pass palette)' : 'H.264 encoded (yuv420p, BT.709, faststart)');

    await finalizeOutput(tempOutput, options.output);
    const { size } = await fsp.stat(options.output);
    const durationMs = (rendered.frames / options.fps) * 1000;

    let framesNote = null;
    if (options.keepFrames) {
      temp.release();
      framesNote = framesDir;
    } else {
      await temp.dispose();
    }
    temp = null;

    const rows = [
      ['Format', `${SUPPORTED_FORMATS[options.format].label} · ${SUPPORTED_FORMATS[options.format].codec}`],
      ['Video', `${options.width}×${options.height} · ${options.fps}fps · ${formatDuration(durationMs)} · ${rendered.frames.toLocaleString('en-US')} frames`],
      ['Size', formatBytes(size)],
      ['Took', formatDuration(performance.now() - startedAt)],
    ];
    if (framesNote) rows.push(['Frames', framesNote]);
    ui.success('Animation ready!', rows, options.output);

    return {
      output: options.output,
      format: options.format,
      width: options.width,
      height: options.height,
      fps: options.fps,
      frames: rendered.frames,
      uniqueFrames: rendered.unique,
      durationMs,
      bytes: size,
      files: models.map((m) => m.path),
      base: base.hash,
      target: target.hash,
      framesDir: framesNote,
    };
  } finally {
    if (renderer) await renderer.close().catch(() => {});
    if (temp) {
      if (options.keepFrames) temp.release();
      else await temp.dispose().catch(() => {});
    }
  }
}

function truncate(text, max) {
  return text.length > max ? `${text.slice(0, max - 1)}…` : text;
}

/** @param {Terminal} term */
function helpText(term) {
  const { s } = term;
  const h = (t) => s.bold(s.cyan(t));
  const themes = Object.keys(THEMES).join(' | ');
  return `
  ${s.bold(s.brightMagenta('Git-Commit Animator'))} ${s.dim(`v${VERSION}`)}
  Turn a git diff into a 60fps "typing" animation (MP4 or GIF) for your README.

${h('  USAGE')}
    git-commit-animator [options] [<commit>]
    git-commit-animator [options] <base> <target> [-- <path>...]
    git-commit-animator [options] <base>..<target>

  With no arguments it animates the latest commit (HEAD~1 → HEAD) of the
  repository in the current folder and writes ./animation.mp4.

${h('  OPTIONS')}
    -r, --repo <path>         Repository folder ${s.dim('(default: current directory)')}
    -b, --base <rev>          Starting revision ${s.dim('(default: parent of target)')}
    -t, --target <rev>        Final revision ${s.dim('(default: HEAD)')}
    -o, --output <file>       Output file, .mp4 or .gif ${s.dim('(default: ./animation.mp4)')}
    -f, --format <mp4|gif>    Force the output format
    -s, --size <WxH|preset>   720p, 1080p, 1440p, 4k, square or e.g. 1600x900
                              ${s.dim('(default: 1080p for MP4, 720p for GIF)')}
        --fps <n>             Frame rate ${s.dim('(default: 60 for MP4, 30 for GIF)')}
        --theme <name>        ${themes} ${s.dim(`(default: ${DEFAULT_THEME})`)}
        --background <c1,c2>  Canvas gradient ${s.dim('(default: #6366f1,#a855f7)')}
        --font-size <px>      Code font size at 1080p ${s.dim('(default: 22)')}
        --title <text>        Name shown in the title bar ${s.dim('(default: repo name)')}
        --speed <n>           Typing speed multiplier ${s.dim('(default: 1)')}
    -d, --max-duration <s>    Longest video; typing speeds up to fit ${s.dim('(default: 30)')}
        --max-files <n>       Animate at most n files, biggest first ${s.dim('(default: 8)')}
        --all-files           Include lockfiles and generated/minified files
        --seed <n>            Seed for the typing rhythm ${s.dim('(default: derived from commits)')}
        --crf <0-51>          H.264 quality, lower is better ${s.dim('(default: 18)')}
    -w, --workers <n>         Parallel headless Chrome renderers ${s.dim('(default: auto)')}
        --batch-size <n>      Frames per render batch ${s.dim('(default: 120)')}
        --keep-frames         Keep the rendered PNG frames for inspection
        --list-themes         List the available themes
    -q, --quiet               Print only the output path ${s.dim('(for scripts)')}
        --verbose             Show debug output and full error details
        --no-color            Disable colors
    -h, --help                Show this help
    -v, --version             Show the version

${h('  EXAMPLES')}
    git-commit-animator                          ${s.dim('# latest commit → animation.mp4')}
    git-commit-animator a1b2c3d                  ${s.dim('# one specific commit')}
    git-commit-animator v1.0.0 v1.1.0 -- src/    ${s.dim('# a range, limited to src/')}
    git-commit-animator HEAD~3..HEAD -o demo.gif ${s.dim('# a GIF of the last three commits')}
    git animate --theme daylight                 ${s.dim('# same tool as a git subcommand')}

${h('  ENVIRONMENT')}
    FFMPEG_PATH                  Use a specific ffmpeg binary
    PUPPETEER_EXECUTABLE_PATH    Use an existing Chrome/Chromium
    NO_COLOR, FORCE_COLOR        Control terminal colors
`;
}

/**
 * CLI entry point. Resolves to the process exit code.
 * @param {string[]} [argv]
 */
export async function main(argv = process.argv.slice(2)) {
  let term = new Terminal({ color: argv.includes('--no-color') ? false : undefined });
  let parsed;
  try {
    parsed = parseCliArgs(argv);
  } catch (error) {
    term.error(error);
    return error.exitCode ?? 2;
  }

  if (parsed.help) {
    process.stdout.write(helpText(new Terminal({ stream: process.stdout, color: parsed.noColor ? false : undefined })));
    return 0;
  }
  if (parsed.version) {
    process.stdout.write(`${VERSION}\n`);
    return 0;
  }
  if (parsed.listThemes) {
    for (const [name, theme] of Object.entries(THEMES)) process.stdout.write(`${name.padEnd(10)} ${theme.label}\n`);
    return 0;
  }

  term = new Terminal({ quiet: parsed.quiet, verbose: parsed.verbose, color: parsed.noColor ? false : undefined });
  installSignalHandlers({
    onSignal: (signal) => {
      term.restore();
      if (!parsed.quiet) process.stderr.write(`\n\n  ${term.s.yellow(`${term.icon('warning')} Received ${signal}: stopping and removing temporary files…`)}\n\n`);
    },
  });
  process.on('exit', () => term.restore());

  term.banner(VERSION);
  try {
    const result = await generateAnimation(parsed.options, { reporter: term });
    if (parsed.quiet) process.stdout.write(`${result.output}\n`);
    return 0;
  } catch (error) {
    if (isShuttingDown()) return 130;
    term.restore();
    const friendly = error instanceof AnimatorError
      ? error
      : Object.assign(new AnimatorError(`Unexpected error: ${error?.message ?? error}`, { code: 'E_INTERNAL', cause: error }), { stack: error?.stack });
    term.error(friendly);
    await runCleanup();
    return friendly.exitCode ?? 1;
  }
}
