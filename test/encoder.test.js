import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { after, describe, it } from 'node:test';
import { ffmpegInstallHint, finalizeOutput, findExecutable, formatFromPath, locateFfmpeg } from '../src/engines/encoder.js';

const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'gca-enc-'));
after(() => fs.rmSync(tmp, { recursive: true, force: true }));

describe('findExecutable', () => {
  it('scans PATH entries in order', () => {
    const a = path.join(tmp, 'a');
    const b = path.join(tmp, 'b');
    fs.mkdirSync(a);
    fs.mkdirSync(b);
    const tool = path.join(b, 'mytool');
    fs.writeFileSync(tool, '#!/bin/sh\n', { mode: 0o755 });
    assert.equal(findExecutable('mytool', { envPath: [a, b].join(path.delimiter), platform: process.platform === 'win32' ? 'linux' : process.platform }), tool);
    assert.equal(findExecutable('missing-tool', { envPath: [a, b].join(path.delimiter) }), null);
  });

  it('honours PATHEXT on Windows-style lookups', () => {
    const dir = path.join(tmp, 'win');
    fs.mkdirSync(dir);
    const exe = path.join(dir, 'ffmpeg.exe');
    fs.writeFileSync(exe, '');
    assert.equal(findExecutable('ffmpeg', { envPath: dir, platform: 'win32', pathext: '.COM;.EXE' }), exe);
  });

  it('ignores directories with the same name', () => {
    const dir = path.join(tmp, 'dirs');
    fs.mkdirSync(path.join(dir, 'ffmpeg'), { recursive: true });
    assert.equal(findExecutable('ffmpeg', { envPath: dir, platform: 'linux' }), null);
  });
});

describe('format helpers', () => {
  it('infers formats from extensions', () => {
    assert.equal(formatFromPath('a/b/demo.MP4'), 'mp4');
    assert.equal(formatFromPath('demo.mov'), 'mp4');
    assert.equal(formatFromPath('demo.gif'), 'gif');
    assert.equal(formatFromPath('demo.webm'), null);
  });

  it('lists the current platform first in install instructions', () => {
    assert.match(ffmpegInstallHint('darwin').split('\n')[2], /brew install ffmpeg/);
    assert.match(ffmpegInstallHint('win32').split('\n')[2], /winget/);
    assert.match(ffmpegInstallHint('linux').split('\n')[2], /apt/);
  });
});

describe('locateFfmpeg', () => {
  it('treats an invalid FFMPEG_PATH as an explicit, friendly error', async () => {
    const previous = process.env.FFMPEG_PATH;
    process.env.FFMPEG_PATH = path.join(tmp, 'not-ffmpeg');
    try {
      await assert.rejects(locateFfmpeg('mp4'), (error) => {
        assert.equal(error.code, 'E_FFMPEG_MISSING');
        assert.match(error.hint, /Install ffmpeg/);
        return true;
      });
    } finally {
      if (previous === undefined) delete process.env.FFMPEG_PATH;
      else process.env.FFMPEG_PATH = previous;
    }
  });
});

describe('finalizeOutput', () => {
  it('moves the file into a freshly created folder, replacing existing output', async () => {
    const src = path.join(tmp, 'out.mp4');
    const dest = path.join(tmp, 'nested', 'deeper', 'final.mp4');
    fs.mkdirSync(path.dirname(dest), { recursive: true });
    fs.writeFileSync(dest, 'old');
    fs.writeFileSync(src, 'new');
    await finalizeOutput(src, dest);
    assert.equal(fs.readFileSync(dest, 'utf8'), 'new');
    assert.equal(fs.existsSync(src), false);
  });
});
