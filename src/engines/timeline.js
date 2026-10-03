/**
 * Timeline engine: turns a parsed diff into a deterministic, frame-accurate
 * sequence of editor "views".
 *
 * The pipeline has three stages:
 *
 *   1. createFileModel()  — merges old/new file contents and diff hunks into a
 *      single list of rows (context, deleted, added) with syntax tokens.
 *   2. createTimeline()   — schedules humanized keystrokes, pauses, deletion
 *      fades and scrolling into a list of timestamped actions, then rescales
 *      the schedule to fit the requested maximum duration.
 *   3. timeline.frames()  — a generator that samples the action list at the
 *      output frame rate, simulating smooth scrolling and cursor blink, and
 *      yields a compact, serializable view for every frame.
 *
 * Everything here is pure and seeded, so the same commit range always
 * produces the same video. Views are absolute (they never depend on the
 * previous frame having been rendered), which lets the renderer split work
 * across several browser processes and retry crashed batches safely.
 */

import path from 'node:path';
import { detectLanguage, tokenize } from './highlighter.js';

/** Default pacing, in milliseconds. */
export const DEFAULT_TIMING = Object.freeze({
  minKeyDelay: 15,
  maxKeyDelay: 45,
  newlineDelay: [70, 150],
  introHold: 650,
  openHold: 600,
  focusPause: 420,
  nearbyFocusPause: 140,
  markDuration: 220,
  markHold: 380,
  collapseDuration: 260,
  hunkPause: 240,
  fileOutroHold: 650,
  finalHold: 1800,
  idleBeforeBlink: 500,
  blinkPeriod: 1060,
  scrollTau: 85,
});

/** Share of the duration budget that pauses may keep when compressing. */
const FIXED_BUDGET_SHARE = 0.4;

const graphemes = new Intl.Segmenter(undefined, { granularity: 'grapheme' });

/**
 * Splits text into lines the same way the highlighter does, dropping the
 * phantom empty line after a trailing newline.
 * @param {string} text
 */
export function splitLines(text) {
  if (!text) return [];
  const lines = text.split('\n');
  if (lines[lines.length - 1] === '') lines.pop();
  return lines;
}

/**
 * Mulberry32 — tiny, fast, well-distributed 32-bit seeded PRNG.
 * @param {number} seed
 * @returns {() => number} Uniform floats in [0, 1).
 */
export function createRandom(seed) {
  let a = (seed >>> 0) || 0x9e3779b9;
  return () => {
    a = (a + 0x6d2b79f5) >>> 0;
    let t = a;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

/**
 * FNV-1a hash of a string, used to derive a default seed from commit hashes.
 * @param {string} input
 */
export function hashSeed(input) {
  let h = 0x811c9dc5;
  for (let i = 0; i < input.length; i++) {
    h ^= input.charCodeAt(i);
    h = Math.imul(h, 0x01000193);
  }
  return h >>> 0;
}

/**
 * Builds the row model for one changed file.
 *
 * @param {object} file Diff entry produced by git.collectDiff().
 * @param {number} index Position of the file in the animation.
 */
export function createFileModel(file, index) {
  const language = detectLanguage(file.path);
  const oldLines = splitLines(file.oldText);
  const newLines = splitLines(file.newText);
  const oldTokens = tokenize(file.oldText, language.id);
  const newTokens = tokenize(file.newText, language.id);

  const rows = [];
  const hunks = [];
  let oldIdx = 0;
  let newIdx = 0;

  const pushContext = () => {
    rows.push({ kind: 'ctx', text: newLines[newIdx] ?? '', tokens: newTokens[newIdx] ?? [], oldNo: oldIdx + 1, newNo: newIdx + 1 });
    oldIdx++;
    newIdx++;
  };

  const ordered = [...file.hunks].sort((a, b) => a.oldStart - b.oldStart || a.newStart - b.newStart);
  for (const hunk of ordered) {
    const oldBegin = hunk.oldLines === 0 ? hunk.oldStart : hunk.oldStart - 1;
    while (oldIdx < oldBegin && oldIdx < oldLines.length) pushContext();
    const newBegin = hunk.newLines === 0 ? hunk.newStart : hunk.newStart - 1;
    if (oldIdx !== oldBegin || newIdx !== newBegin) {
      throw new Error(`Inconsistent diff hunk in ${file.path}: expected old/new line ${oldBegin + 1}/${newBegin + 1}, reached ${oldIdx + 1}/${newIdx + 1}`);
    }

    const record = { index: hunks.length, delRows: [], addRows: [] };
    for (let k = 0; k < hunk.oldLines; k++) {
      record.delRows.push(rows.length);
      rows.push({ kind: 'del', text: oldLines[oldIdx] ?? '', tokens: oldTokens[oldIdx] ?? [], oldNo: oldIdx + 1, newNo: 0 });
      oldIdx++;
    }
    for (let k = 0; k < hunk.newLines; k++) {
      record.addRows.push(rows.length);
      rows.push({ kind: 'add', text: newLines[newIdx] ?? '', tokens: newTokens[newIdx] ?? [], oldNo: 0, newNo: newIdx + 1 });
      newIdx++;
    }
    if (record.delRows.length || record.addRows.length) hunks.push(record);
  }
  while (oldIdx < oldLines.length || newIdx < newLines.length) {
    if (oldIdx >= oldLines.length || newIdx >= newLines.length) break;
    pushContext();
  }

  // Global ordering of added rows (typing happens strictly top to bottom).
  const addOrder = [];
  for (const h of hunks) for (const r of h.addRows) {
    rows[r].addIndex = addOrder.length;
    addOrder.push(r);
  }
  for (const h of hunks) for (const r of h.delRows) rows[r].hunk = h.index;

  return {
    index,
    path: file.path,
    oldPath: file.oldPath,
    status: file.status,
    name: path.posix.basename(file.path),
    directory: path.posix.dirname(file.path) === '.' ? '' : path.posix.dirname(file.path),
    language,
    rows,
    hunks,
    addOrder,
    additions: hunks.reduce((n, h) => n + h.addRows.length, 0),
    deletions: hunks.reduce((n, h) => n + h.delRows.length, 0),
  };
}

/**
 * Compact payload sent once per file to each browser page.
 * Rows are `[kindLetter, tokens]`.
 * @param {ReturnType<typeof createFileModel>} model
 */
export function toPagePayload(model) {
  return {
    index: model.index,
    name: model.name,
    directory: model.directory,
    language: model.language.name,
    rows: model.rows.map((r) => [r.kind[0], r.tokens]),
  };
}

/**
 * Splits an added line into keystrokes. Leading indentation is a single
 * keystroke (editors auto-indent); everything else is typed one grapheme at a
 * time so emoji and combining characters never get split.
 * @returns {number[]} UTF-16 end offsets after each keystroke.
 */
export function keystrokeOffsets(text) {
  const offsets = [];
  const indent = /^[ \t]+/.exec(text)?.[0].length ?? 0;
  if (indent) offsets.push(indent);
  if (indent < text.length) {
    for (const { index, segment } of graphemes.segment(text.slice(indent))) {
      offsets.push(indent + index + segment.length);
    }
  }
  return offsets;
}

/**
 * Humanized per-character delay. Triangular distribution skewed toward the
 * fast end, nudged slower after word boundaries and faster on repeats, always
 * clamped to [min, max].
 */
function keyDelay(rng, timing, prevChar, char) {
  const { minKeyDelay: min, maxKeyDelay: max } = timing;
  const tri = (rng() + rng()) / 2;
  let t = tri * 0.85;
  if (char === ' ' || /[(){}[\],.;:]/.test(prevChar)) t += 0.25 * rng();
  if (char === prevChar) t *= 0.6;
  return Math.min(max, Math.max(min, min + (max - min) * t));
}

function range(rng, [lo, hi]) {
  return lo + (hi - lo) * rng();
}

/** First row of a hunk (deleted rows always precede added rows). */
function hunkFirstRow(hunk) {
  return hunk.delRows.length ? hunk.delRows[0] : hunk.addRows[0];
}

function easeInOut(x) {
  return x < 0.5 ? 2 * x * x : 1 - (-2 * x + 2) ** 2 / 2;
}

function clamp(x, lo, hi) {
  return x < lo ? lo : x > hi ? hi : x;
}

const round3 = (x) => Math.round(x * 1000) / 1000;

/**
 * Builds a timeline for a set of file models.
 *
 * @param {ReturnType<typeof createFileModel>[]} models
 * @param {object} options
 * @param {number} options.fps Output frame rate.
 * @param {number} options.visibleLines Number of code lines visible in the editor viewport.
 * @param {number} [options.speed=1] Typing speed multiplier.
 * @param {number} [options.maxDuration=30] Upper bound for the video length, in seconds.
 * @param {number} [options.seed=1] PRNG seed.
 * @param {Partial<typeof DEFAULT_TIMING>} [options.timing]
 */
export function createTimeline(models, options) {
  const fps = options.fps;
  const visible = Math.max(4, options.visibleLines);
  const timing = { ...DEFAULT_TIMING, ...(options.timing ?? {}) };
  const speed = options.speed ?? 1;
  const maxDurationMs = (options.maxDuration ?? 30) * 1000;
  const rng = createRandom(options.seed ?? 1);

  // ---- 1. Script: a flat list of { d, cat, act } steps -------------------
  // Semantics: wait `d` ms, then apply `act` (may be null). `cat` selects the
  // scaling bucket used when compressing to the duration budget.
  const steps = [];
  const fixed = (d, act = null) => steps.push({ d, cat: 'fixed', act });
  const typed = (d, act) => steps.push({ d: d / speed, cat: 'type', act });

  models.forEach((model, f) => {
    fixed(0, { type: 'open', f });
    fixed(f === 0 ? timing.introHold : timing.openHold);
    let prevHunkEnd = -Infinity;

    model.hunks.forEach((hunk, h) => {
      const first = hunkFirstRow(hunk);
      const last = hunk.addRows.length ? hunk.addRows[hunk.addRows.length - 1] : hunk.delRows[hunk.delRows.length - 1];
      const nearby = h > 0 && first - prevHunkEnd < visible * 0.45;
      prevHunkEnd = last;
      fixed(0, { type: 'focus', f, h, center: !nearby });
      fixed(h === 0 ? timing.nearbyFocusPause : nearby ? timing.nearbyFocusPause : timing.focusPause);

      if (hunk.delRows.length) {
        fixed(0, { type: 'mark', f, h, dur: timing.markDuration });
        fixed(timing.markDuration + timing.markHold);
        fixed(0, { type: 'collapse', f, h, dur: timing.collapseDuration });
        fixed(timing.collapseDuration, { type: 'delsDone', f, h });
      }

      hunk.addRows.forEach((rowIdx, k) => {
        const text = model.rows[rowIdx].text;
        const newline = k === 0 && !hunk.delRows.length ? range(rng, timing.newlineDelay) * 0.6 : range(rng, timing.newlineDelay);
        typed(newline, { type: 'newline', f, row: rowIdx });
        let prevChar = '\n';
        for (const end of keystrokeOffsets(text)) {
          const ch = text.slice(end - 1, end);
          typed(keyDelay(rng, timing, prevChar, ch), { type: 'key', f, row: rowIdx, end });
          prevChar = ch;
        }
      });
      fixed(timing.hunkPause, { type: 'hunkDone', f, h });
    });
    fixed(f === models.length - 1 ? timing.finalHold : timing.fileOutroHold);
  });

  // ---- 2. Fit the script into the duration budget ------------------------
  let typeTotal = 0;
  let fixedTotal = 0;
  for (const s of steps) {
    if (s.cat === 'type') typeTotal += s.d;
    else fixedTotal += s.d;
  }
  let kType = 1;
  let kFixed = 1;
  if (typeTotal + fixedTotal > maxDurationMs) {
    if (typeTotal === 0) {
      kFixed = maxDurationMs / fixedTotal;
    } else {
      const fixedBudget = Math.min(fixedTotal, maxDurationMs * FIXED_BUDGET_SHARE);
      kFixed = fixedTotal > 0 ? fixedBudget / fixedTotal : 1;
      kType = (maxDurationMs - fixedBudget) / typeTotal;
    }
  }

  const actions = [];
  let t = 0;
  for (const s of steps) {
    t += s.d * (s.cat === 'type' ? kType : kFixed);
    if (s.act) {
      if (s.act.dur) s.act.dur *= kFixed;
      s.act.t = t;
      actions.push(s.act);
    }
  }
  const durationMs = t;
  const totalFrames = Math.max(1, Math.ceil((durationMs / 1000) * fps) + 1);

  const stats = {
    files: models.length,
    hunks: models.reduce((n, m) => n + m.hunks.length, 0),
    keystrokes: actions.reduce((n, a) => n + (a.type === 'key' ? 1 : 0), 0),
    compressed: kType < 1 || kFixed < 1,
    typingScale: kType,
  };

  return {
    fps,
    durationMs,
    totalFrames,
    stats,
    frames: () => sampleFrames(models, actions, { fps, totalFrames, visible, timing }),
  };
}

/**
 * Samples the action list at the output frame rate.
 * @returns {Generator<object>}
 */
function* sampleFrames(models, actions, { fps, totalFrames, visible, timing }) {
  const dt = 1000 / fps;
  const smoothing = 1 - Math.exp(-dt / timing.scrollTau);
  const topMargin = Math.min(3, Math.floor(visible * 0.15));
  const bottomMargin = Math.max(2, Math.floor(visible * 0.25));

  let ai = 0;
  let file = -1;
  let model = null;
  let heights = null;
  let st = null;
  let scroll = 0;
  let scrollTarget = 0;
  let lastKeyTime = -Infinity;
  let cursor = { row: 0, col: 0 };

  let totalHeight = 0;

  /** Height (0..1) of every row for the current state; also updates totalHeight. */
  const computeHeights = (time) => {
    const rows = model.rows;
    totalHeight = 0;
    for (let r = 0; r < rows.length; r++) {
      const row = rows[r];
      if (row.kind === 'ctx') heights[r] = 1;
      else if (row.kind === 'add') heights[r] = row.addIndex < st.addPresent ? 1 : 0;
      else if (row.hunk < st.hunk || (row.hunk === st.hunk && st.delsDone)) heights[r] = 0;
      else if (row.hunk === st.hunk && st.collapse) {
        const p = clamp((time - st.collapse.t) / st.collapse.dur, 0, 1);
        heights[r] = 1 - easeInOut(p);
      } else heights[r] = 1;
      totalHeight += heights[r];
    }
  };

  /** Y position (in line units) of a row, i.e. the sum of heights above it. */
  const rowY = (target) => {
    let y = 0;
    for (let r = 0; r < target; r++) y += heights[r];
    return y;
  };

  const maxScroll = () => Math.max(0, totalHeight + bottomMargin - visible);

  const focusTarget = (f, h, time) => {
    computeHeights(time);
    return clamp(rowY(hunkFirstRow(models[f].hunks[h])) - visible * 0.3, 0, maxScroll());
  };

  /** Cursor position when focusing a hunk: start of the deletions, or end of the line above the insertion. */
  const hunkCursor = (hunk) => {
    if (hunk.delRows.length) return { row: hunk.delRows[0], col: 0 };
    const firstAdd = hunk.addRows[0];
    for (let r = firstAdd - 1; r >= 0; r--) {
      const row = model.rows[r];
      if (row.kind === 'ctx' || (row.kind === 'add' && row.addIndex < st.addPresent)) return { row: r, col: Infinity };
    }
    for (let r = firstAdd + 1; r < model.rows.length; r++) {
      if (model.rows[r].kind === 'ctx') return { row: r, col: 0 };
    }
    return { row: firstAdd, col: 0 };
  };

  const apply = (a) => {
    switch (a.type) {
      case 'open': {
        file = a.f;
        model = models[file];
        heights = new Float64Array(model.rows.length);
        st = { hunk: -1, mark: null, collapse: null, delsDone: false, addPresent: 0, lastChars: Infinity };
        lastKeyTime = a.t;
        if (model.hunks.length) {
          st.hunk = 0;
          scrollTarget = focusTarget(file, 0, a.t);
          scroll = scrollTarget;
          cursor = hunkCursor(model.hunks[0]);
        } else {
          scroll = scrollTarget = 0;
          cursor = { row: 0, col: 0 };
        }
        break;
      }
      case 'focus': {
        st.hunk = a.h;
        st.mark = null;
        st.collapse = null;
        st.delsDone = false;
        cursor = hunkCursor(model.hunks[a.h]);
        lastKeyTime = a.t;
        if (a.center) scrollTarget = focusTarget(file, a.h, a.t);
        break;
      }
      case 'mark':
        st.mark = { t: a.t, dur: Math.max(a.dur, 1e-3) };
        break;
      case 'collapse':
        st.collapse = { t: a.t, dur: Math.max(a.dur, 1e-3) };
        break;
      case 'delsDone': {
        st.delsDone = true;
        const hunk = model.hunks[a.h];
        const firstDel = hunk.delRows[0];
        let above = -1;
        for (let r = firstDel - 1; r >= 0; r--) {
          const row = model.rows[r];
          if (row.kind === 'ctx' || (row.kind === 'add' && row.addIndex < st.addPresent)) {
            above = r;
            break;
          }
        }
        if (above >= 0) cursor = { row: above, col: Infinity };
        else {
          const below = hunk.delRows[hunk.delRows.length - 1] + 1;
          cursor = { row: Math.min(below, model.rows.length - 1), col: 0 };
        }
        lastKeyTime = a.t;
        break;
      }
      case 'newline':
        st.addPresent = model.rows[a.row].addIndex + 1;
        st.lastChars = 0;
        cursor = { row: a.row, col: 0 };
        lastKeyTime = a.t;
        break;
      case 'key':
        st.lastChars = a.end;
        cursor = { row: a.row, col: a.end };
        lastKeyTime = a.t;
        break;
      case 'hunkDone':
        st.lastChars = Infinity;
        break;
      default:
        break;
    }
  };

  for (let i = 0; i < totalFrames; i++) {
    const time = i * dt;
    while (ai < actions.length && actions[ai].t <= time + 1e-6) apply(actions[ai++]);
    if (!model) break;

    computeHeights(time);

    // Keep the cursor comfortably inside the viewport.
    let cursorRow = clamp(cursor.row, 0, Math.max(0, model.rows.length - 1));
    if (heights[cursorRow] === 0) {
      // The cursor row collapsed away; fall back to the nearest present row.
      let r = cursorRow;
      while (r > 0 && heights[r] === 0) r--;
      cursorRow = r;
    }
    const cy = rowY(cursorRow);
    const ms = maxScroll();
    if (cy < scrollTarget + topMargin) scrollTarget = cy - topMargin;
    if (cy + 1 > scrollTarget + visible - bottomMargin) scrollTarget = cy + 1 - visible + bottomMargin;
    scrollTarget = clamp(scrollTarget, 0, ms);
    scroll += (scrollTarget - scroll) * smoothing;
    if (Math.abs(scrollTarget - scroll) < 0.004) scroll = scrollTarget;

    // Deletion highlight intensity for the active hunk.
    let alpha = 0;
    if (st.mark) alpha = clamp((time - st.mark.t) / st.mark.dur, 0, 1);

    // Collect visible rows with dynamic line numbers.
    const viewRows = [];
    let y = 0;
    let lineNo = 0;
    let cursorLine = 1;
    const rows = model.rows;
    for (let r = 0; r < rows.length; r++) {
      const h = heights[r];
      if (h === 0) continue;
      lineNo++;
      if (r === cursorRow) cursorLine = lineNo;
      const top = y - scroll;
      if (top + h > -0.5 && top < visible + 0.5) {
        const row = rows[r];
        let chars = -1;
        if (row.kind === 'add' && row.addIndex === st.addPresent - 1 && st.lastChars < row.text.length) chars = st.lastChars;
        const rowAlpha = row.kind === 'del' && row.hunk === st.hunk ? Math.round(alpha * 100) / 100 : 0;
        viewRows.push([r, round3(top), round3(h), chars, rowAlpha, lineNo]);
      }
      y += h;
      if (top > visible + 1 && r > cursorRow) {
        // Below the viewport: only the cursor line number was still needed.
        break;
      }
    }

    if (viewRows.length === 0 && totalHeight === 0) {
      // Empty document (e.g. a brand-new file before the first keystroke):
      // show a blank first line so the cursor has somewhere to blink.
      viewRows.push([-1, round3(-scroll), 1, 0, 0, 1]);
    }

    const idle = time - lastKeyTime;
    const cursorOn = idle < timing.idleBeforeBlink
      || Math.floor((idle - timing.idleBeforeBlink) / (timing.blinkPeriod / 2)) % 2 === 1;
    const row = rows[cursorRow];
    const present = row && heights[cursorRow] > 0;
    const rowLength = !present ? 0 : row.kind === 'add' && row.addIndex === st.addPresent - 1
      ? Math.min(st.lastChars, row.text.length)
      : row.text.length;
    const col = Math.min(cursor.row === cursorRow ? cursor.col : 0, rowLength);

    yield {
      f: file,
      rows: viewRows,
      cur: [present ? cursorRow : -1, col, cursorOn ? 1 : 0],
      ln: cursorLine,
      col: col + 1,
    };
  }
}
