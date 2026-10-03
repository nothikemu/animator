import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import fs from 'node:fs';
import { after, before, describe, it } from 'node:test';
import os from 'node:os';
import {
  collectDiff,
  decodeText,
  isBinaryBuffer,
  isGeneratedFile,
  openRepository,
  parseNumstat,
  parseRawDiff,
  parseUnifiedDiff,
  resolveRange,
  validateRevision,
} from '../src/utils/git.js';
import { createFileModel } from '../src/engines/timeline.js';
import { createRepo } from './helpers/repo.js';

describe('parseUnifiedDiff', () => {
  it('parses zero-context hunks', () => {
    const { hunks } = parseUnifiedDiff([
      'diff --git a/x b/x',
      '--- a/x',
      '+++ b/x',
      '@@ -2 +2,2 @@',
      '-old',
      '+new one',
      '+new two',
      '@@ -10,0 +12 @@ context',
      '+appended',
    ].join('\n'));
    assert.equal(hunks.length, 2);
    assert.deepEqual(
      [hunks[0].oldStart, hunks[0].oldLines, hunks[0].newStart, hunks[0].newLines],
      [2, 1, 2, 2],
    );
    assert.deepEqual(hunks[0].lines.map((l) => l.type + l.text), ['-old', '+new one', '+new two']);
    assert.deepEqual([hunks[1].oldLines, hunks[1].newStart, hunks[1].newLines], [0, 12, 1]);
  });

  it('does not mistake content that looks like headers for headers', () => {
    const { hunks } = parseUnifiedDiff([
      '@@ -1,2 +1,2 @@',
      '--- not a header',
      '-@@ -9 +9 @@',
      '+++ also content',
      '+@@ still content',
    ].join('\n'));
    assert.equal(hunks.length, 1);
    assert.deepEqual(hunks[0].lines.map((l) => l.text), ['-- not a header', '@@ -9 +9 @@', '++ also content', '@@ still content']);
  });

  it('ignores "no newline" markers and flags binary diffs', () => {
    const { hunks } = parseUnifiedDiff('@@ -1 +1 @@\n-a\n\\ No newline at end of file\n+b\n');
    assert.deepEqual(hunks[0].lines.map((l) => l.type), ['-', '+']);
    assert.equal(parseUnifiedDiff('Binary files a/x and b/x differ\n').binary, true);
  });
});

describe('raw/numstat parsers', () => {
  it('parses -z output including renames and unusual paths', () => {
    const raw = [
      ':100644 100644 aaa bbb M', 'src/a file.js',
      ':000000 100644 000 ccc A', 'docs/ünïcödé.md',
      ':100644 100644 ddd eee R087', 'old name.txt', 'new name.txt',
      '',
    ].join('\0');
    const entries = parseRawDiff(raw);
    assert.equal(entries.length, 3);
    assert.deepEqual([entries[0].status, entries[0].newPath], ['M', 'src/a file.js']);
    assert.equal(entries[1].newPath, 'docs/ünïcödé.md');
    assert.deepEqual([entries[2].status, entries[2].similarity, entries[2].oldPath, entries[2].newPath], ['R', 87, 'old name.txt', 'new name.txt']);

    const numstat = ['3\t1\tsrc/a file.js', '-\t-\timg.png', '2\t2\t', 'old name.txt', 'new name.txt', ''].join('\0');
    const stats = parseNumstat(numstat);
    assert.deepEqual(stats.map((s) => [s.path, s.binary, s.additions, s.deletions]), [
      ['src/a file.js', false, 3, 1],
      ['img.png', true, 0, 0],
      ['new name.txt', false, 2, 2],
    ]);
  });
});

describe('text helpers', () => {
  it('detects binary content beyond NUL bytes', () => {
    assert.equal(isBinaryBuffer(Buffer.from([0x41, 0x00, 0x42])), true);
    assert.equal(isBinaryBuffer(Buffer.from('plain ascii\n')), false);
    assert.equal(isBinaryBuffer(Buffer.from('ünïcödé 🚀\n'.repeat(20))), false);
    assert.equal(isBinaryBuffer(Buffer.from('caf\xe9 r\xe9sum\xe9\n'.repeat(20), 'latin1')), false);
    let misses = 0;
    for (let i = 0; i < 50; i++) if (!isBinaryBuffer(crypto.randomBytes(400))) misses++;
    assert.equal(misses, 0);
  });

  it('normalizes BOM and line endings', () => {
    assert.equal(decodeText(Buffer.from('﻿a\r\nb\r\n')), 'a\nb\n');
    assert.equal(decodeText(Buffer.from('a\rb')), 'ab');
  });

  it('recognizes lockfiles and generated bundles', () => {
    for (const f of ['package-lock.json', 'web/yarn.lock', 'Cargo.lock', 'dist/app.min.js', 'x.js.map', 'go.sum']) {
      assert.ok(isGeneratedFile(f), f);
    }
    for (const f of ['src/lock.js', 'package.json', 'README.md']) assert.ok(!isGeneratedFile(f), f);
  });

  it('rejects revisions that look like options', () => {
    assert.throws(() => validateRevision('--output=/tmp/x', 'target'), { code: 'E_BAD_REVISION' });
    assert.throws(() => validateRevision('', 'base'), { code: 'E_BAD_REVISION' });
    assert.doesNotThrow(() => validateRevision('HEAD~2', 'base'));
  });
});

describe('repository access', () => {
  let repo;
  let commits;

  before(() => {
    repo = createRepo();
    repo.write('src/app.js', 'const a = 1;\nconst b = 2;\nconsole.log(a);\n');
    repo.write('README.md', '# Demo\n');
    repo.write('image.bin', Buffer.from([0, 1, 2, 3, 255, 0, 7]));
    repo.write('old.txt', 'goodbye\nworld\n');
    repo.write('stays the same.txt', 'stable\ncontent\nhere\nfor\nrename\ndetection\n');
    const first = repo.commit('initial');

    repo.write('src/app.js', 'const a = 1;\nconst c = 3;\nconsole.log(a, c);\nexport { a };\n');
    repo.write('src/new.py', 'def hi():\n    return 1\n');
    repo.write('image.bin', Buffer.from([0, 9, 9, 9, 255, 0, 7]));
    repo.write('package-lock.json', '{"lockfileVersion": 3}\n');
    repo.remove('old.txt');
    repo.remove('stays the same.txt');
    repo.write('renamed file.txt', 'stable\ncontent\nhere\nfor\nrename\ndetection\n');
    const second = repo.commit('second');
    commits = { first, second };
  });

  after(() => repo?.cleanup());

  it('opens a repository from a nested folder', async () => {
    const opened = await openRepository(`${repo.dir}/src`);
    assert.equal(opened.root, await openRepository(repo.dir).then((r) => r.root));
    assert.equal(opened.bare, false);
  });

  it('fails clearly outside a repository and for missing paths', async () => {
    await assert.rejects(openRepository(os.tmpdir()), (error) => ['E_NOT_A_REPO', 'E_GIT_FAILED'].includes(error.code));
    await assert.rejects(openRepository(`${repo.dir}/does-not-exist`), { code: 'E_REPO_NOT_FOUND' });
    await assert.rejects(openRepository(`${repo.dir}/README.md`), { code: 'E_REPO_NOT_DIRECTORY' });
  });

  it('defaults to HEAD~1 → HEAD', async () => {
    const opened = await openRepository(repo.dir);
    const range = await resolveRange(opened, {});
    assert.equal(range.target.hash, commits.second);
    assert.equal(range.base.hash, commits.first);
    assert.equal(range.target.subject, 'second');
  });

  it('uses the empty tree as the base of a root commit', async () => {
    const opened = await openRepository(repo.dir);
    const range = await resolveRange(opened, { target: commits.first });
    assert.equal(range.base.isEmptyTree, true);
  });

  it('reports unknown revisions with a friendly error', async () => {
    const opened = await openRepository(repo.dir);
    await assert.rejects(resolveRange(opened, { target: 'nope123' }), { code: 'E_BAD_REVISION' });
    await assert.rejects(resolveRange(opened, { base: 'HEAD~9' }), { code: 'E_BAD_REVISION' });
  });

  it('collects modified, added, deleted and renamed text files', async () => {
    const diff = await collectDiff({ repoPath: repo.dir });
    const byPath = Object.fromEntries(diff.files.map((f) => [f.path, f]));
    assert.deepEqual(Object.keys(byPath).sort(), ['old.txt', 'src/app.js', 'src/new.py']);
    assert.equal(byPath['src/new.py'].status, 'A');
    assert.equal(byPath['old.txt'].status, 'D');
    assert.equal(byPath['src/app.js'].status, 'M');

    const skipped = Object.fromEntries(diff.skipped.map((s) => [s.path, s.reason]));
    assert.equal(skipped['image.bin'], 'binary file');
    assert.equal(skipped['package-lock.json'], 'lockfile / generated');
    assert.equal(skipped['renamed file.txt'], 'no content change');

    // Every collected file must produce a consistent row model.
    for (const file of diff.files) assert.doesNotThrow(() => createFileModel(file, 0));
    const model = createFileModel(byPath['src/app.js'], 0);
    assert.deepEqual(model.rows.filter((r) => r.kind !== 'del').map((r) => r.text), ['const a = 1;', 'const c = 3;', 'console.log(a, c);', 'export { a };']);
  });

  it('honours pathspecs, --all-files and --max-files', async () => {
    const onlySrc = await collectDiff({ repoPath: repo.dir, pathspec: ['src/'] });
    assert.deepEqual(onlySrc.files.map((f) => f.path).sort(), ['src/app.js', 'src/new.py']);

    const all = await collectDiff({ repoPath: repo.dir, includeGenerated: true });
    assert.ok(all.files.some((f) => f.path === 'package-lock.json'));

    const limited = await collectDiff({ repoPath: repo.dir, maxFiles: 1 });
    assert.equal(limited.files.length, 1);
    assert.ok(limited.skipped.some((s) => s.reason.startsWith('over --max-files')));
  });

  it('refuses to treat a shallow-clone boundary as a root commit', async () => {
    const shallowDir = `${repo.dir}-shallow`;
    repo.git('clone', '-q', '--depth', '1', `file://${repo.dir}`, shallowDir);
    try {
      const opened = await openRepository(shallowDir);
      await assert.rejects(resolveRange(opened, {}), { code: 'E_SHALLOW_CLONE' });
    } finally {
      fs.rmSync(shallowDir, { recursive: true, force: true });
    }
  });

  it('skips files above the size limit', async () => {
    const diff = await collectDiff({ repoPath: repo.dir, maxFileBytes: 10 });
    assert.ok(diff.skipped.some((s) => s.path === 'src/app.js' && /larger than/.test(s.reason)));
  });
});
