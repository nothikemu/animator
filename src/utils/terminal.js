/**
 * Dependency-free terminal UI: colors, phase headers, progress bars,
 * spinners and result boxes.
 *
 * All human-facing output goes to stderr so stdout stays clean for scripting
 * (in --quiet mode the CLI prints only the output path to stdout). Colors and
 * cursor tricks are disabled automatically when the stream is not a TTY, when
 * NO_COLOR is set, or for TERM=dumb; FORCE_COLOR re-enables colors.
 */

import process from 'node:process';

const ESC = '\x1b[';
const ANSI_RE = /\x1b\[[0-9;?]*[A-Za-z]/g;

/**
 * @param {NodeJS.WriteStream} stream
 * @param {NodeJS.ProcessEnv} [env]
 */
export function supportsColor(stream, env = process.env) {
  if (env.NO_COLOR !== undefined && env.NO_COLOR !== '') return false;
  if (env.FORCE_COLOR !== undefined) return env.FORCE_COLOR !== '0' && env.FORCE_COLOR !== 'false';
  if (!stream?.isTTY) return false;
  return env.TERM !== 'dumb';
}

/**
 * Best-effort detection of terminals that render emoji and box drawing.
 * @param {NodeJS.ProcessEnv} [env]
 * @param {string} [platform]
 */
export function supportsUnicode(env = process.env, platform = process.platform) {
  if (platform !== 'win32') return env.TERM !== 'linux';
  return Boolean(env.WT_SESSION || env.TERM_PROGRAM === 'vscode' || env.ConEmuTask || env.TERMINUS_SUBLIME
    || env.TERM === 'xterm-256color' || env.TERM === 'alacritty');
}

/** @param {string} text */
export function stripAnsi(text) {
  return String(text).replace(ANSI_RE, '');
}

/** @param {boolean} enabled */
export function createStyles(enabled) {
  const wrap = (open, close) => (enabled ? (s) => `${ESC}${open}m${s}${ESC}${close}m` : (s) => String(s));
  return {
    bold: wrap(1, 22),
    dim: wrap(2, 22),
    italic: wrap(3, 23),
    underline: wrap(4, 24),
    red: wrap(31, 39),
    green: wrap(32, 39),
    yellow: wrap(33, 39),
    blue: wrap(34, 39),
    magenta: wrap(35, 39),
    cyan: wrap(36, 39),
    gray: wrap(90, 39),
    brightMagenta: wrap(95, 39),
  };
}

/** @param {number} ms */
export function formatDuration(ms) {
  if (!Number.isFinite(ms) || ms < 0) return '--';
  if (ms < 1000) return `${Math.round(ms)}ms`;
  const s = ms / 1000;
  if (s < 60) return `${s.toFixed(s < 10 ? 1 : 0)}s`;
  const m = Math.floor(s / 60);
  return `${m}m ${String(Math.round(s % 60)).padStart(2, '0')}s`;
}

/** @param {number} bytes */
export function formatBytes(bytes) {
  if (bytes < 1024) return `${bytes} B`;
  const units = ['KB', 'MB', 'GB'];
  let value = bytes / 1024;
  let unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit++;
  }
  return `${value.toFixed(value < 10 ? 1 : 0)} ${units[unit]}`;
}

const ICONS = {
  analyze: ['📂', '[git]'],
  render: ['🎬', '[render]'],
  encode: ['🚀', '[encode]'],
  success: ['✔', 'OK'],
  failure: ['✖', 'X'],
  warning: ['⚠', '!'],
  bullet: ['•', '*'],
  arrow: ['→', '->'],
  spark: ['✨', '*'],
  skip: ['↷', '-'],
};

const SPINNER_FRAMES = ['⠋', '⠙', '⠹', '⠸', '⠼', '⠴', '⠦', '⠧', '⠇', '⠏'];
const SPINNER_FRAMES_ASCII = ['-', '\\', '|', '/'];
const PARTIAL_BLOCKS = ['', '▏', '▎', '▍', '▌', '▋', '▊', '▉'];

export class Terminal {
  /**
   * @param {object} [options]
   * @param {NodeJS.WriteStream} [options.stream]
   * @param {boolean} [options.quiet]
   * @param {boolean} [options.verbose]
   * @param {boolean} [options.color]
   * @param {boolean} [options.unicode]
   */
  constructor({ stream = process.stderr, quiet = false, verbose = false, color, unicode } = {}) {
    this.stream = stream;
    this.quiet = quiet;
    this.verbose = verbose;
    this.interactive = Boolean(stream.isTTY) && process.env.TERM !== 'dumb' && !process.env.CI;
    this.color = color ?? supportsColor(stream);
    this.unicode = unicode ?? supportsUnicode();
    this.s = createStyles(this.color);
    this.cursorHidden = false;
    this.liveLine = false;
  }

  /** @param {keyof typeof ICONS} name */
  icon(name) {
    const [fancy, plain] = ICONS[name];
    return this.unicode ? fancy : plain;
  }

  get columns() {
    return Math.max(40, Math.min(this.stream.columns || 80, 120));
  }

  /** Writes a full line, clearing any live progress line first. */
  line(text = '') {
    if (this.quiet) return;
    this.clearLive();
    this.stream.write(`${text}\n`);
  }

  clearLive() {
    if (this.liveLine && this.interactive) this.stream.write(`\r${ESC}2K`);
    this.liveLine = false;
  }

  live(text) {
    if (this.quiet || !this.interactive) return;
    this.stream.write(`\r${ESC}2K${text}`);
    this.liveLine = true;
  }

  hideCursor() {
    if (this.interactive && !this.cursorHidden && !this.quiet) {
      this.stream.write(`${ESC}?25l`);
      this.cursorHidden = true;
    }
  }

  showCursor() {
    if (this.cursorHidden) {
      this.stream.write(`${ESC}?25h`);
      this.cursorHidden = false;
    }
  }

  /** Restores the terminal to a sane state (used on exit and abort). */
  restore() {
    this.clearLive();
    this.showCursor();
  }

  banner(version) {
    const { s } = this;
    this.line();
    this.line(`  ${s.bold(s.brightMagenta(this.unicode ? '◆ Git-Commit Animator' : '* Git-Commit Animator'))} ${s.dim(`v${version}`)}`);
    this.line(`  ${s.dim('Turn any commit into a typing animation for your README.')}`);
  }

  /**
   * @param {number} index
   * @param {number} total
   * @param {keyof typeof ICONS} icon
   * @param {string} title
   */
  phase(index, total, icon, title) {
    const { s } = this;
    this.line();
    this.line(`${s.bold(s.cyan(`[${index}/${total}]`))} ${this.icon(icon)} ${s.bold(title)}`);
  }

  detail(label, value) {
    this.line(`      ${this.s.dim(String(label).padEnd(10))} ${value}`);
  }

  item(text) {
    this.line(`      ${this.s.dim(this.icon('bullet'))} ${text}`);
  }

  info(text) {
    this.line(`      ${text}`);
  }

  warn(text) {
    this.line(`      ${this.s.yellow(`${this.icon('warning')} ${text}`)}`);
  }

  debug(text) {
    if (this.verbose) this.line(this.s.gray(`      [debug] ${text}`));
  }

  /**
   * @param {object} options
   * @param {number} options.total
   * @param {string} [options.unit]
   */
  progress({ total, unit = 'frames' }) {
    return new ProgressBar(this, { total, unit });
  }

  /** @param {string} text */
  spinner(text) {
    return new Spinner(this, text);
  }

  /**
   * Prints the final success block.
   * @param {string} title
   * @param {Array<[string, string]>} rows
   * @param {string} filePath
   */
  success(title, rows, filePath) {
    const { s } = this;
    const width = Math.min(this.columns - 4, 64);
    const [tl, tr, bl, br, h, v] = this.unicode ? ['╭', '╮', '╰', '╯', '─', '│'] : ['+', '+', '+', '+', '-', '|'];
    const heading = ` ${this.icon('success')} ${title}`;
    const pad = Math.max(0, width - stripAnsi(heading).length);
    this.line();
    this.line(`  ${s.green(tl + h.repeat(width) + tr)}`);
    this.line(`  ${s.green(v)}${s.bold(s.green(heading))}${' '.repeat(pad)}${s.green(v)}`);
    this.line(`  ${s.green(bl + h.repeat(width) + br)}`);
    this.line();
    this.line(`    ${s.dim('Saved to'.padEnd(10))} ${s.bold(s.cyan(filePath))}`);
    for (const [label, value] of rows) this.line(`    ${s.dim(label.padEnd(10))} ${value}`);
    this.line();
  }

  /**
   * Prints a friendly error. Stack traces only appear with --verbose.
   * @param {any} error
   */
  error(error) {
    const { s } = this;
    this.clearLive();
    const out = (text = '') => this.stream.write(`${text}\n`);
    out();
    out(`  ${s.bold(s.red(`${this.icon('failure')} ${error?.message ?? String(error)}`))}`);
    if (error?.hint) {
      out();
      for (const hintLine of String(error.hint).split('\n')) out(`    ${hintLine}`);
    }
    if (this.verbose) {
      if (error?.details) {
        out();
        out(s.gray(String(error.details).split('\n').slice(-25).map((l) => `    ${l}`).join('\n')));
      }
      if (error?.stack) {
        out();
        out(s.gray(error.stack.split('\n').map((l) => `    ${l}`).join('\n')));
      }
    } else if (!error?.code || error.code === 'E_INTERNAL') {
      out();
      out(s.dim('    Run again with --verbose for the full stack trace.'));
    }
    out();
  }
}

export class ProgressBar {
  /**
   * @param {Terminal} term
   * @param {{ total: number, unit: string }} options
   */
  constructor(term, { total, unit }) {
    this.term = term;
    this.total = Math.max(1, total);
    this.unit = unit;
    this.current = 0;
    this.startedAt = performance.now();
    this.lastRender = 0;
    this.lastBucket = -1;
    this.rate = 0;
    this.lastSample = { t: this.startedAt, v: 0 };
    term.hideCursor();
    this.render(true);
  }

  /** @param {number} value */
  update(value) {
    this.current = Math.min(this.total, Math.max(this.current, value));
    const now = performance.now();
    const dt = now - this.lastSample.t;
    if (dt >= 250) {
      const instant = ((this.current - this.lastSample.v) / dt) * 1000;
      this.rate = this.rate ? this.rate * 0.7 + instant * 0.3 : instant;
      this.lastSample = { t: now, v: this.current };
    }
    if (now - this.lastRender >= 80 || this.current === this.total) this.render();
  }

  render(force = false) {
    const { term } = this;
    const { s } = term;
    this.lastRender = performance.now();
    const ratio = this.current / this.total;
    const percent = Math.floor(ratio * 100);

    if (!term.interactive) {
      const bucket = Math.floor(percent / 25);
      if (bucket !== this.lastBucket && (force || this.current > 0)) {
        this.lastBucket = bucket;
        term.line(`      ${String(percent).padStart(3)}%  ${this.current}/${this.total} ${this.unit}`);
      }
      return;
    }

    const elapsed = performance.now() - this.startedAt;
    const rate = this.rate || (elapsed > 0 ? (this.current / elapsed) * 1000 : 0);
    const eta = rate > 0 ? ((this.total - this.current) / rate) * 1000 : NaN;
    const counts = `${this.current}/${this.total} ${this.unit}`;
    const stats = `${rate.toFixed(1)}/s  ETA ${formatDuration(eta)}`;
    const reserved = 6 + 6 + counts.length + 2 + stats.length + 4;
    const width = Math.max(10, Math.min(36, term.columns - reserved));
    term.live(`      ${this.bar(ratio, width)} ${s.bold(`${String(percent).padStart(3)}%`)}  ${counts}  ${s.dim(stats)}`);
  }

  bar(ratio, width) {
    const { term } = this;
    const { s } = term;
    if (!term.unicode) {
      const filled = Math.round(ratio * width);
      return `[${'#'.repeat(filled)}${'-'.repeat(width - filled)}]`;
    }
    const exact = ratio * width;
    const full = Math.floor(exact);
    const partial = full < width ? PARTIAL_BLOCKS[Math.floor((exact - full) * 8)] : '';
    const empty = Math.max(0, width - full - (partial ? 1 : 0));
    return s.magenta('█'.repeat(full) + partial) + s.dim('░'.repeat(empty));
  }

  /** @param {string} [summary] */
  done(summary) {
    this.current = this.total;
    if (this.term.interactive) this.render(true);
    this.term.clearLive();
    this.term.showCursor();
    const elapsed = performance.now() - this.startedAt;
    this.term.line(`      ${this.term.s.green(this.term.icon('success'))} ${summary ?? `${this.total} ${this.unit}`} ${this.term.s.dim(`in ${formatDuration(elapsed)}`)}`);
  }

  fail() {
    this.term.clearLive();
    this.term.showCursor();
  }
}

export class Spinner {
  /**
   * @param {Terminal} term
   * @param {string} text
   */
  constructor(term, text) {
    this.term = term;
    this.text = text;
    this.frame = 0;
    this.timer = null;
    this.startedAt = performance.now();
    if (term.quiet) return;
    if (!term.interactive) {
      term.line(`      ${text}`);
      return;
    }
    term.hideCursor();
    const frames = term.unicode ? SPINNER_FRAMES : SPINNER_FRAMES_ASCII;
    const tick = () => {
      term.live(`      ${term.s.magenta(frames[this.frame++ % frames.length])} ${this.text}`);
    };
    tick();
    this.timer = setInterval(tick, 80);
    this.timer.unref?.();
  }

  /** @param {string} text */
  setText(text) {
    this.text = text;
  }

  /**
   * @param {string} [text]
   * @param {boolean} [ok]
   */
  stop(text, ok = true) {
    if (this.timer) clearInterval(this.timer);
    this.timer = null;
    const { term } = this;
    if (term.quiet) return;
    term.clearLive();
    term.showCursor();
    if (term.interactive || text) {
      const mark = ok ? term.s.green(term.icon('success')) : term.s.red(term.icon('failure'));
      term.line(`      ${mark} ${text ?? this.text} ${term.s.dim(`(${formatDuration(performance.now() - this.startedAt)})`)}`);
    }
  }
}
