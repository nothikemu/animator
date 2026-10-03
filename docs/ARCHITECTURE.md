# Architecture

This document explains how Git-Commit Animator turns a diff into a video and why it's built the way it is. The README covers usage.

```
            ┌──────────────────────────── src/cli.js ─────────────────────────────┐
            │ parse argv → normalize options → preflight (ffmpeg) → 3 phases → UI │
            └──────┬────────────────────────┬─────────────────────────┬───────────┘
                   │ [1/3] Analyze          │ [2/3] Render            │ [3/3] Encode
                   ▼                        ▼                         ▼
        src/utils/git.js         src/engines/timeline.js    src/engines/encoder.js
        (spawn git, parse)  ──▶  (rows, keystrokes,    ──▶  (overlay + libx264 / GIF)
                                  scroll, frame views)
                                          │                         ▲
                                          ▼                         │ frame_%06d.png
                                 src/engines/renderer.js ───────────┘ + background.png
                                 (Chrome pool, batches,
                                  dedupe, window capture)
```

## Phase 1: Analyze (`src/utils/git.js`)

- **No shell, ever.** Every git call is `spawn('git', [...args])`, so paths and revisions are passed through unchanged. Revisions that start with `-` are rejected as defense in depth against option injection (for example `--output=/etc/passwd`).
- **Predictable output.** Every call sets `-c core.quotePath=false -c color.ui=false`, `--no-ext-diff --no-textconv`, `GIT_OPTIONAL_LOCKS=0` (never take the index lock) and `GIT_TERMINAL_PROMPT=0`. That way the user's git config (external diff tools, colors, pagers) can't change what we parse.
- **Machine-readable listings.** The changed files come from `git diff --raw -z --no-abbrev -M` together with `--numstat -z`. NUL separators handle any file name, including spaces, quotes, newlines and Unicode.
- **One process for all blobs.** `git cat-file --batch-check` reads the sizes, so files over 1 MB can be skipped before loading anything. `git cat-file --batch` then streams every needed blob through a single process.
- **Human-looking hunks.** Modified files are diffed blob-to-blob with `-U0 --diff-algorithm=histogram`, which pairs lines the way a person would. Added and deleted files don't need git at all: their single hunk is built directly.
- **Binary detection.** A NUL byte in the first 8 KB (git's heuristic) marks a file as binary. A file also counts as binary if it isn't valid UTF-8 and is dominated by control or high-bit bytes. Git would happily diff such a file as text, but typing it out produces garbage.
- **Smart defaults and edge cases:**
  - target defaults to `HEAD` and base to the target's first parent;
  - a root commit is diffed against the **empty tree**, using the repository's own object format (works for SHA-256 repositories);
  - a shallow-clone boundary looks parentless but is *not* treated as a root commit. Doing so would quietly animate the whole repository, so the user gets an `E_SHALLOW_CLONE` hint instead;
  - `A...B` resolves the merge base, like `git diff A...B`;
  - lockfiles, minified bundles and source maps are skipped unless `--all-files` is given;
  - `--max-files` keeps the biggest changes but shows them in path order.

## Phase 2a: Timeline (`src/engines/timeline.js`)

The timeline is **pure and seeded**: given the same diff and seed it produces byte-identical views. The default seed comes from the two commit hashes.

1. **Row model.** For each file, the old and new contents are merged with the hunks into one row list (`ctx`, `del`, `add`). It is checked against the hunk headers, so a malformed diff fails loudly instead of rendering the wrong text. Tokens come from the highlighter, run on the *final* text of each side. That way a half-typed keyword already has its final color and nothing flickers mid-keystroke.
2. **Script.** A flat list of `{wait, action}` steps: open file → focus hunk → fade deletions red → collapse them → for each added line, Enter and then keystrokes → pause. Keystrokes follow grapheme clusters (`Intl.Segmenter`), so emoji and combining marks are never split. Leading indentation is one keystroke, like an editor's auto-indent. Per-character delays come from a triangular distribution clamped to 15–45 ms, a bit slower after word boundaries and faster on repeated characters.
3. **Fitting to the budget.** The steps are split into *typing* and *fixed* (pauses) buckets. If the total is longer than `--max-duration`, pauses keep at most 40% of the budget and typing is scaled to fill the rest.
4. **Sampling.** A generator walks the actions at the output frame rate. At each frame it computes:
   - the row heights (collapsing deletions ease from 1 to 0);
   - the scroll position: frame-rate-independent exponential smoothing toward a target that keeps the cursor in a comfortable band, snapped once within 0.004 lines so frames settle and deduplicate;
   - live line numbers (they renumber as lines are inserted or removed);
   - the cursor position and blink phase (solid while typing, blinking after 500 ms idle).

Each frame yields a small **absolute view**: `{ f, rows: [[row, top, height, chars, alpha, lineNo]…], cur, ln, col }`. A view never depends on a previous frame. That property is what makes the renderer below parallel, retryable and deduplicable.

## Phase 2b: Rendering (`src/engines/renderer.js`)

### The page is a dumb view

`buildTemplate()` produces one static HTML document: CSS for the editor chrome, theme tokens, the bundled JetBrains Mono as base64 `@font-face` data, and a tiny runtime (`pageRuntime`, serialized with `Function#toString`). The runtime's `render(view)` builds about 30 row `div`s from cached token HTML. Horizontal scroll is a pure function of where the caret is, so every page produces identical pixels for the same view.

The layout is computed in Node with **integer pixels** at any output size. Everything scales from a 1920×1080 design (12px corners, `0 25px 50px -12px` shadow, 22px font, 35px line height at 1080p), and the editor window always lands on whole device pixels. That keeps text crisp and makes the window's clip rectangle exact.

A strict CSP (`default-src 'none'`) blocks all network access. Code is HTML-escaped before it reaches `innerHTML`.

### Worker pool: processes, not tabs

Benchmarks on 4 cores (1080p PNG capture):

| Strategy | ms / frame |
| --- | --- |
| 1 browser, 1 page | 87 |
| 1 browser, 4 pages | 65 |
| 2 browsers | 43 |
| 3 browsers | 31 |

Chrome serializes compositing within one browser process, so extra tabs barely help, while extra *processes* scale almost linearly. The default worker count is `min(4, cores − 1)`, further limited by free memory (about 400 MB per worker). The first worker launches alone, so a missing browser is detected (and downloaded) once. The others then start in parallel, and if one fails the run continues with fewer workers.

`chrome-headless-shell` is preferred because it's faster for screenshots. Puppeteer's bundled Chrome is the fallback, then a one-time automatic download. Puppeteer's own signal handlers are turned off so our cleanup controls shutdown order.

### Strict batched queue

```
generator ──▶ [ batch of ≤120 views ] ──▶ split into contiguous slices ──▶ worker 0 … worker N
                    │                                                        │ capture → write (1 in flight)
                    └── duplicates ──▶ hard links (after uniques are flushed) ◀┘
```

- The frame generator is consumed **lazily**. At most `batchSize` views exist at once, each worker holds at most one PNG plus one pending write, and a batch must be completely on disk before the next starts. Memory use stays flat no matter how long the video is.
- Workers get **contiguous** slices, so file switches (`loadFile`) are rare.
- **Deduplication.** Consecutive identical views (pauses, blink plateaus, frames between keystrokes) become `fs.link` hard links to the previous PNG. They cost no CPU and no disk space. Hard links fall back to copies on file systems that don't support them. In our test runs, 27–40% of frames were deduplicated, and far more for small diffs dominated by pauses.
- **Static/dynamic layer separation.** Only the editor window is captured each frame (`clip`). The gradient and drop shadow are captured once as `background.png`. Window-only PNGs are about 5× smaller (121 KB vs 597 KB) and 30% faster to produce, because the gradient compresses poorly.
- **Crash tolerance.** If a capture throws (renderer crash, killed process), the worker's browser is relaunched and the rest of its slice is retried, up to twice. Because views are absolute, this is always correct. Pages are also recycled every 1,500 captures to limit long-run memory growth.

## Phase 3: Encoding (`src/engines/encoder.js`)

### Finding ffmpeg

`FFMPEG_PATH` is authoritative if set. Otherwise the tool scans `PATH` (with `PATHEXT` on Windows), then common install locations such as Homebrew, WinGet links, Scoop, Chocolatey, Snap and Linuxbrew, which helps when GUI-launched shells have an incomplete PATH. Each candidate is run with `-version`, `-encoders` and `-filters` to confirm `libx264`, `overlay` and the palette filters are present. Missing pieces produce OS-specific install instructions, including the Fedora `ffmpeg-free` swap.

### Filter graph (MP4)

```
[background.png] → loop=-1:size=1 → settb=1/fps → setpts=N ─┐
                                                            ├─ overlay(x,y, format=rgb, shortest=1)
[frame_%06d.png @ fps] ─────────────────────────────────────┘
   → scale(out_color_matrix=bt709, out_range=tv, accurate_rnd, full_chroma_int) → yuv420p
   → libx264 -preset medium -tune animation -crf 18 -profile:v high -r fps -movflags +faststart
```

- **Background decoded once.** The `loop` filter repeats the decoded background in memory. That's about 20% faster than re-reading it with `-loop 1`.
- **Exact timestamps.** `setpts=N/FRAME_RATE/TB` would round through floating point and occasionally emit a duplicate PTS. ffmpeg then drops one frame and duplicates another, which shows up as a stutter in the typing. `settb=1/fps,setpts=N` uses only integers. This was checked with `framemd5`: output matches a `-loop 1` reference frame for frame, and each composited window region matches its source PNG pixel for pixel.
- **RGB compositing, one color conversion.** `overlay` defaults to compositing in YUV 4:2:0, which would subsample chroma *before* compositing. Compositing in RGB and converting once with explicit BT.709 coefficients avoids color shifts. The stream is tagged `bt709` primaries and matrix with an sRGB (`iec61966-2-1`) transfer, which matches how the pixels were produced, so QuickTime and Safari don't show the familiar washed-out screen-recording look.
- **Locked CFR.** Image inputs at `-framerate fps` plus `-r fps` give a constant frame rate. The e2e test checks `nb_read_frames == rendered frames` and `r_frame_rate == 60/1`.

### GIF

The GIF is built in two passes. Pass 1 runs `palettegen` over every composited frame and writes a 256-color palette. Pass 2 runs `paletteuse` with `dither=sierra2_4a:diff_mode=rectangle`. A single-pass `split` graph would buffer every frame in RAM while `palettegen` waits for the end of the stream. `diff_mode=rectangle` only re-dithers changed regions, which keeps static areas stable and shrinks typing animations a lot (a 14s 960×540 demo is 580 KB). GIF delays are stored in 1/100 s, so the frame rate defaults to 30 and is capped at 50.

### Output

ffmpeg writes inside the temp folder. The finished file is then `rename`d into place (atomic on the same device, copy and delete across devices), so a half-written video never sits at the destination path.

## Lifecycle and cleanup (`src/utils/cleanup.js`)

| Exit path | What happens |
| --- | --- |
| Success | Browsers closed, temp folder removed, output moved into place |
| Thrown error | `finally` blocks close browsers and remove the temp folder; the CLI also runs `runCleanup()` |
| SIGINT / SIGTERM / SIGHUP | `AbortController` fires (loops stop, ffmpeg is killed), async cleanup runs with an 8s cap, exit code 130/143/129 |
| Second Ctrl+C | Synchronous teardown (SIGKILL to Chrome and ffmpeg, `rmSync` the temp folder), immediate exit |
| `process.exit` elsewhere | `exit` hook removes any temp folders still registered |

These paths were checked by hand by interrupting real renders: after SIGINT during rendering or SIGTERM during encoding, no temp folders, Chrome processes, ffmpeg processes or partial output files remained. Crash recovery was checked by SIGKILLing a worker's browser mid-render; the worker restarted and the frame sequence completed with no gaps.

## Terminal UI (`src/utils/terminal.js`)

Human-facing output goes to **stderr**, so `--quiet` can print only the output path to stdout for scripts. Colors follow `NO_COLOR`, `FORCE_COLOR`, TTY detection and `TERM=dumb`. Progress bars use sub-character block glyphs and an EMA-smoothed rate and ETA. Without a TTY (CI logs), they print one line per 25%. Emoji and box drawing fall back to ASCII on terminals that can't show them, such as the legacy Windows console and the Linux VT. Errors are `AnimatorError`s with a stable `code`, a hint and an exit code. Stack traces only appear with `--verbose`.

## Testing

`npm test` runs `node:test` suites with no extra dependencies:

- **highlighter:** exact round-trips for every language, adversarial fuzzing (unterminated strings and comments, emoji, CR), classification checks;
- **timeline:** determinism, the duration budget, final-state correctness, monotonic typing, fade then collapse, cursor always in view;
- **git:** real temporary repositories covering added, modified, deleted, renamed, binary, lockfile, pathspec, `--max-files`, size limit, root commit, shallow clone and error codes; plus parser tests with header-like content and odd file names;
- **cli:** every revision syntax, defaults, validation, CSS-injection rejection;
- **encoder:** PATH/PATHEXT scanning, an authoritative `FFMPEG_PATH`, atomic finalize;
- **renderer:** integer layout at many sizes, presence of the spec's visual values, CSP;
- **e2e:** real MP4 and GIF renders checked with `ffprobe` (codec, pixel format, frame rate, color tags, exact frame count) and for temp-folder cleanup.
