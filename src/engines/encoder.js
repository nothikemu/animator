/**
 * Video encoding subsystem (ffmpeg via fluent-ffmpeg).
 *
 * Responsibilities:
 *   - locate a working ffmpeg binary (FFMPEG_PATH, PATH scan, common install
 *     locations) and verify the capabilities we need, failing with OS-specific
 *     installation instructions instead of a stack trace;
 *   - composite the per-frame editor-window PNGs onto the static background;
 *   - encode either web-ready H.264 MP4 (locked CFR, yuv420p, BT.709, faststart)
 *     or an optimized two-pass palette GIF;
 *   - kill ffmpeg on abort and move the finished file into place atomically so
 *     a half-written video never appears at the destination.
 */

import { spawn } from 'node:child_process';
import fs from 'node:fs';
import fsp from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import ffmpeg from 'fluent-ffmpeg';
import { AbortError, AnimatorError } from '../utils/errors.js';
import { registerCleanup } from '../utils/cleanup.js';
import { FRAME_PATTERN } from './renderer.js';

export const SUPPORTED_FORMATS = Object.freeze({
  mp4: { label: 'MP4', codec: 'H.264', extensions: ['.mp4', '.m4v', '.mov'] },
  gif: { label: 'GIF', codec: 'GIF (256-color palette)', extensions: ['.gif'] },
});

/**
 * Infers the output format from a file name.
 * @param {string} file
 * @returns {'mp4' | 'gif' | null}
 */
export function formatFromPath(file) {
  const ext = path.extname(file).toLowerCase();
  for (const [format, spec] of Object.entries(SUPPORTED_FORMATS)) {
    if (spec.extensions.includes(ext)) return /** @type {'mp4' | 'gif'} */ (format);
  }
  return null;
}

function isExecutableFile(candidate, platform = process.platform) {
  try {
    const stat = fs.statSync(candidate);
    if (!stat.isFile()) return false;
    // Windows has no execute bit: existence with a PATHEXT extension is enough.
    if (platform !== 'win32') fs.accessSync(candidate, fs.constants.X_OK);
    return true;
  } catch {
    return false;
  }
}

/**
 * Scans the PATH environment variable for an executable, honouring PATHEXT
 * on Windows. Pure lookup: nothing is executed.
 *
 * @param {string} name
 * @param {{ envPath?: string, platform?: string, pathext?: string }} [options]
 * @returns {string | null}
 */
export function findExecutable(name, { envPath = process.env.PATH ?? process.env.Path ?? '', platform = process.platform, pathext = process.env.PATHEXT } = {}) {
  const delimiter = platform === 'win32' ? ';' : ':';
  const extensions = platform === 'win32'
    ? ['', ...(pathext || '.EXE;.CMD;.BAT;.COM').split(';').filter(Boolean)]
    : [''];
  for (const rawDir of envPath.split(delimiter)) {
    const dir = rawDir.trim().replace(/^"(.*)"$/, '$1');
    if (!dir) continue;
    for (const ext of extensions) {
      const candidate = path.join(dir, name + ext.toLowerCase());
      if (isExecutableFile(candidate, platform)) return candidate;
      if (ext && isExecutableFile(path.join(dir, name + ext), platform)) return path.join(dir, name + ext);
    }
  }
  return null;
}

/** Well-known install locations used when PATH is incomplete (GUI shells, fresh installs). */
function commonLocations(platform = process.platform) {
  const home = os.homedir();
  if (platform === 'darwin') {
    return ['/opt/homebrew/bin/ffmpeg', '/usr/local/bin/ffmpeg', '/opt/local/bin/ffmpeg'];
  }
  if (platform === 'win32') {
    const local = process.env.LOCALAPPDATA ?? path.join(home, 'AppData', 'Local');
    return [
      path.join(local, 'Microsoft', 'WinGet', 'Links', 'ffmpeg.exe'),
      path.join(home, 'scoop', 'shims', 'ffmpeg.exe'),
      'C:\\ProgramData\\chocolatey\\bin\\ffmpeg.exe',
      'C:\\ffmpeg\\bin\\ffmpeg.exe',
    ];
  }
  return ['/usr/bin/ffmpeg', '/usr/local/bin/ffmpeg', '/snap/bin/ffmpeg', '/home/linuxbrew/.linuxbrew/bin/ffmpeg', path.join(home, '.local', 'bin', 'ffmpeg')];
}

function captureOutput(bin, args, timeoutMs = 15000) {
  return new Promise((resolve) => {
    let child;
    try {
      child = spawn(bin, args, { stdio: ['ignore', 'pipe', 'pipe'], windowsHide: true });
    } catch {
      resolve(null);
      return;
    }
    let stdout = '';
    let stderr = '';
    const timer = setTimeout(() => child.kill('SIGKILL'), timeoutMs);
    child.stdout.on('data', (d) => { stdout += d; });
    child.stderr.on('data', (d) => { stderr += d; });
    child.on('error', () => {
      clearTimeout(timer);
      resolve(null);
    });
    child.on('close', (code) => {
      clearTimeout(timer);
      resolve({ code, stdout, stderr });
    });
  });
}

/**
 * Runs a candidate binary and inspects its build.
 * @param {string} bin
 */
export async function probeFfmpeg(bin) {
  const version = await captureOutput(bin, ['-hide_banner', '-version']);
  if (!version || version.code !== 0 || !/ffmpeg version/i.test(version.stdout)) return null;
  const [encoders, filters] = await Promise.all([
    captureOutput(bin, ['-hide_banner', '-encoders']),
    captureOutput(bin, ['-hide_banner', '-filters']),
  ]);
  const enc = encoders?.stdout ?? '';
  const fil = filters?.stdout ?? '';
  return {
    version: /ffmpeg version (\S+)/i.exec(version.stdout)?.[1] ?? 'unknown',
    libx264: /^\s*V\S*\s+libx264\b/m.test(enc),
    gif: /^\s*V\S*\s+gif\b/m.test(enc),
    palette: /\bpalettegen\b/.test(fil) && /\bpaletteuse\b/.test(fil),
    overlay: /\boverlay\b/.test(fil),
  };
}

/**
 * OS-specific installation instructions, current platform first.
 * @param {string} [platform]
 */
export function ffmpegInstallHint(platform = process.platform) {
  const sections = {
    darwin: ['macOS     brew install ffmpeg            (Homebrew: https://brew.sh)'],
    linux: [
      'Ubuntu    sudo apt update && sudo apt install -y ffmpeg',
      'Fedora    sudo dnf install -y ffmpeg         (H.264 needs RPM Fusion, see README)',
      'Arch      sudo pacman -S ffmpeg',
    ],
    win32: [
      'Windows   winget install --id Gyan.FFmpeg -e',
      '          or: choco install ffmpeg  /  scoop install ffmpeg',
    ],
  };
  const order = [platform, ...Object.keys(sections).filter((p) => p !== platform)].filter((p) => sections[p]);
  return [
    'Install ffmpeg, then open a new terminal:',
    '',
    ...order.flatMap((p) => sections[p].map((l) => `  ${l}`)),
    '',
    'Verify with `ffmpeg -version`. Installed somewhere unusual? Set FFMPEG_PATH=/path/to/ffmpeg',
  ].join('\n');
}

/**
 * Finds a working ffmpeg and checks it can produce the requested format.
 *
 * @param {'mp4' | 'gif'} format
 * @returns {Promise<{ path: string, source: string, version: string }>}
 */
export async function locateFfmpeg(format = 'mp4') {
  const candidates = [];
  const seen = new Set();
  const add = (file, source) => {
    if (!file) return;
    const key = path.resolve(file);
    if (seen.has(key)) return;
    seen.add(key);
    candidates.push({ path: file, source });
  };
  if (process.env.FFMPEG_PATH) {
    // An explicit setting is authoritative: never silently fall back to another binary.
    add(process.env.FFMPEG_PATH, 'FFMPEG_PATH');
  } else {
    add(findExecutable('ffmpeg'), 'PATH');
    for (const loc of commonLocations()) if (isExecutableFile(loc)) add(loc, 'common install location');
  }

  for (const candidate of candidates) {
    const info = await probeFfmpeg(candidate.path);
    if (!info) continue;
    if (!info.overlay) {
      throw new AnimatorError(`The ffmpeg at ${candidate.path} was built without the "overlay" filter.`, {
        code: 'E_FFMPEG_CAPABILITY',
        hint: ffmpegInstallHint(),
      });
    }
    if (format === 'mp4' && !info.libx264) {
      throw new AnimatorError(`ffmpeg ${info.version} (${candidate.path}) has no H.264 encoder (libx264).`, {
        code: 'E_FFMPEG_NO_X264',
        hint: [
          'Your ffmpeg build omits libx264 (common with Fedora\'s "ffmpeg-free" package).',
          'Fedora: enable RPM Fusion, then run  sudo dnf swap ffmpeg-free ffmpeg --allowerasing',
          'Other systems: install the full ffmpeg build from your package manager or https://ffmpeg.org/download.html',
          'Or export a GIF instead:  git-commit-animator -o animation.gif',
        ].join('\n'),
      });
    }
    if (format === 'gif' && (!info.gif || !info.palette)) {
      throw new AnimatorError(`ffmpeg ${info.version} cannot produce optimized GIFs (missing gif encoder or palette filters).`, {
        code: 'E_FFMPEG_CAPABILITY',
        hint: ffmpegInstallHint(),
      });
    }
    return { ...candidate, version: info.version };
  }

  if (process.env.FFMPEG_PATH) {
    throw new AnimatorError(`FFMPEG_PATH is set to "${process.env.FFMPEG_PATH}", but that is not a working ffmpeg binary.`, {
      code: 'E_FFMPEG_MISSING',
      hint: `Fix or unset FFMPEG_PATH.\n\n${ffmpegInstallHint()}`,
    });
  }
  throw new AnimatorError('ffmpeg is required to encode videos, but it was not found on this system.', {
    code: 'E_FFMPEG_MISSING',
    hint: ffmpegInstallHint(),
  });
}

/**
 * Runs a prepared fluent-ffmpeg command with progress reporting, abort
 * support and guaranteed process cleanup.
 */
function runCommand(command, { output, totalFrames, onProgress, signal, onDebug, phase }) {
  return new Promise((resolve, reject) => {
    let finished = false;
    const kill = () => {
      try {
        command.kill('SIGKILL');
      } catch {
        // already exited
      }
    };
    const unregister = registerCleanup(`ffmpeg:${phase}`, kill, () => {
      try {
        command.ffmpegProc?.kill('SIGKILL');
      } catch {
        // ignore
      }
    });
    const onAbort = () => kill();
    signal?.addEventListener('abort', onAbort, { once: true });

    const done = (error) => {
      if (finished) return;
      finished = true;
      unregister();
      signal?.removeEventListener('abort', onAbort);
      if (error) reject(error);
      else resolve();
    };

    command
      .on('start', (commandLine) => onDebug?.(`ffmpeg ${phase}: ${commandLine}`))
      .on('stderr', (line) => {
        const m = /frame=\s*(\d+)/.exec(line);
        if (m) onProgress?.(Math.min(totalFrames, Number(m[1])));
      })
      .on('error', (error, _stdout, stderr) => {
        if (signal?.aborted) {
          done(new AbortError());
          return;
        }
        const tail = String(stderr ?? '').trim().split('\n').slice(-15).join('\n');
        done(new AnimatorError(`ffmpeg failed while ${phase}: ${String(error.message).split('\n')[0]}`, {
          code: 'E_FFMPEG_FAILED',
          hint: 'Run again with --verbose to see the full ffmpeg log.',
          details: tail,
          cause: error,
        }));
      })
      .on('end', () => {
        onProgress?.(totalFrames);
        done();
      })
      .save(output);
  });
}

/**
 * Creates a command whose first two inputs are the static background and the
 * window frame sequence.
 */
function compositeCommand(ffmpegPath, { framesDir, background, fps }) {
  const command = ffmpeg();
  command.setFfmpegPath(ffmpegPath);
  command.input(background).inputOptions(['-framerate', String(fps)]);
  command.input(path.join(framesDir, FRAME_PATTERN)).inputOptions(['-framerate', String(fps), '-start_number', '0']);
  return command;
}

/**
 * Filter graph prefix that composites the window frames onto the background.
 *
 * - The background is decoded once and repeated in memory by the `loop`
 *   filter (≈20% faster than re-reading the PNG with `-loop 1`).
 * - Its timestamps are regenerated as exact integers (`settb` + `setpts=N`).
 *   An expression like N/FRAME_RATE/TB would accumulate floating-point error
 *   and occasionally emit duplicate PTS, which makes ffmpeg drop one frame
 *   and duplicate another, i.e. a visible stutter in the typing.
 * - Compositing happens in RGB so no chroma subsampling occurs before the
 *   single, carefully configured RGB→YUV conversion.
 */
function overlayFilter(clip, fps) {
  return `[0:v]loop=loop=-1:size=1:start=0,settb=1/${fps},setpts=N[bg];`
    + `[bg][1:v]overlay=x=${clip.x}:y=${clip.y}:format=rgb:shortest=1:eof_action=endall`;
}

/**
 * Encodes the rendered frames.
 *
 * @param {object} options
 * @param {string} options.ffmpegPath
 * @param {'mp4' | 'gif'} options.format
 * @param {string} options.framesDir Folder containing frame_%06d.png.
 * @param {string} options.background Full-canvas background PNG.
 * @param {{ x: number, y: number, width: number, height: number }} options.clip Window rectangle the frames cover.
 * @param {number} options.fps
 * @param {number} options.width
 * @param {number} options.height
 * @param {number} options.frameCount
 * @param {string} options.output Temporary output path.
 * @param {number} [options.crf]
 * @param {(fraction: number) => void} [options.onProgress] 0..1 overall progress.
 * @param {AbortSignal} [options.signal]
 * @param {(msg: string) => void} [options.onDebug]
 */
export async function encodeVideo(options) {
  const { format } = options;
  if (format === 'gif') return encodeGif(options);
  return encodeMp4(options);
}

async function encodeMp4({ ffmpegPath, framesDir, background, clip, fps, width, height, frameCount, output, crf = 18, onProgress, signal, onDebug }) {
  const command = compositeCommand(ffmpegPath, { framesDir, background, fps });
  command
    .complexFilter([
      `${overlayFilter(clip, fps)},scale=${width}:${height}:flags=lanczos+accurate_rnd+full_chroma_int:out_color_matrix=bt709:out_range=tv,format=yuv420p[v]`,
    ], 'v')
    .videoCodec('libx264')
    .outputOptions([
      '-preset', 'medium',
      '-tune', 'animation',
      '-crf', String(crf),
      '-profile:v', 'high',
      '-pix_fmt', 'yuv420p',
      '-r', String(fps),
      '-colorspace', 'bt709',
      '-color_primaries', 'bt709',
      '-color_trc', 'iec61966-2-1',
      '-color_range', 'tv',
      '-movflags', '+faststart',
      '-an',
    ])
    .format('mp4');

  await runCommand(command, {
    output,
    totalFrames: frameCount,
    onProgress: (frames) => onProgress?.(frames / frameCount),
    signal,
    onDebug,
    phase: 'encoding H.264',
  });
}

async function encodeGif({ ffmpegPath, framesDir, background, clip, fps, frameCount, output, onProgress, signal, onDebug }) {
  // Pass 1: build an optimal 256-color palette from every composited frame.
  // A two-pass approach (instead of split+palettegen in one graph) avoids
  // buffering the entire video in RAM while palettegen waits for EOF.
  const palette = path.join(path.dirname(output), 'palette.png');
  const pass1 = compositeCommand(ffmpegPath, { framesDir, background, fps });
  pass1
    .complexFilter([`${overlayFilter(clip, fps)},palettegen=max_colors=256:stats_mode=full:reserve_transparent=0[p]`], 'p')
    .outputOptions(['-frames:v', '1', '-update', '1']);
  await runCommand(pass1, {
    output: palette,
    totalFrames: frameCount,
    onProgress: (frames) => onProgress?.(0.35 * (frames / frameCount)),
    signal,
    onDebug,
    phase: 'building the GIF palette',
  });

  // Pass 2: map frames to the palette. diff_mode=rectangle only re-dithers
  // the region that changed, which keeps static areas stable (no dither
  // "crawl") and makes typing animations dramatically smaller.
  const pass2 = compositeCommand(ffmpegPath, { framesDir, background, fps });
  pass2
    .input(palette)
    .complexFilter([`${overlayFilter(clip, fps)}[c];[c][2:v]paletteuse=dither=sierra2_4a:diff_mode=rectangle[g]`], 'g')
    .outputOptions(['-loop', '0', '-r', String(fps)])
    .format('gif');
  await runCommand(pass2, {
    output,
    totalFrames: frameCount,
    onProgress: (frames) => onProgress?.(0.35 + 0.65 * (frames / frameCount)),
    signal,
    onDebug,
    phase: 'encoding the GIF',
  });
  await fsp.rm(palette, { force: true });
}

/**
 * Moves the finished video to its destination. Uses an atomic rename when
 * possible and falls back to copy+delete across devices.
 *
 * @param {string} tempFile
 * @param {string} destination
 */
export async function finalizeOutput(tempFile, destination) {
  try {
    await fsp.mkdir(path.dirname(destination), { recursive: true });
  } catch (error) {
    throw new AnimatorError(`Cannot create the output folder ${path.dirname(destination)}: ${error.message}`, {
      code: 'E_OUTPUT_DIR',
      cause: error,
    });
  }
  try {
    await fsp.rename(tempFile, destination);
  } catch (error) {
    if (error.code === 'EXDEV') {
      try {
        await fsp.copyFile(tempFile, destination);
        await fsp.rm(tempFile, { force: true });
        return;
      } catch (copyError) {
        error = copyError;
      }
    }
    if (['EBUSY', 'EPERM', 'EACCES'].includes(error.code)) {
      throw new AnimatorError(`Cannot write ${destination}: the file is in use or not writable.`, {
        code: 'E_OUTPUT_LOCKED',
        hint: 'Close any program that has the file open, or choose another name with --output.',
        cause: error,
      });
    }
    throw new AnimatorError(`Cannot write ${destination}: ${error.message}`, { code: 'E_OUTPUT_WRITE', cause: error });
  }
}
