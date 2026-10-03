/**
 * Frame renderer: headless Chrome + a static HTML editor template.
 *
 * Architecture
 * ------------
 * - The page is a "dumb" view: Node computes every frame (see timeline.js)
 *   and the page just paints the rows it is told to. Views are absolute, so
 *   any page can render any frame.
 * - A pool of independent browser processes renders contiguous slices of each
 *   batch in parallel. Separate processes (not tabs) are used because Chrome
 *   serializes compositing per process; with N processes throughput scales
 *   almost linearly with cores.
 * - Frames are processed through a strict batched queue: the frame generator
 *   is consumed lazily, at most `batchSize` views are in memory, each worker
 *   holds at most one screenshot plus one pending disk write, and a batch must
 *   be fully flushed before the next starts. Memory use is therefore constant
 *   regardless of video length.
 * - Identical consecutive frames (pauses, cursor-blink plateaus, sub-frame
 *   keystroke gaps) are never re-rendered: they become hard links to the
 *   previous PNG, which costs no CPU and no disk space.
 * - Only the editor window is captured per frame (static/dynamic layer
 *   separation). The gradient background and drop shadow never change, so
 *   they are captured once and composited back by ffmpeg. This cuts per-frame
 *   PNG size by ~5x and capture time by ~30%.
 * - Crashed browser processes are restarted and their remaining jobs retried.
 */

import { spawn } from 'node:child_process';
import fs from 'node:fs';
import fsp from 'node:fs/promises';
import { createRequire } from 'node:module';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import puppeteer from 'puppeteer';
import { AbortError, AnimatorError, throwIfAborted } from '../utils/errors.js';
import { registerCleanup } from '../utils/cleanup.js';
import { TOKEN_CLASSES } from './highlighter.js';

export const FRAME_PATTERN = 'frame_%06d.png';
export const BACKGROUND_FILE = 'background.png';

/** @param {number} index */
export const frameFileName = (index) => `frame_${String(index).padStart(6, '0')}.png`;

const FONT_DIR = fileURLToPath(new URL('../../assets/fonts/', import.meta.url));
const FONT_FACES = [
  { file: 'jetbrains-mono-latin-400-normal.woff2', weight: 400, range: 'U+0000-00FF,U+0131,U+0152-0153,U+02BB-02BC,U+02C6,U+02DA,U+02DC,U+0304,U+0308,U+0329,U+2000-206F,U+20AC,U+2122,U+2191,U+2193,U+2212,U+2215,U+FEFF,U+FFFD' },
  { file: 'jetbrains-mono-latin-ext-400-normal.woff2', weight: 400, range: 'U+0100-02BA,U+02BD-02C5,U+02C7-02CC,U+02CE-02D7,U+02DD-02FF,U+0304,U+0308,U+0329,U+1D00-1DBF,U+1E00-1E9F,U+1EF2-1EFF,U+2020,U+20A0-20AB,U+20AD-20C0,U+2113,U+2C60-2C7F,U+A720-A7FF' },
  { file: 'jetbrains-mono-latin-700-normal.woff2', weight: 700, range: 'U+0000-00FF,U+0131,U+0152-0153,U+02BB-02BC,U+02C6,U+02DA,U+02DC,U+0304,U+0308,U+0329,U+2000-206F,U+20AC,U+2122,U+2191,U+2193,U+2212,U+2215,U+FEFF,U+FFFD' },
  { file: 'jetbrains-mono-latin-ext-700-normal.woff2', weight: 700, range: 'U+0100-02BA,U+02BD-02C5,U+02C7-02CC,U+02CE-02D7,U+02DD-02FF,U+0304,U+0308,U+0329,U+1D00-1DBF,U+1E00-1E9F,U+1EF2-1EFF,U+2020,U+20A0-20AB,U+20AD-20C0,U+2113,U+2C60-2C7F,U+A720-A7FF' },
];

const MONO_STACK = "'JetBrains Mono', 'Fira Code', 'SF Mono', Menlo, Consolas, 'Liberation Mono', 'DejaVu Sans Mono', 'Courier New', monospace";
const UI_STACK = "Inter, -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, 'Helvetica Neue', 'Noto Sans', 'Liberation Sans', Arial, sans-serif";

/** Dot colors shown next to file names in the tab bar. */
const LANGUAGE_COLORS = {
  JavaScript: '#f7df1e', TypeScript: '#3178c6', Python: '#3776ab', Ruby: '#cc342d', Go: '#00add8',
  Rust: '#dea584', Java: '#b07219', Kotlin: '#a97bff', Swift: '#f05138', C: '#a8b9cc', 'C++': '#f34b7d',
  'C#': '#178600', PHP: '#777bb4', Dart: '#00b4ab', Scala: '#dc322f', Elixir: '#6e4a7e', Lua: '#000080',
  SQL: '#e38c00', Shell: '#89e051', Dockerfile: '#384d54', Makefile: '#427819', JSON: '#cbcb41',
  YAML: '#cb171e', TOML: '#9c4221', INI: '#d1dbe0', CSS: '#563d7c', SCSS: '#c6538c', HTML: '#e34c26',
  XML: '#0060ac', Vue: '#41b883', Markdown: '#083fa1', 'Plain Text': '#9ca3af',
};

const MAX_WORKER_RESTARTS = 2;
const RECYCLE_PAGE_EVERY = 1500;
const LINK_CONCURRENCY = 32;
const WORKER_MEMORY_BUDGET = 400 * 1024 * 1024;

/**
 * Picks a worker count from CPU cores and free memory.
 * @returns {number}
 */
export function defaultWorkerCount() {
  const cores = typeof os.availableParallelism === 'function' ? os.availableParallelism() : os.cpus().length;
  const byCpu = Math.max(1, Math.min(4, cores - 1));
  const byMemory = Math.max(1, Math.floor(os.freemem() / WORKER_MEMORY_BUDGET));
  return Math.max(1, Math.min(byCpu, byMemory));
}

/**
 * Computes the pixel layout of the canvas. All values are integers so the
 * editor window lands exactly on device pixels, which keeps text crisp and
 * makes the window clip rectangle exact for compositing.
 *
 * @param {{ width: number, height: number, fontSize?: number }} options
 */
export function computeLayout({ width, height, fontSize = 22 }) {
  const s = Math.min(width / 1920, height / 1080);
  const px = (v) => Math.max(1, Math.round(v * s));
  const padX = Math.round(width * 0.075);
  const padY = Math.round(height * 0.075);
  const windowRect = { x: padX, y: padY, width: width - 2 * padX, height: height - 2 * padY };
  const titleH = px(44);
  const tabH = px(40);
  const statusH = px(30);
  const font = Math.max(8, Math.round(fontSize * s * 4) / 4);
  const lineH = Math.max(10, Math.round(font * 1.6));
  const editorPadTop = px(14);
  const editorHeight = windowRect.height - titleH - tabH - statusH;
  return {
    width,
    height,
    scale: s,
    px,
    window: windowRect,
    titleH,
    tabH,
    statusH,
    fontSize: font,
    lineHeight: lineH,
    editorPadTop,
    editorHeight,
    visibleLines: (editorHeight - editorPadTop) / lineH,
  };
}

function rgbaParts(color) {
  const m = /rgba?\(\s*([\d.]+)\s*,\s*([\d.]+)\s*,\s*([\d.]+)\s*(?:,\s*([\d.]+)\s*)?\)/.exec(color);
  if (m) return { rgb: `${m[1]}, ${m[2]}, ${m[3]}`, alpha: m[4] === undefined ? 1 : Number(m[4]) };
  const hex = /^#([\da-f]{6})$/i.exec(color);
  if (hex) {
    const n = parseInt(hex[1], 16);
    return { rgb: `${(n >> 16) & 255}, ${(n >> 8) & 255}, ${n & 255}`, alpha: 1 };
  }
  return { rgb: '239, 68, 68', alpha: 0.2 };
}

let fontCssCache = null;
function fontFaceCss() {
  if (fontCssCache !== null) return fontCssCache;
  fontCssCache = FONT_FACES.map(({ file, weight, range }) => {
    try {
      const data = fs.readFileSync(path.join(FONT_DIR, file)).toString('base64');
      return `@font-face{font-family:'JetBrains Mono';font-style:normal;font-weight:${weight};font-display:block;src:url(data:font/woff2;base64,${data}) format('woff2');unicode-range:${range}}`;
    } catch {
      // Bundled font missing: fall back to the system monospace stack.
      return '';
    }
  }).join('\n');
  return fontCssCache;
}

/**
 * Builds the static HTML orchestration page.
 *
 * @param {object} options
 * @param {ReturnType<typeof computeLayout>} options.layout
 * @param {any} options.theme Resolved theme from themes.js.
 */
export function buildTemplate({ layout, theme }) {
  const L = layout;
  const { px } = L;
  const removed = rgbaParts(theme.removed);
  const removedMarker = rgbaParts(theme.removedMarker);
  const tokenCss = TOKEN_CLASSES.map((cls) => `.t-${cls}{color:${theme.tokens[cls]}}`).join('');

  const css = `
${fontFaceCss()}
:root{
  --bg-from:${theme.background[0]};--bg-to:${theme.background[1] ?? theme.background[0]};
  --editor:${theme.editor};--chrome:${theme.chrome};--border:${theme.border};--title:${theme.title};
  --tab:${theme.tab};--tab-active:${theme.tabActive};--accent:${theme.accent};--text:${theme.text};
  --gutter:${theme.gutter};--gutter-active:${theme.gutterActive};--line-hl:${theme.lineHighlight};
  --cursor:${theme.cursor};--status:${theme.status};
  --added:${theme.added};--added-marker:${theme.addedMarker};
  --removed-rgb:${removed.rgb};--removed-alpha:${removed.alpha};--removed-marker-rgb:${removedMarker.rgb};
  --mono:${MONO_STACK};--ui:${UI_STACK};
  --win-x:${L.window.x}px;--win-y:${L.window.y}px;--win-w:${L.window.width}px;--win-h:${L.window.height}px;
  --radius:${px(12)}px;--sh-y:${px(25)}px;--sh-blur:${px(50)}px;--sh-spread:${-px(12)}px;
  --title-h:${L.titleH}px;--tab-h:${L.tabH}px;--status-h:${L.statusH}px;
  --font-size:${L.fontSize}px;--line-h:${L.lineHeight}px;--pad-top:${L.editorPadTop}px;
  --ui-size:${Math.max(9, L.scale * 15).toFixed(2)}px;--ui-size-sm:${Math.max(8, L.scale * 14).toFixed(2)}px;--ui-size-xs:${Math.max(8, L.scale * 13).toFixed(2)}px;
  --dot:${px(13)}px;--dot-gap:${px(9)}px;--pad:${px(18)}px;--tab-pad:${px(18)}px;--tab-gap:${px(9)}px;--tab-accent:${px(2)}px;
  --lang-dot:${px(9)}px;--gutter-l:${px(22)}px;--gutter-r:${px(22)}px;--code-pad:${px(4)}px;
  --marker:${px(3)}px;--caret-w:${Math.max(2, px(2))}px;--caret-inset:${Math.round(L.lineHeight * 0.16)}px;
}
*{box-sizing:border-box;margin:0;padding:0}
html,body{width:100%;height:100%;overflow:hidden}
body{background:linear-gradient(135deg,var(--bg-from) 0%,var(--bg-to) 100%);-webkit-font-smoothing:antialiased;text-rendering:optimizeLegibility}
#window{position:absolute;left:var(--win-x);top:var(--win-y);width:var(--win-w);height:var(--win-h);border-radius:var(--radius);background:var(--editor);box-shadow:0 var(--sh-y) var(--sh-blur) var(--sh-spread) rgba(0,0,0,.5);overflow:hidden;display:flex;flex-direction:column;isolation:isolate}
#window::after{content:'';position:absolute;inset:0;border-radius:inherit;box-shadow:inset 0 0 0 1px var(--border);pointer-events:none;z-index:5}
#titlebar{flex:none;height:var(--title-h);display:flex;align-items:center;position:relative;background:var(--chrome);padding:0 var(--pad)}
.dots{display:flex;gap:var(--dot-gap);position:relative;z-index:1}
.dot{width:var(--dot);height:var(--dot);border-radius:50%;box-shadow:inset 0 0 0 .5px rgba(0,0,0,.18)}
.dot.r{background:#ff5f57}.dot.y{background:#febc2e}.dot.g{background:#28c840}
#title{position:absolute;inset:0;display:flex;align-items:center;justify-content:center;padding:0 18%;font:500 var(--ui-size)/1 var(--ui);color:var(--title);white-space:nowrap;overflow:hidden}
#title .dir{opacity:.55}
#title .sep{opacity:.4;margin:0 .6em}
#tabs{flex:none;height:var(--tab-h);background:var(--chrome);position:relative;overflow:hidden;border-bottom:1px solid var(--border)}
#tabstrip{display:flex;height:100%;transform:translateX(var(--tab-offset,0px))}
.tab{flex:none;display:flex;align-items:center;gap:var(--tab-gap);padding:0 var(--tab-pad);font:var(--ui-size-sm)/1 var(--ui);color:var(--tab);border-right:1px solid var(--border);white-space:nowrap;position:relative}
.tab.active{background:var(--editor);color:var(--tab-active)}
.tab.active::before{content:'';position:absolute;left:0;right:0;top:0;height:var(--tab-accent);background:var(--accent)}
.tab .lang{width:var(--lang-dot);height:var(--lang-dot);border-radius:50%;flex:none}
.tab .stat{font-family:var(--mono);font-size:.86em;display:flex;gap:.5em}
.tab .add{color:#22c55e}.tab .del{color:#ef4444}
.tab .st{font-family:var(--mono);font-weight:700;font-size:.82em;opacity:.95}
.st-A{color:#22c55e}.st-M,.st-T{color:#e2b340}.st-D{color:#ef4444}.st-R,.st-C{color:#60a5fa}
#editor{flex:1;position:relative;overflow:hidden;font-family:var(--mono);font-size:var(--font-size);line-height:var(--line-h);color:var(--text);font-variant-ligatures:none;font-feature-settings:"liga" 0,"calt" 0;tab-size:4;-moz-tab-size:4}
#rows{position:absolute;inset:0}
.row{position:absolute;left:0;right:0;top:0;height:var(--line-h);display:flex;white-space:pre;overflow:hidden}
.ln{flex:none;width:calc(var(--digits,3) * 1ch + var(--gutter-l) + var(--gutter-r));padding-right:var(--gutter-r);text-align:right;color:var(--gutter)}
.code{flex:1;overflow:hidden;position:relative}
.in{display:inline-block;position:relative;padding-left:var(--code-pad);transform:translateX(var(--sx,0px))}
.row.cur{background-image:linear-gradient(var(--line-hl),var(--line-hl))}
.row.cur .ln{color:var(--gutter-active)}
.k-a{background-color:var(--added)}
.k-a .ln{box-shadow:inset var(--marker) 0 0 var(--added-marker)}
.k-d{background-color:rgba(var(--removed-rgb),calc(var(--removed-alpha) * var(--a,0)))}
.k-d .ln{box-shadow:inset var(--marker) 0 0 rgba(var(--removed-marker-rgb),var(--a,0))}
.caret{display:inline-block;position:relative;width:0;height:var(--line-h);vertical-align:top}
.caret::after{content:'';position:absolute;left:calc(var(--caret-w) / -2);top:var(--caret-inset);bottom:var(--caret-inset);width:var(--caret-w);border-radius:1px;background:var(--cursor)}
.caret.off::after{opacity:0}
#status{flex:none;height:var(--status-h);display:flex;align-items:center;justify-content:space-between;gap:2em;padding:0 var(--pad);background:var(--chrome);border-top:1px solid var(--border);font:var(--ui-size-xs)/1 var(--ui);color:var(--status);white-space:nowrap}
#status .left,#status .right{display:flex;align-items:center;gap:1.5em;overflow:hidden;min-width:0}
#status .right{flex:none}
#status .subject{overflow:hidden;text-overflow:ellipsis;opacity:.8;min-width:0}
#status .hash{font-family:var(--mono);font-size:.95em}
#status svg{width:1.15em;height:1.15em;margin-right:.4em;vertical-align:-.22em;fill:none;stroke:currentColor;stroke-width:2;stroke-linecap:round;stroke-linejoin:round}
${tokenCss}
${theme.italicComments ? '.t-com{font-style:italic}' : ''}
`;

  return `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta http-equiv="Content-Security-Policy" content="default-src 'none'; style-src 'unsafe-inline'; font-src data:; img-src data:; script-src 'unsafe-inline'">
<title>Git-Commit Animator</title>
<style>${css}</style>
</head>
<body>
<div id="window">
  <div id="titlebar"><div class="dots"><span class="dot r"></span><span class="dot y"></span><span class="dot g"></span></div><div id="title"></div></div>
  <div id="tabs"><div id="tabstrip"></div></div>
  <div id="editor"><div id="rows"></div></div>
  <div id="status"><div class="left" id="status-left"></div><div class="right" id="status-right"></div></div>
</div>
<script>(${pageRuntime.toString()})();</script>
</body>
</html>`;
}

/**
 * Runtime injected into the page. Must be fully self-contained: it is
 * serialized with Function#toString and executed inside Chrome.
 */
function pageRuntime() {
  const $ = (id) => document.getElementById(id);
  const ESC = { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' };
  const esc = (s) => String(s).replace(/[&<>"]/g, (c) => ESC[c]);
  const BRANCH_ICON = '<svg viewBox="0 0 24 24"><circle cx="6" cy="6" r="2.5"/><circle cx="6" cy="18" r="2.5"/><circle cx="18" cy="8" r="2.5"/><path d="M6 8.5v7M18 10.5c0 4-6 3-11 6"/></svg>';
  const COMMIT_ICON = '<svg viewBox="0 0 24 24"><circle cx="12" cy="12" r="3.5"/><path d="M2 12h6.5M15.5 12H22"/></svg>';

  const state = {
    config: null,
    files: new Map(),
    file: -1,
    payload: null,
    lengths: [],
    fullHtml: new Map(),
    lineH: 0,
    padTop: 0,
    charW: 0,
  };

  function tokensHtml(tokens, from, to) {
    let out = '';
    let pos = 0;
    for (let i = 0; i < tokens.length && pos < to; i++) {
      const cls = tokens[i][0];
      const text = tokens[i][1];
      const end = pos + text.length;
      if (end > from) {
        const piece = text.slice(Math.max(0, from - pos), Math.min(text.length, to - pos));
        if (piece) out += cls ? `<span class="t-${cls}">${esc(piece)}</span>` : esc(piece);
      }
      pos = end;
    }
    return out;
  }

  function activate(index) {
    const payload = state.files.get(index);
    if (!payload) throw new Error(`File ${index} was not loaded`);
    state.file = index;
    state.payload = payload;
    state.fullHtml = new Map();
    state.lengths = payload.rows.map((row) => row[1].reduce((n, t) => n + t[1].length, 0));
    const digits = Math.max(3, String(payload.rows.length).length);
    $('rows').style.setProperty('--digits', String(digits));

    const cfg = state.config;
    $('title').innerHTML = `${payload.directory ? `<span class="dir">${esc(payload.directory)}/</span>` : ''}${esc(payload.name)}<span class="sep">—</span>${esc(cfg.repoName)}`;

    const tabs = document.querySelectorAll('.tab');
    tabs.forEach((tab, i) => tab.classList.toggle('active', i === index));
    const strip = $('tabs').clientWidth;
    const tab = tabs[index];
    let offset = 0;
    if (tab) {
      const right = tab.offsetLeft + tab.offsetWidth;
      const margin = tab.offsetWidth * 0.5;
      if (right + margin > strip) offset = Math.min(tab.offsetLeft, right + margin - strip);
    }
    $('tabstrip').style.setProperty('--tab-offset', `${-Math.round(offset)}px`);
    $('lang').textContent = payload.language;
  }

  window.__gca = {
    async init(config) {
      state.config = config;
      state.lineH = config.lineHeight;
      state.padTop = config.padTop;

      $('tabstrip').innerHTML = config.tabs.map((t) => {
        const stat = `<span class="stat">${t.additions ? `<span class="add">+${t.additions}</span>` : ''}${t.deletions ? `<span class="del">−${t.deletions}</span>` : ''}</span>`;
        return `<div class="tab"><span class="lang" style="background:${esc(t.color)}"></span><span class="name">${esc(t.name)}</span>${stat}<span class="st st-${esc(t.status)}">${esc(t.status)}</span></div>`;
      }).join('');

      const left = [];
      if (config.branch) left.push(`<span>${BRANCH_ICON}${esc(config.branch)}</span>`);
      left.push(`<span class="hash">${COMMIT_ICON}${esc(config.baseHash)} → ${esc(config.targetHash)}</span>`);
      if (config.subject) left.push(`<span class="subject">${esc(config.subject)}</span>`);
      $('status-left').innerHTML = left.join('');
      $('status-right').innerHTML = '<span id="pos">Ln 1, Col 1</span><span>UTF-8</span><span>LF</span><span id="lang"></span>';

      await Promise.all([
        document.fonts.load(`400 ${config.fontSize}px "JetBrains Mono"`),
        document.fonts.load(`700 ${config.fontSize}px "JetBrains Mono"`),
      ]).catch(() => {});
      await document.fonts.ready;

      const probe = document.createElement('span');
      probe.style.cssText = 'position:absolute;visibility:hidden;white-space:pre';
      probe.textContent = '0'.repeat(100);
      $('editor').appendChild(probe);
      state.charW = probe.getBoundingClientRect().width / 100;
      probe.remove();

      const editor = $('editor');
      const win = $('window').getBoundingClientRect();
      return {
        charWidth: state.charW,
        visibleLines: (editor.clientHeight - state.padTop) / state.lineH,
        window: { x: win.x, y: win.y, width: win.width, height: win.height },
        fontFamily: getComputedStyle(editor).fontFamily,
        monoLoaded: document.fonts.check(`400 ${config.fontSize}px "JetBrains Mono"`),
      };
    },

    loadFile(payload) {
      state.files.set(payload.index, payload);
      return true;
    },

    render(view) {
      if (view.f !== state.file) activate(view.f);
      const rows = state.payload.rows;
      const curRow = view.cur[0];
      const curCol = view.cur[1];
      const curOn = view.cur[2] === 1;
      const lineH = state.lineH;
      let html = '';

      for (let i = 0; i < view.rows.length; i++) {
        const r = view.rows[i];
        const ri = r[0];
        const top = r[1];
        const h = r[2];
        const chars = r[3];
        const alpha = r[4];
        const ln = r[5];
        const row = ri >= 0 ? rows[ri] : null;
        const kind = row ? row[0] : 'c';
        const tokens = row ? row[1] : [];
        const length = row ? state.lengths[ri] : 0;
        const visible = chars < 0 ? length : Math.min(chars, length);
        const y = Math.round(state.padTop + top * lineH);
        const hpx = h >= 1 ? lineH : Math.max(0, Math.round(h * lineH));

        let cls = `row k-${kind}`;
        let style = `transform:translateY(${y}px)`;
        if (hpx !== lineH) style += `;height:${hpx}px;opacity:${h.toFixed(3)}`;
        if (kind === 'd') style += `;--a:${alpha}`;

        let body;
        if (ri === curRow) {
          cls += ' cur';
          const col = Math.min(curCol, visible);
          body = `${tokensHtml(tokens, 0, col)}<span class="caret${curOn ? '' : ' off'}"></span>${tokensHtml(tokens, col, visible)}`;
        } else if (visible === length) {
          body = state.fullHtml.get(ri);
          if (body === undefined) {
            body = tokensHtml(tokens, 0, length);
            state.fullHtml.set(ri, body);
          }
        } else {
          body = tokensHtml(tokens, 0, visible);
        }
        html += `<div class="${cls}" style="${style}"><span class="ln">${ln}</span><span class="code"><span class="in">${body}</span></span></div>`;
      }

      const container = $('rows');
      container.innerHTML = html;

      // Horizontal scroll keeps the caret in view. It is a pure function of
      // the caret position so every worker renders identical pixels.
      let sx = 0;
      const caret = container.querySelector('.caret');
      if (caret) {
        const x = caret.offsetLeft;
        const avail = caret.parentElement.parentElement.clientWidth;
        const margin = state.charW * 6;
        if (x > avail - margin) sx = Math.ceil(x - avail + margin);
      }
      container.style.setProperty('--sx', `${-sx}px`);
      $('pos').textContent = `Ln ${view.ln}, Col ${view.col}`;
      return true;
    },
  };
}

// ---------------------------------------------------------------------------
// Browser lifecycle
// ---------------------------------------------------------------------------

function chromeArgs() {
  const args = [
    '--hide-scrollbars',
    '--mute-audio',
    '--no-first-run',
    '--no-default-browser-check',
    '--disable-extensions',
    '--disable-background-networking',
    '--disable-background-timer-throttling',
    '--disable-backgrounding-occluded-windows',
    '--disable-renderer-backgrounding',
    '--disable-dev-shm-usage',
    '--force-color-profile=srgb',
    '--font-render-hinting=none',
    '--disable-lcd-text',
  ];
  const isRoot = typeof process.getuid === 'function' && process.getuid() === 0;
  const inContainer = fs.existsSync('/.dockerenv') || fs.existsSync('/run/.containerenv');
  if (isRoot || inContainer || process.env.GIT_COMMIT_ANIMATOR_NO_SANDBOX === '1') {
    // Chrome's sandbox cannot start as root or in most containers. The page
    // only ever displays our own escaped template with a CSP that blocks all
    // network access, so running unsandboxed here is safe.
    args.push('--no-sandbox', '--disable-setuid-sandbox');
  }
  return args;
}

function isMissingBrowserError(error) {
  return /Could not find (Chrome|chrome-headless-shell|Chromium)|Tried to find the browser|Browser was not found|no executable was found/i.test(String(error?.message ?? ''));
}

function mapLaunchError(error) {
  const message = String(error?.message ?? error);
  const lib = /error while loading shared libraries: ([^\s:]+)/.exec(message);
  if (lib) {
    return new AnimatorError(`Headless Chrome could not start: missing system library ${lib[1]}.`, {
      code: 'E_BROWSER_LIBS',
      hint: [
        'Install Chrome\'s runtime libraries. On Debian/Ubuntu:',
        '  sudo apt-get install -y libnss3 libatk1.0-0 libatk-bridge2.0-0 libcups2 libdrm2 libxkbcommon0 \\',
        '    libxcomposite1 libxdamage1 libxfixes3 libxrandr2 libgbm1 libpango-1.0-0 libcairo2 libasound2',
        'On Fedora/RHEL: sudo dnf install -y nss atk at-spi2-atk cups-libs libdrm libxkbcommon libXcomposite libXdamage libXrandr mesa-libgbm pango alsa-lib',
      ].join('\n'),
      details: message,
      cause: error,
    });
  }
  if (isMissingBrowserError(error)) {
    return new AnimatorError('The headless Chrome browser used for rendering is not installed.', {
      code: 'E_BROWSER_MISSING',
      hint: 'Download it once with:\n  npx puppeteer browsers install chrome-headless-shell\nOr point PUPPETEER_EXECUTABLE_PATH at an existing Chrome/Chromium binary.',
      details: message,
      cause: error,
    });
  }
  return new AnimatorError(`Headless Chrome failed to start: ${message.split('\n')[0]}`, {
    code: 'E_BROWSER_LAUNCH',
    hint: 'Run with --verbose for details. In Docker/CI, setting GIT_COMMIT_ANIMATOR_NO_SANDBOX=1 often helps.',
    details: message,
    cause: error,
  });
}

/** Downloads Puppeteer's pinned chrome-headless-shell build. */
async function installBundledBrowser() {
  const require = createRequire(import.meta.url);
  const pkgPath = require.resolve('puppeteer/package.json');
  const pkg = JSON.parse(await fsp.readFile(pkgPath, 'utf8'));
  const bin = typeof pkg.bin === 'string' ? pkg.bin : pkg.bin?.puppeteer;
  if (!bin) throw new Error('Puppeteer CLI entry point not found');
  const cli = path.join(path.dirname(pkgPath), bin);
  await new Promise((resolve, reject) => {
    const child = spawn(process.execPath, [cli, 'browsers', 'install', 'chrome-headless-shell'], {
      stdio: ['ignore', 'pipe', 'pipe'],
      windowsHide: true,
    });
    let output = '';
    child.stdout.on('data', (d) => { output += d; });
    child.stderr.on('data', (d) => { output += d; });
    child.on('error', reject);
    child.on('close', (code) => (code === 0 ? resolve() : reject(new Error(`browser download failed (exit ${code}):\n${output}`))));
  });
}

let installAttempted = null;

/**
 * Launches headless Chrome with automatic recovery:
 *   1. Puppeteer's bundled chrome-headless-shell (fastest for screenshots);
 *   2. Puppeteer's bundled Chrome in new-headless mode;
 *   3. a one-time automatic download of chrome-headless-shell.
 * PUPPETEER_EXECUTABLE_PATH, when set, is honoured by Puppeteer directly.
 *
 * @param {{ onStatus?: (msg: string) => void }} [options]
 */
export async function launchBrowser({ onStatus } = {}) {
  const base = {
    pipe: true,
    args: chromeArgs(),
    handleSIGINT: false,
    handleSIGTERM: false,
    handleSIGHUP: false,
    protocolTimeout: 180_000,
    timeout: 90_000,
    defaultViewport: null,
  };
  const custom = Boolean(process.env.PUPPETEER_EXECUTABLE_PATH);
  const attempts = custom ? [{ ...base, headless: true }] : [{ ...base, headless: 'shell' }, { ...base, headless: true }];

  let lastError;
  for (const options of attempts) {
    try {
      return await puppeteer.launch(options);
    } catch (error) {
      lastError = error;
      if (!isMissingBrowserError(error)) throw mapLaunchError(error);
    }
  }

  if (!custom) {
    try {
      onStatus?.('Downloading headless Chrome (one-time setup, ~100 MB)…');
      installAttempted ??= installBundledBrowser();
      await installAttempted;
      return await puppeteer.launch({ ...base, headless: 'shell' });
    } catch (error) {
      lastError = error;
    }
  }
  throw mapLaunchError(lastError);
}

class BrowserWorker {
  /**
   * @param {number} id
   * @param {FrameRenderer} owner
   */
  constructor(id, owner) {
    this.id = id;
    this.owner = owner;
    this.browser = null;
    this.page = null;
    this.loaded = new Set();
    this.rendered = 0;
    this.metrics = null;
  }

  async start() {
    this.browser = await launchBrowser({ onStatus: this.owner.onStatus });
    await this.openPage();
    return this.metrics;
  }

  async openPage() {
    const { width, height } = this.owner.layout;
    this.page = await this.browser.newPage();
    await this.page.setViewport({ width, height, deviceScaleFactor: 1 });
    await this.page.setContent(this.owner.html, { waitUntil: 'load' });
    this.metrics = await this.page.evaluate((cfg) => window.__gca.init(cfg), this.owner.pageConfig);
    this.loaded = new Set();
    this.rendered = 0;
  }

  async recyclePage() {
    const old = this.page;
    this.page = null;
    await old?.close().catch(() => {});
    await this.openPage();
  }

  async restart() {
    await this.close();
    await this.start();
  }

  /**
   * Renders one view and returns the PNG bytes.
   * @param {object} view
   * @param {{ clip?: object }} [options]
   */
  async capture(view, { clip } = {}) {
    if (this.rendered >= RECYCLE_PAGE_EVERY) await this.recyclePage();
    if (!this.loaded.has(view.f)) {
      await this.page.evaluate((p) => window.__gca.loadFile(p), this.owner.payloads[view.f]);
      this.loaded.add(view.f);
    }
    await this.page.evaluate((v) => window.__gca.render(v), view);
    const png = await this.page.screenshot({
      type: 'png',
      optimizeForSpeed: true,
      captureBeyondViewport: false,
      ...(clip ? { clip } : {}),
    });
    this.rendered++;
    return png;
  }

  async close() {
    const browser = this.browser;
    this.browser = null;
    this.page = null;
    if (!browser) return;
    try {
      await Promise.race([browser.close(), new Promise((r) => setTimeout(r, 3000).unref?.())]);
    } catch {
      // fall through to kill
    }
    this.killSync(browser);
  }

  killSync(browser = this.browser) {
    try {
      const proc = browser?.process();
      if (proc && proc.exitCode === null && !proc.killed) proc.kill('SIGKILL');
    } catch {
      // ignore
    }
  }
}

/**
 * Hard-links `src` to `dst`, falling back to a copy on file systems without
 * hard-link support (FAT, some network shares) or when the link limit is hit.
 */
async function linkOrCopy(src, dst) {
  try {
    await fsp.link(src, dst);
  } catch (error) {
    if (error.code === 'EEXIST') {
      await fsp.rm(dst, { force: true });
      return linkOrCopy(src, dst);
    }
    await fsp.copyFile(src, dst);
  }
}

async function mapLimit(items, limit, fn) {
  let next = 0;
  const run = async () => {
    while (next < items.length) {
      const item = items[next++];
      await fn(item);
    }
  };
  await Promise.all(Array.from({ length: Math.min(limit, items.length) }, run));
}

function diskError(error, dir) {
  if (error?.code === 'ENOSPC') {
    return new AnimatorError('Ran out of disk space while writing frames.', {
      code: 'E_DISK_FULL',
      hint: `Free some space in ${path.dirname(dir)} or point TMPDIR (TEMP on Windows) at a larger drive. Lowering --size or --max-duration also reduces the frame count.`,
      cause: error,
    });
  }
  return error;
}

export class FrameRenderer {
  /**
   * @param {object} options
   * @param {number} options.width Output width in pixels.
   * @param {number} options.height Output height in pixels.
   * @param {number} [options.fontSize] Code font size at 1920×1080.
   * @param {any} options.theme Resolved theme.
   * @param {object[]} options.payloads One page payload per file (timeline.toPagePayload).
   * @param {object} options.meta Repository metadata for the window chrome.
   * @param {string} options.framesDir Directory receiving frame PNGs.
   * @param {number} [options.workers]
   * @param {number} [options.batchSize]
   * @param {AbortSignal} [options.signal]
   * @param {(msg: string) => void} [options.onStatus]
   * @param {(msg: string) => void} [options.onDebug]
   */
  constructor(options) {
    this.options = options;
    this.layout = computeLayout({ width: options.width, height: options.height, fontSize: options.fontSize });
    this.html = buildTemplate({ layout: this.layout, theme: options.theme });
    this.payloads = options.payloads;
    this.framesDir = options.framesDir;
    this.batchSize = Math.max(1, options.batchSize ?? 120);
    this.requestedWorkers = Math.max(1, options.workers ?? defaultWorkerCount());
    this.signal = options.signal;
    this.onStatus = options.onStatus;
    this.onDebug = options.onDebug ?? (() => {});
    this.workers = [];
    this.metrics = null;
    this.clip = null;
    this.unregister = null;

    const { meta } = options;
    this.pageConfig = {
      repoName: meta.repoName,
      branch: meta.branch,
      baseHash: meta.baseHash,
      targetHash: meta.targetHash,
      subject: meta.subject,
      fontSize: this.layout.fontSize,
      lineHeight: this.layout.lineHeight,
      padTop: this.layout.editorPadTop,
      tabs: meta.tabs.map((t) => ({ ...t, color: LANGUAGE_COLORS[t.language] ?? LANGUAGE_COLORS['Plain Text'] })),
    };
  }

  /**
   * Launches the browser pool and measures the layout.
   * @returns {Promise<{ visibleLines: number, workers: number, clip: object, fontLoaded: boolean }>}
   */
  async start() {
    this.unregister = registerCleanup('browsers', () => this.close(), () => {
      for (const w of this.workers) w.killSync();
    });

    // Launch one worker first so a missing browser is detected (and auto-
    // installed) once, then bring up the rest in parallel.
    const first = new BrowserWorker(0, this);
    this.workers.push(first);
    this.metrics = await first.start();
    throwIfAborted(this.signal);

    // Extra workers are optional: on a memory-starved machine, carry on with
    // however many started instead of failing the whole run.
    const extra = Array.from({ length: this.requestedWorkers - 1 }, (_, i) => new BrowserWorker(i + 1, this));
    this.workers.push(...extra);
    const results = await Promise.allSettled(extra.map((worker) => worker.start()));
    for (const [i, result] of results.entries()) {
      if (result.status === 'rejected') {
        this.onDebug(`extra renderer ${extra[i].id} failed to start: ${result.reason?.message ?? result.reason}`);
        await extra[i].close();
      }
    }
    this.workers = this.workers.filter((w) => w.page);
    throwIfAborted(this.signal);

    const w = this.layout.window;
    this.clip = { x: w.x, y: w.y, width: w.width, height: w.height };
    this.onDebug(`layout: window ${w.width}x${w.height}@${w.x},${w.y}, font ${this.layout.fontSize}px/${this.layout.lineHeight}px, ${this.metrics.visibleLines.toFixed(2)} lines, char ${this.metrics.charWidth.toFixed(2)}px, JetBrains Mono loaded: ${this.metrics.monoLoaded}`);
    return {
      visibleLines: this.metrics.visibleLines,
      workers: this.workers.length,
      clip: this.clip,
      fontLoaded: this.metrics.monoLoaded,
    };
  }

  /**
   * Captures the full canvas once. Everything outside the editor window
   * (gradient + drop shadow) is static and reused for every frame.
   * @param {object} view Any view (normally the first frame).
   */
  async captureBackground(view) {
    const file = path.join(this.framesDir, BACKGROUND_FILE);
    const png = await this.workers[0].capture(view);
    await fsp.writeFile(file, png).catch((error) => {
      throw diskError(error, this.framesDir);
    });
    return file;
  }

  /**
   * Runs the batched capture loop.
   *
   * @param {Iterable<object>} frames Lazily generated views.
   * @param {number} totalFrames Expected number of frames (for progress).
   * @param {(progress: { done: number, total: number, unique: number }) => void} [onProgress]
   */
  async render(frames, totalFrames, onProgress = () => {}) {
    let batch = [];
    let index = 0;
    let unique = 0;
    let done = 0;
    let prevKey = null;
    let prevIndex = -1;

    const report = () => onProgress({ done, total: totalFrames, unique });
    const tick = () => {
      done++;
      report();
    };

    for (const view of frames) {
      throwIfAborted(this.signal);
      const key = JSON.stringify(view);
      if (key === prevKey) {
        batch.push({ index, source: prevIndex });
      } else {
        batch.push({ index, view });
        prevKey = key;
        prevIndex = index;
        unique++;
      }
      index++;
      if (batch.length >= this.batchSize) {
        await this.flush(batch, tick);
        batch = [];
      }
    }
    if (batch.length) await this.flush(batch, tick);
    report();
    return { frames: index, unique };
  }

  /**
   * Renders a batch: unique views in parallel contiguous slices, then hard
   * links for duplicates.
   */
  async flush(batch, tick) {
    const jobs = batch.filter((j) => j.view);
    const workers = this.workers;
    const sliceSize = Math.ceil(jobs.length / workers.length);
    await Promise.all(workers.map((worker, w) => {
      const slice = jobs.slice(w * sliceSize, (w + 1) * sliceSize);
      return slice.length ? this.runSlice(worker, slice, tick) : null;
    }));

    const dups = batch.filter((j) => !j.view);
    await mapLimit(dups, LINK_CONCURRENCY, async (job) => {
      throwIfAborted(this.signal);
      await linkOrCopy(path.join(this.framesDir, frameFileName(job.source)), path.join(this.framesDir, frameFileName(job.index)))
        .catch((error) => {
          throw diskError(error, this.framesDir);
        });
      tick();
    });
  }

  async runSlice(worker, slice, tick) {
    let pending = null;
    let writeError = null;
    let restarts = 0;
    for (let i = 0; i < slice.length;) {
      throwIfAborted(this.signal);
      const job = slice[i];
      let png;
      try {
        png = await worker.capture(job.view, { clip: this.clip });
      } catch (error) {
        if (this.signal?.aborted) throw new AbortError();
        if (error instanceof AnimatorError) throw error;
        if (++restarts > MAX_WORKER_RESTARTS) {
          throw new AnimatorError(`Renderer ${worker.id} keeps crashing: ${error.message}`, {
            code: 'E_RENDER_CRASH',
            hint: 'Try fewer parallel renderers (--workers 1) or a smaller --size.',
            cause: error,
            details: error.stack,
          });
        }
        this.onDebug(`renderer ${worker.id} failed (${error.message}); restarting (${restarts}/${MAX_WORKER_RESTARTS})`);
        await worker.restart();
        continue;
      }
      // One write in flight per worker: overlap disk I/O with the next capture.
      if (pending) await pending;
      if (writeError) throw diskError(writeError, this.framesDir);
      pending = fsp.writeFile(path.join(this.framesDir, frameFileName(job.index)), png)
        .then(tick)
        .catch((error) => {
          writeError = error;
        });
      i++;
    }
    if (pending) await pending;
    if (writeError) throw diskError(writeError, this.framesDir);
  }

  async close() {
    const workers = this.workers;
    this.workers = [];
    await Promise.all(workers.map((w) => w.close()));
    this.unregister?.();
    this.unregister = null;
  }
}
