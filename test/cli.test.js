import assert from 'node:assert/strict';
import path from 'node:path';
import { describe, it } from 'node:test';
import { normalizeOptions, parseBackground, parseCliArgs, parseSize } from '../src/cli.js';

const parse = (...argv) => parseCliArgs(argv).options;

describe('parseCliArgs defaults', () => {
  it('works with zero configuration', () => {
    const o = parse();
    assert.equal(o.repo, process.cwd());
    assert.equal(o.base, null);
    assert.equal(o.target, null);
    assert.equal(o.output, path.resolve(process.cwd(), 'animation.mp4'));
    assert.equal(o.format, 'mp4');
    assert.deepEqual([o.width, o.height, o.fps], [1920, 1080, 60]);
    assert.equal(o.theme, 'nebula');
    assert.equal(o.maxDuration, 30);
  });

  it('switches to GIF defaults from the output extension', () => {
    const o = parse('-o', 'demo.gif');
    assert.equal(o.format, 'gif');
    assert.deepEqual([o.width, o.height, o.fps], [1280, 720, 30]);
  });

  it('appends the extension when only --format is given', () => {
    assert.equal(parse('--format', 'gif').output, path.resolve('animation.gif'));
    assert.equal(parse('--format', 'gif', '-o', 'out/demo').output, path.resolve('out/demo.gif'));
  });
});

describe('revision arguments', () => {
  it('treats a single argument as the commit to animate', () => {
    const o = parse('abc123');
    assert.equal(o.target, 'abc123');
    assert.equal(o.base, null);
  });

  it('accepts base and target like git diff', () => {
    const o = parse('v1.0.0', 'v1.1.0');
    assert.deepEqual([o.base, o.target], ['v1.0.0', 'v1.1.0']);
  });

  it('accepts two- and three-dot ranges', () => {
    assert.deepEqual([parse('HEAD~3..HEAD').base, parse('HEAD~3..HEAD').target], ['HEAD~3', 'HEAD']);
    const sym = parse('main...feature');
    assert.deepEqual([sym.base, sym.target, sym.symmetric], ['main', 'feature', true]);
    assert.equal(parse('v1..').target, 'HEAD');
  });

  it('collects pathspecs after --', () => {
    const o = parse('HEAD~1', 'HEAD', '--', 'src/', 'docs/*.md');
    assert.deepEqual(o.pathspec, ['src/', 'docs/*.md']);
    assert.deepEqual([o.base, o.target], ['HEAD~1', 'HEAD']);
  });

  it('rejects conflicting or excessive revisions', () => {
    assert.throws(() => parse('a', '--target', 'b'), { code: 'E_USAGE' });
    assert.throws(() => parse('a', 'b', 'c'), { code: 'E_USAGE' });
  });
});

describe('validation', () => {
  it('rejects unknown options and missing values', () => {
    assert.throws(() => parse('--nope'), { code: 'E_USAGE', message: /Unknown option --nope/ });
    assert.throws(() => parse('--fps'), { code: 'E_USAGE' });
  });

  it('validates numbers', () => {
    assert.throws(() => parse('--fps', '0'), { code: 'E_USAGE' });
    assert.throws(() => parse('--fps', '29.97'), { code: 'E_USAGE' });
    assert.throws(() => parse('--crf', '60'), { code: 'E_USAGE' });
    assert.throws(() => parse('--speed', 'fast'), { code: 'E_USAGE' });
    assert.equal(parse('--speed', '1.5').speed, 1.5);
  });

  it('validates sizes and presets', () => {
    assert.deepEqual(parseSize('720p'), [1280, 720]);
    assert.deepEqual(parseSize('1600x900'), [1600, 900]);
    assert.deepEqual(parseSize('4K'), [3840, 2160]);
    assert.throws(() => parseSize('big'), { code: 'E_USAGE' });
    assert.throws(() => parse('--size', '1281x720'), { message: /odd dimension/ });
    assert.doesNotThrow(() => parse('--size', '1281x721', '-o', 'x.gif'));
    assert.throws(() => parse('--size', '100x100'), { message: /out of range/ });
  });

  it('caps GIF frame rates at 50fps with a warning', () => {
    const o = parse('-o', 'x.gif', '--fps', '60');
    assert.equal(o.fps, 50);
    assert.equal(o.warnings.length, 1);
  });

  it('validates themes, formats and output names', () => {
    assert.throws(() => parse('--theme', 'neon'), { message: /Unknown theme/ });
    assert.throws(() => parse('--format', 'webm'), { message: /Unsupported --format/ });
    assert.throws(() => parse('-o', 'video.avi'), { message: /Cannot tell the format/ });
    assert.throws(() => parse('-o', 'a.gif', '--format', 'mp4'), { message: /does not match/ });
    assert.equal(parse('--theme', 'DAYLIGHT').theme, 'daylight');
  });

  it('parses background colors and refuses CSS injection', () => {
    assert.deepEqual(parseBackground('#000,#fff'), ['#000', '#fff']);
    assert.deepEqual(parseBackground('rgb(1, 2, 3), hsl(10 50% 50%)'), ['rgb(1, 2, 3)', 'hsl(10 50% 50%)']);
    assert.deepEqual(parseBackground('teal'), ['teal', 'teal']);
    assert.throws(() => parseBackground('red;}</style><script>alert(1)</script>'), { code: 'E_USAGE' });
    assert.throws(() => parseBackground('#1,#2,#3'), { code: 'E_USAGE' });
  });

  it('short-circuits for help, version and theme listing', () => {
    assert.equal(parseCliArgs(['--help']).help, true);
    assert.equal(parseCliArgs(['-v']).version, true);
    assert.equal(parseCliArgs(['--list-themes']).options, null);
  });
});

describe('normalizeOptions (programmatic API)', () => {
  it('accepts typed values', () => {
    const o = normalizeOptions({ size: [1280, 720], background: ['#111', '#222'], output: 'x.mp4' });
    assert.deepEqual([o.width, o.height], [1280, 720]);
    assert.deepEqual(o.background, ['#111', '#222']);
  });
});
