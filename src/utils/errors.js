/**
 * Typed error used across the whole tool.
 *
 * Every failure that can reasonably be caused by the user's environment or
 * input (missing ffmpeg, bad commit hash, not a repository, ...) is thrown as
 * an AnimatorError carrying a stable `code` and a human-friendly `hint`. The
 * CLI renders those as a clean message instead of a raw stack trace.
 */
export class AnimatorError extends Error {
  /**
   * @param {string} message Short, user-facing description of what went wrong.
   * @param {object} [options]
   * @param {string} [options.code] Stable machine-readable code (E_*).
   * @param {string} [options.hint] Actionable advice printed below the message.
   * @param {string} [options.details] Extra diagnostic output (shown with --verbose).
   * @param {unknown} [options.cause] Underlying error.
   * @param {number} [options.exitCode] Process exit code to use (default 1).
   */
  constructor(message, { code = 'E_ANIMATOR', hint, details, cause, exitCode = 1 } = {}) {
    super(message, cause === undefined ? undefined : { cause });
    this.name = 'AnimatorError';
    this.code = code;
    this.hint = hint;
    this.details = details;
    this.exitCode = exitCode;
  }
}

/** Raised when the run is interrupted (SIGINT/SIGTERM) or explicitly aborted. */
export class AbortError extends AnimatorError {
  constructor(message = 'Operation aborted') {
    super(message, { code: 'E_ABORTED', exitCode: 130 });
    this.name = 'AbortError';
  }
}

/**
 * Throws an AbortError when the given signal has been aborted.
 * @param {AbortSignal | undefined} signal
 */
export function throwIfAborted(signal) {
  if (signal?.aborted) throw new AbortError();
}
