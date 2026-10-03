/**
 * Visual themes for the rendered editor.
 *
 * Every theme provides the editor chrome palette plus one color per token
 * class from highlighter.js. Diff highlight colors follow the project spec:
 * additions use rgba(34, 197, 94, 0.2) and deletions a matching red.
 */

const DIFF = Object.freeze({
  added: 'rgba(34, 197, 94, 0.2)',
  addedMarker: '#22c55e',
  removed: 'rgba(239, 68, 68, 0.2)',
  removedMarker: '#ef4444',
});

/** Default canvas gradient (indigo → purple). */
export const DEFAULT_BACKGROUND = Object.freeze(['#6366f1', '#a855f7']);

export const THEMES = Object.freeze({
  nebula: {
    label: 'Nebula (dark, default)',
    background: DEFAULT_BACKGROUND,
    editor: '#1e1e2e',
    chrome: '#181825',
    border: 'rgba(255, 255, 255, 0.06)',
    title: '#a6adc8',
    tab: '#7f849c',
    tabActive: '#cdd6f4',
    accent: '#cba6f7',
    text: '#cdd6f4',
    gutter: '#585b70',
    gutterActive: '#cdd6f4',
    lineHighlight: 'rgba(255, 255, 255, 0.045)',
    cursor: '#f5e0dc',
    status: '#a6adc8',
    ...DIFF,
    tokens: {
      kw: '#cba6f7', str: '#a6e3a1', num: '#fab387', com: '#7f849c', fn: '#89b4fa',
      type: '#f9e2af', const: '#fab387', op: '#89dceb', punc: '#9399b2', prop: '#b4befe',
      tag: '#f38ba8', attr: '#f9e2af', var: '#f38ba8', deco: '#f5c2e7', regex: '#f5c2e7',
    },
    italicComments: true,
  },

  midnight: {
    label: 'Midnight (deep blue)',
    background: ['#0ea5e9', '#6366f1'],
    editor: '#1a1b26',
    chrome: '#16161e',
    border: 'rgba(255, 255, 255, 0.05)',
    title: '#787c99',
    tab: '#5a5f7d',
    tabActive: '#c0caf5',
    accent: '#7aa2f7',
    text: '#c0caf5',
    gutter: '#565f89',
    gutterActive: '#a9b1d6',
    lineHighlight: 'rgba(122, 162, 247, 0.06)',
    cursor: '#c0caf5',
    status: '#787c99',
    ...DIFF,
    tokens: {
      kw: '#bb9af7', str: '#9ece6a', num: '#ff9e64', com: '#565f89', fn: '#7aa2f7',
      type: '#2ac3de', const: '#ff9e64', op: '#89ddff', punc: '#a9b1d6', prop: '#73daca',
      tag: '#f7768e', attr: '#e0af68', var: '#f7768e', deco: '#e0af68', regex: '#b4f9f8',
    },
    italicComments: true,
  },

  daylight: {
    label: 'Daylight (light)',
    background: ['#f472b6', '#818cf8'],
    editor: '#ffffff',
    chrome: '#f3f4f6',
    border: 'rgba(15, 23, 42, 0.08)',
    title: '#4b5563',
    tab: '#6b7280',
    tabActive: '#111827',
    accent: '#6366f1',
    text: '#24292f',
    gutter: '#9ca3af',
    gutterActive: '#374151',
    lineHighlight: 'rgba(99, 102, 241, 0.06)',
    cursor: '#4f46e5',
    status: '#4b5563',
    ...DIFF,
    tokens: {
      kw: '#cf222e', str: '#0a3069', num: '#0550ae', com: '#6e7781', fn: '#8250df',
      type: '#953800', const: '#0550ae', op: '#cf222e', punc: '#57606a', prop: '#0550ae',
      tag: '#116329', attr: '#953800', var: '#953800', deco: '#8250df', regex: '#116329',
    },
    italicComments: false,
  },
});

export const DEFAULT_THEME = 'nebula';

/**
 * Returns a theme, optionally with a custom background gradient.
 * @param {string} name
 * @param {string[] | null} [background]
 */
export function resolveTheme(name, background = null) {
  const theme = THEMES[name];
  if (!theme) return null;
  return { name, ...theme, background: background ?? theme.background };
}
