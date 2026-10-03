/**
 * End-to-end test: renders real videos with headless Chrome and ffmpeg.
 * Skipped automatically when ffmpeg is not installed.
 */
import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { after, before, describe, it } from 'node:test';
import { generateAnimation } from '../src/cli.js';
import { locateFfmpeg } from '../src/engines/encoder.js';
import { createRepo } from './helpers/repo.js';

let ffmpegPath = null;
try {
  ffmpegPath = (await locateFfmpeg('mp4')).path;
} catch {
  ffmpegPath = null;
}

const ffprobe = ffmpegPath ? path.join(path.dirname(ffmpegPath), process.platform === 'win32' ? 'ffprobe.exe' : 'ffprobe') : null;

function probe(file) {
  const out = execFileSync(ffprobe, [
    '-v', 'error', '-count_frames', '-select_streams', 'v:0',
    '-show_entries', 'stream=codec_name,pix_fmt,width,height,r_frame_rate,nb_read_frames,color_space',
    '-of', 'json', file,
  ], { encoding: 'utf8' });
  return JSON.parse(out).streams[0];
}

describe('end-to-end rendering', { skip: !ffmpegPath && 'ffmpeg not installed', timeout: 300_000 }, () => {
  let repo;
  const outDir = fs.mkdtempSync(path.join(os.tmpdir(), 'gca-e2e-'));

  before(() => {
    repo = createRepo();
    repo.write('src/math.js', 'export function add(a, b) {\n  return a + b;\n}\n');
    repo.commit('initial');
    repo.write('src/math.js', 'export function add(a, b) {\n  return a + b;\n}\n\nexport const square = (x) => x * x; // 🚀\n');
    repo.write('notes.md', '# Notes\n\n- fast\n');
    repo.commit('feat: square');
  });

  after(() => {
    repo?.cleanup();
    fs.rmSync(outDir, { recursive: true, force: true });
  });

  it('renders a web-compatible H.264 MP4', async () => {
    const before = new Set(fs.readdirSync(os.tmpdir()).filter((f) => f.startsWith('git-commit-animator-')));
    const output = path.join(outDir, 'out.mp4');
    const result = await generateAnimation({ repo: repo.dir, output, size: '640x360', maxDuration: 4, workers: 2 });
    assert.equal(result.output, output);
    assert.ok(fs.statSync(output).size > 1000);
    assert.deepEqual(result.files, ['notes.md', 'src/math.js']);

    const stream = probe(output);
    assert.equal(stream.codec_name, 'h264');
    assert.equal(stream.pix_fmt, 'yuv420p');
    assert.equal(stream.width, 640);
    assert.equal(stream.height, 360);
    assert.equal(stream.r_frame_rate, '60/1');
    assert.equal(stream.color_space, 'bt709');
    assert.equal(Number(stream.nb_read_frames), result.frames, 'every rendered frame is in the video');
    assert.ok(result.uniqueFrames < result.frames, 'duplicate frames were deduplicated');

    const leftovers = fs.readdirSync(os.tmpdir()).filter((f) => f.startsWith('git-commit-animator-') && !before.has(f));
    assert.deepEqual(leftovers, [], 'temporary frames are cleaned up');
  });

  it('renders an optimized GIF', async () => {
    const output = path.join(outDir, 'out.gif');
    const result = await generateAnimation({ repo: repo.dir, output, size: '480x270', maxDuration: 3, workers: 1 });
    const stream = probe(output);
    assert.equal(stream.codec_name, 'gif');
    assert.equal(stream.width, 480);
    assert.equal(Number(stream.nb_read_frames), result.frames);
    assert.equal(result.fps, 30);
  });
});
