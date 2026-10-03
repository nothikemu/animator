/**
 * Programmatic API.
 *
 * @example
 * import { generateAnimation } from 'git-commit-animator';
 * const result = await generateAnimation({ repo: '.', target: 'HEAD', output: 'demo.mp4' });
 * console.log(result.output);
 */
export { generateAnimation, normalizeOptions, parseCliArgs, VERSION } from './cli.js';
export { collectDiff, openRepository, resolveRange, parseUnifiedDiff } from './utils/git.js';
export { createFileModel, createTimeline, toPagePayload } from './engines/timeline.js';
export { FrameRenderer, computeLayout, buildTemplate, launchBrowser } from './engines/renderer.js';
export { encodeVideo, locateFfmpeg, findExecutable, finalizeOutput } from './engines/encoder.js';
export { tokenize, detectLanguage, supportedLanguages } from './engines/highlighter.js';
export { THEMES, resolveTheme } from './engines/themes.js';
export { AnimatorError, AbortError } from './utils/errors.js';
