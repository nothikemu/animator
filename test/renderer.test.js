import assert from 'node:assert/strict';
import { describe, it } from 'node:test';
import { buildTemplate, computeLayout, frameFileName } from '../src/engines/renderer.js';
import { resolveTheme } from '../src/engines/themes.js';

describe('computeLayout', () => {
  for (const [w, h] of [[1920, 1080], [1280, 720], [960, 540], [3840, 2160], [1080, 1080], [1601, 899]]) {
    it(`places the window on whole pixels at ${w}x${h}`, () => {
      const layout = computeLayout({ width: w, height: h });
      const r = layout.window;
      for (const v of [r.x, r.y, r.width, r.height, layout.lineHeight, layout.titleH, layout.tabH, layout.statusH]) {
        assert.ok(Number.isInteger(v), `${v} is an integer`);
      }
      assert.ok(r.x > 0 && r.y > 0 && r.x + r.width < w && r.y + r.height < h, 'window fits inside the canvas');
      assert.ok(layout.visibleLines > 5);
    });
  }

  it('matches the reference design at 1080p', () => {
    const layout = computeLayout({ width: 1920, height: 1080 });
    assert.equal(layout.scale, 1);
    assert.equal(layout.fontSize, 22);
    assert.deepEqual(layout.window, { x: 144, y: 81, width: 1632, height: 918 });
  });
});

describe('buildTemplate', () => {
  const html = buildTemplate({ layout: computeLayout({ width: 1920, height: 1080 }), theme: resolveTheme('nebula') });

  it('locks the page down with a strict CSP', () => {
    assert.match(html, /Content-Security-Policy" content="default-src 'none'/);
  });

  it('includes the spec visuals', () => {
    assert.match(html, /linear-gradient\(135deg,var\(--bg-from\) 0%,var\(--bg-to\) 100%\)/);
    assert.match(html, /--bg-from:#6366f1;--bg-to:#a855f7/);
    assert.match(html, /--radius:12px;--sh-y:25px;--sh-blur:50px;--sh-spread:-12px/);
    assert.match(html, /rgba\(0,0,0,\.5\)/);
    assert.match(html, /--added:rgba\(34, 197, 94, 0\.2\)/);
    assert.match(html, /'JetBrains Mono', 'Fira Code'.*'Courier New', monospace/);
    assert.match(html, /dot r.*dot y.*dot g/);
  });

  it('embeds the bundled font and the page runtime', () => {
    assert.match(html, /@font-face\{font-family:'JetBrains Mono'.*data:font\/woff2;base64,/);
    assert.match(html, /window\.__gca = \{/);
  });
});

describe('frameFileName', () => {
  it('zero-pads indices for the ffmpeg image2 pattern', () => {
    assert.equal(frameFileName(0), 'frame_000000.png');
    assert.equal(frameFileName(1234), 'frame_001234.png');
  });
});
