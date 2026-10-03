import assert from 'node:assert/strict';
import { describe, it } from 'node:test';
import {
  createFileModel,
  createRandom,
  createTimeline,
  hashSeed,
  keystrokeOffsets,
  splitLines,
  toPagePayload,
} from '../src/engines/timeline.js';

const MODIFIED = {
  path: 'src/app.js',
  oldPath: 'src/app.js',
  status: 'M',
  oldText: 'const a = 1;\nconst b = 2;\nconsole.log(a);\n',
  newText: 'const a = 1;\nconst c = 3;\nconst d = 4;\nconsole.log(a);\nexport { a };\n',
  hunks: [
    { oldStart: 2, oldLines: 1, newStart: 2, newLines: 2, lines: [] },
    { oldStart: 3, oldLines: 0, newStart: 5, newLines: 1, lines: [] },
  ],
};

const ADDED = {
  path: 'new.py',
  oldPath: 'new.py',
  status: 'A',
  oldText: '',
  newText: 'def hello():\n    return "hi"\n',
  hunks: [{ oldStart: 0, oldLines: 0, newStart: 1, newLines: 2, lines: [] }],
};

const DELETED = {
  path: 'gone.md',
  oldPath: 'gone.md',
  status: 'D',
  oldText: '# Old\n\ntext\n',
  newText: '',
  hunks: [{ oldStart: 1, oldLines: 3, newStart: 0, newLines: 0, lines: [] }],
};

function runAll(timeline) {
  return [...timeline.frames()];
}

describe('splitLines', () => {
  it('drops the phantom line after a trailing newline', () => {
    assert.deepEqual(splitLines('a\nb\n'), ['a', 'b']);
    assert.deepEqual(splitLines('a\nb'), ['a', 'b']);
    assert.deepEqual(splitLines(''), []);
    assert.deepEqual(splitLines('\n'), ['']);
  });
});

describe('createFileModel', () => {
  it('interleaves context, deleted and added rows in file order', () => {
    const model = createFileModel(MODIFIED, 0);
    assert.deepEqual(model.rows.map((r) => [r.kind, r.text]), [
      ['ctx', 'const a = 1;'],
      ['del', 'const b = 2;'],
      ['add', 'const c = 3;'],
      ['add', 'const d = 4;'],
      ['ctx', 'console.log(a);'],
      ['add', 'export { a };'],
    ]);
    assert.equal(model.hunks.length, 2);
    assert.deepEqual(model.addOrder, [2, 3, 5]);
    assert.equal(model.additions, 3);
    assert.equal(model.deletions, 1);
    assert.equal(model.language.id, 'javascript');
  });

  it('models added and deleted files', () => {
    const added = createFileModel(ADDED, 0);
    assert.deepEqual(added.rows.map((r) => r.kind), ['add', 'add']);
    const deleted = createFileModel(DELETED, 0);
    assert.deepEqual(deleted.rows.map((r) => r.kind), ['del', 'del', 'del']);
  });

  it('rejects hunks that do not match the file contents', () => {
    const broken = { ...MODIFIED, hunks: [{ oldStart: 2, oldLines: 1, newStart: 4, newLines: 1, lines: [] }] };
    assert.throws(() => createFileModel(broken, 0), /Inconsistent diff hunk/);
  });

  it('produces a compact page payload with tokens for every row', () => {
    const payload = toPagePayload(createFileModel(MODIFIED, 3));
    assert.equal(payload.index, 3);
    assert.equal(payload.name, 'app.js');
    assert.equal(payload.directory, 'src');
    assert.equal(payload.rows.length, 6);
    assert.equal(payload.rows[1][0], 'd');
    assert.equal(payload.rows[2][1].map((t) => t[1]).join(''), 'const c = 3;');
  });
});

describe('keystrokeOffsets', () => {
  it('types indentation as one keystroke', () => {
    assert.deepEqual(keystrokeOffsets('    ab'), [4, 5, 6]);
  });

  it('never splits grapheme clusters', () => {
    const text = 'a👩‍💻b';
    const offsets = keystrokeOffsets(text);
    assert.deepEqual(offsets, [1, 1 + '👩‍💻'.length, text.length]);
  });

  it('returns nothing for an empty line', () => {
    assert.deepEqual(keystrokeOffsets(''), []);
  });
});

describe('createRandom / hashSeed', () => {
  it('is deterministic per seed', () => {
    const a = createRandom(42);
    const b = createRandom(42);
    const c = createRandom(43);
    const seqA = Array.from({ length: 5 }, a);
    assert.deepEqual(seqA, Array.from({ length: 5 }, b));
    assert.notDeepEqual(seqA, Array.from({ length: 5 }, c));
    for (const v of seqA) assert.ok(v >= 0 && v < 1);
  });

  it('hashes strings to stable 32-bit seeds', () => {
    assert.equal(hashSeed('abc'), hashSeed('abc'));
    assert.notEqual(hashSeed('abc'), hashSeed('abd'));
    assert.ok(Number.isInteger(hashSeed('x')) && hashSeed('x') >= 0);
  });
});

describe('createTimeline', () => {
  const models = [createFileModel(MODIFIED, 0), createFileModel(ADDED, 1), createFileModel(DELETED, 2)];
  const options = { fps: 30, visibleLines: 20, seed: 7, maxDuration: 60 };

  it('is fully deterministic for a given seed', () => {
    const a = JSON.stringify(runAll(createTimeline(models, options)));
    const b = JSON.stringify(runAll(createTimeline(models, options)));
    assert.equal(a, b);
    const c = JSON.stringify(runAll(createTimeline(models, { ...options, seed: 8 })));
    assert.notEqual(a, c);
  });

  it('yields exactly totalFrames frames', () => {
    const timeline = createTimeline(models, options);
    assert.equal(runAll(timeline).length, timeline.totalFrames);
    assert.equal(timeline.totalFrames, Math.ceil((timeline.durationMs / 1000) * options.fps) + 1);
  });

  it('respects the maximum duration by compressing the schedule', () => {
    const relaxed = createTimeline(models, { ...options, maxDuration: 600 });
    const tight = createTimeline(models, { ...options, maxDuration: 3 });
    assert.ok(relaxed.durationMs > 3000);
    assert.ok(tight.durationMs <= 3000 + 1e-6);
    assert.ok(tight.stats.compressed);
    assert.equal(relaxed.stats.compressed, false);
  });

  it('keeps typing delays within the 15-45ms humanized range', () => {
    const timeline = createTimeline([createFileModel(ADDED, 0)], { ...options, maxDuration: 600 });
    assert.equal(timeline.stats.typingScale, 1);
    assert.equal(timeline.stats.keystrokes, keystrokeOffsets('def hello():').length + keystrokeOffsets('    return "hi"').length);
  });

  it('ends each file in its final state', () => {
    const frames = runAll(createTimeline(models, options));
    const lastOf = (f) => frames.filter((v) => v.f === f).at(-1);

    const modified = lastOf(0);
    const kinds = modified.rows.map(([r]) => models[0].rows[r].kind);
    assert.ok(!kinds.includes('del'), 'deleted rows are gone');
    assert.equal(kinds.filter((k) => k === 'add').length, 3, 'all added rows present');
    for (const row of modified.rows) assert.equal(row[3], -1, 'all rows fully typed');
    assert.deepEqual(modified.rows.map((r) => r[5]), [1, 2, 3, 4, 5], 'line numbers follow the new file');

    const deleted = lastOf(2);
    assert.deepEqual(deleted.rows.map((r) => r[0]), [-1], 'emptied file shows a blank line');
  });

  it('reveals added text progressively and never goes backwards', () => {
    const frames = runAll(createTimeline([createFileModel(ADDED, 0)], options));
    let typed = 0;
    for (const view of frames) {
      const count = view.rows.reduce((n, [r, , h, chars]) => {
        if (r < 0 || h === 0) return n;
        const len = createFileModel(ADDED, 0).rows[r].text.length;
        return n + (chars < 0 ? len : chars);
      }, 0);
      assert.ok(count >= typed, 'typed character count is monotonic');
      typed = count;
    }
    assert.equal(typed, 'def hello():'.length + '    return "hi"'.length);
  });

  it('fades deleted rows in before collapsing them', () => {
    const frames = runAll(createTimeline([createFileModel(DELETED, 0)], { ...options, fps: 60 }));
    const alphas = frames.flatMap((v) => v.rows.filter((r) => r[0] >= 0).map((r) => r[4]));
    assert.ok(alphas.includes(0));
    assert.ok(alphas.some((a) => a > 0 && a < 1), 'partial fade');
    assert.ok(alphas.includes(1));
    const heights = frames.flatMap((v) => v.rows.filter((r) => r[0] >= 0).map((r) => r[2]));
    assert.ok(heights.some((h) => h > 0 && h < 1), 'rows collapse smoothly');
  });

  it('keeps the cursor inside the viewport while typing a long file', () => {
    const lines = Array.from({ length: 120 }, (_, i) => `line ${i}`);
    const longFile = { path: 'long.txt', oldPath: 'long.txt', status: 'A', oldText: '', newText: `${lines.join('\n')}\n`, hunks: [{ oldStart: 0, oldLines: 0, newStart: 1, newLines: 120, lines: [] }] };
    const visibleLines = 15;
    const frames = runAll(createTimeline([createFileModel(longFile, 0)], { fps: 30, visibleLines, seed: 1, maxDuration: 20 }));
    for (const view of frames) {
      const cursorRow = view.rows.find(([r]) => r === view.cur[0]);
      if (view.cur[0] < 0) continue;
      assert.ok(cursorRow, 'cursor row is rendered');
      assert.ok(cursorRow[1] >= -0.01 && cursorRow[1] < visibleLines, `cursor at ${cursorRow[1]} is visible`);
    }
  });
});
