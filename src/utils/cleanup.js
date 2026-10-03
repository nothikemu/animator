/**
 * Process-wide resource cleanup.
 *
 * Long renders create temporary frame folders, headless browsers and ffmpeg
 * processes. This module guarantees they are torn down on every exit path:
 *
 *   - normal completion   → callers dispose their resources explicitly;
 *   - thrown errors       → `runCleanup()` from the CLI's error handler;
 *   - SIGINT/SIGTERM/HUP  → async cleanup with a hard timeout, then exit;
 *   - a second Ctrl+C     → immediate synchronous teardown and exit;
 *   - `process.exit()`    → synchronous fallback that removes temp folders.
 */

import fs from 'node:fs';
import fsp from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';

/** @type {Map<number, { name: string, fn: () => unknown, syncFn?: () => void }>} */
const tasks = new Map();
/** @type {Set<string>} */
const tempDirs = new Set();
const controller = new AbortController();
let nextId = 1;
let handlersInstalled = false;
let shuttingDown = false;

const SIGNAL_EXIT_CODES = { SIGINT: 130, SIGTERM: 143, SIGHUP: 129 };
const CLEANUP_TIMEOUT_MS = 8000;

/** Signal that fires when the process is asked to stop. */
export const shutdownSignal = controller.signal;

/** True once a termination signal has been received. */
export function isShuttingDown() {
  return shuttingDown;
}

/**
 * Registers a cleanup task. Tasks run in reverse registration order.
 *
 * @param {string} name Human-readable label (for debugging).
 * @param {() => unknown} fn Async-capable cleanup.
 * @param {() => void} [syncFn] Optional synchronous variant used when the process is exiting immediately.
 * @returns {() => void} Unregister function.
 */
export function registerCleanup(name, fn, syncFn) {
  const id = nextId++;
  tasks.set(id, { name, fn, syncFn });
  return () => tasks.delete(id);
}

/**
 * Creates a private temporary directory that is removed on any exit path.
 * @param {string} [prefix]
 * @returns {Promise<{ path: string, dispose: () => Promise<void> }>}
 */
export async function createTempDir(prefix = 'git-commit-animator-') {
  const dir = await fsp.mkdtemp(path.join(os.tmpdir(), prefix));
  tempDirs.add(dir);
  return {
    path: dir,
    dispose: async () => {
      tempDirs.delete(dir);
      await fsp.rm(dir, { recursive: true, force: true, maxRetries: 3, retryDelay: 100 });
    },
    /** Stops tracking the folder so it survives exit (used by --keep-frames). */
    release: () => {
      tempDirs.delete(dir);
    },
  };
}

/** Runs every registered cleanup task, then removes temp folders. Never throws. */
export async function runCleanup() {
  const pending = [...tasks.values()].reverse();
  tasks.clear();
  for (const task of pending) {
    try {
      await withTimeout(Promise.resolve().then(task.fn), 5000);
    } catch {
      // Best effort: keep tearing down the remaining resources.
    }
  }
  for (const dir of [...tempDirs]) {
    tempDirs.delete(dir);
    try {
      await fsp.rm(dir, { recursive: true, force: true, maxRetries: 3, retryDelay: 100 });
    } catch {
      // Ignore: the OS temp cleaner will eventually reclaim it.
    }
  }
}

function runCleanupSync() {
  for (const task of [...tasks.values()].reverse()) {
    try {
      task.syncFn?.();
    } catch {
      // ignore
    }
  }
  tasks.clear();
  for (const dir of tempDirs) {
    try {
      fs.rmSync(dir, { recursive: true, force: true });
    } catch {
      // ignore
    }
  }
  tempDirs.clear();
}

function withTimeout(promise, ms) {
  let timer;
  return Promise.race([
    promise,
    new Promise((_, reject) => {
      timer = setTimeout(() => reject(new Error('cleanup timeout')), ms);
      timer.unref?.();
    }),
  ]).finally(() => clearTimeout(timer));
}

/**
 * Installs SIGINT/SIGTERM/SIGHUP handlers and an exit hook (idempotent).
 * @param {object} [options]
 * @param {(signal: string) => void} [options.onSignal] Called once when shutdown starts (e.g. to print a message).
 */
export function installSignalHandlers({ onSignal } = {}) {
  if (handlersInstalled) return;
  handlersInstalled = true;

  const handle = (signal) => {
    if (shuttingDown) {
      // Second signal: the user really wants out.
      runCleanupSync();
      process.exit(SIGNAL_EXIT_CODES[signal] ?? 1);
      return;
    }
    shuttingDown = true;
    controller.abort();
    try {
      onSignal?.(signal);
    } catch {
      // ignore
    }
    withTimeout(runCleanup(), CLEANUP_TIMEOUT_MS)
      .catch(() => runCleanupSync())
      .finally(() => process.exit(SIGNAL_EXIT_CODES[signal] ?? 1));
  };

  for (const signal of Object.keys(SIGNAL_EXIT_CODES)) {
    try {
      process.on(signal, () => handle(signal));
    } catch {
      // Some signals are unsupported on some platforms (e.g. SIGHUP on old Windows builds).
    }
  }
  process.on('exit', runCleanupSync);
}
