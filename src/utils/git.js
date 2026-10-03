/**
 * Git plumbing layer.
 *
 * Talks to the system `git` binary through child_process.spawn with argument
 * arrays (never a shell), so paths and revisions are passed verbatim and
 * cannot be interpreted as shell syntax. Every user-caused failure is mapped
 * to an AnimatorError with an actionable hint.
 */

import { spawn } from 'node:child_process';
import fs from 'node:fs/promises';
import path from 'node:path';
import { AnimatorError } from './errors.js';

/** Environment that makes git non-interactive and its output predictable. */
const GIT_ENV = {
  GIT_TERMINAL_PROMPT: '0',
  GIT_OPTIONAL_LOCKS: '0',
  GIT_PAGER: 'cat',
  PAGER: 'cat',
  LC_ALL: 'C',
  LANGUAGE: 'C',
};

/** Options applied to every invocation, overriding user configuration that would change output formats. */
const GIT_GLOBAL_ARGS = ['--no-pager', '-c', 'core.quotePath=false', '-c', 'color.ui=false', '-c', 'diff.noprefix=false'];

const DEFAULT_MAX_BUFFER = 256 * 1024 * 1024;

/** Files above this size are skipped: typing them out would never be watchable. */
export const DEFAULT_MAX_FILE_BYTES = 1024 * 1024;

/** Lockfiles and generated artifacts that are excluded unless --all-files is given. */
const GENERATED_BASENAMES = new Set([
  'package-lock.json', 'npm-shrinkwrap.json', 'yarn.lock', 'pnpm-lock.yaml', 'bun.lockb', 'bun.lock',
  'cargo.lock', 'gemfile.lock', 'poetry.lock', 'pipfile.lock', 'uv.lock', 'composer.lock', 'go.sum',
  'mix.lock', 'pubspec.lock', 'podfile.lock', 'packages.lock.json', 'flake.lock', 'deno.lock',
]);
const GENERATED_PATTERNS = [/\.min\.(?:js|css|mjs)$/i, /\.map$/i, /(?:^|\/)dist\/.*\.(?:js|css)$/i];

const NULL_SHA_RE = /^0+$/;

/**
 * Runs git and collects its output.
 *
 * @param {string[]} args
 * @param {object} [options]
 * @param {string} [options.cwd]
 * @param {string | Buffer} [options.input] Data written to stdin.
 * @param {'utf8' | 'buffer'} [options.encoding]
 * @param {number} [options.maxBuffer]
 * @returns {Promise<{ code: number, stdout: any, stderr: string }>}
 */
export function runGit(args, { cwd, input, encoding = 'utf8', maxBuffer = DEFAULT_MAX_BUFFER } = {}) {
  return new Promise((resolve, reject) => {
    let settled = false;
    const finish = (fn, value) => {
      if (settled) return;
      settled = true;
      fn(value);
    };

    let child;
    try {
      child = spawn('git', [...GIT_GLOBAL_ARGS, ...args], {
        cwd,
        env: { ...process.env, ...GIT_ENV },
        stdio: [input === undefined ? 'ignore' : 'pipe', 'pipe', 'pipe'],
        windowsHide: true,
      });
    } catch (error) {
      finish(reject, mapSpawnError(error));
      return;
    }

    const out = [];
    const err = [];
    let outBytes = 0;

    child.on('error', (error) => finish(reject, mapSpawnError(error)));
    child.stdout.on('data', (chunk) => {
      outBytes += chunk.length;
      if (outBytes > maxBuffer) {
        child.kill('SIGKILL');
        finish(reject, new AnimatorError(`git produced more than ${Math.round(maxBuffer / 1048576)} MB of output`, {
          code: 'E_GIT_OUTPUT_TOO_LARGE',
          hint: 'Narrow the diff with a pathspec, e.g. `git-commit-animator HEAD~1 HEAD -- src/`.',
        }));
        return;
      }
      out.push(chunk);
    });
    child.stderr.on('data', (chunk) => err.push(chunk));
    child.on('close', (code) => {
      const stdout = Buffer.concat(out);
      finish(resolve, {
        code: code ?? 1,
        stdout: encoding === 'buffer' ? stdout : stdout.toString('utf8'),
        stderr: Buffer.concat(err).toString('utf8').trim(),
      });
    });

    if (input !== undefined) {
      child.stdin.on('error', () => {});
      child.stdin.end(input);
    }
  });
}

function mapSpawnError(error) {
  if (error && error.code === 'ENOENT') {
    return new AnimatorError('Git is not installed or not available on your PATH.', {
      code: 'E_GIT_MISSING',
      hint: 'Install git from https://git-scm.com/downloads and make sure `git --version` works in your terminal.',
      cause: error,
    });
  }
  return new AnimatorError(`Failed to run git: ${error?.message ?? error}`, { code: 'E_GIT_SPAWN', cause: error });
}

/**
 * Runs git and throws a descriptive error on a non-zero exit code.
 * @param {string[]} args
 * @param {Parameters<typeof runGit>[1]} [options]
 */
export async function git(args, options) {
  const result = await runGit(args, options);
  if (result.code !== 0) {
    throw new AnimatorError(`git ${args[0]} failed: ${firstLine(result.stderr) || `exit code ${result.code}`}`, {
      code: 'E_GIT_FAILED',
      details: result.stderr,
    });
  }
  return result.stdout;
}

function firstLine(text) {
  return String(text ?? '').split('\n').find((l) => l.trim())?.replace(/^fatal:\s*/, '') ?? '';
}

/** Verifies that git can be executed and returns its version string. */
export async function getGitVersion() {
  const out = await git(['--version']);
  return out.trim().replace(/^git version\s*/, '');
}

/**
 * Locates the repository containing `repoPath`.
 *
 * @param {string} repoPath
 * @returns {Promise<{ root: string, gitDir: string, bare: boolean, name: string }>}
 */
export async function openRepository(repoPath) {
  const absolute = path.resolve(repoPath);
  let stat;
  try {
    stat = await fs.stat(absolute);
  } catch {
    throw new AnimatorError(`The path "${absolute}" does not exist.`, {
      code: 'E_REPO_NOT_FOUND',
      hint: 'Pass the folder of a git repository with --repo <path>, or run the command inside one.',
    });
  }
  if (!stat.isDirectory()) {
    throw new AnimatorError(`The path "${absolute}" is not a directory.`, {
      code: 'E_REPO_NOT_DIRECTORY',
      hint: 'Point --repo at the repository folder, not at a file inside it.',
    });
  }

  const probe = await runGit(['rev-parse', '--is-bare-repository', '--absolute-git-dir'], { cwd: absolute });
  if (probe.code !== 0) {
    const stderr = probe.stderr;
    if (/dubious ownership/i.test(stderr)) {
      throw new AnimatorError(`Git refuses to read "${absolute}" because it is owned by a different user.`, {
        code: 'E_GIT_UNSAFE_REPO',
        hint: `If you trust this repository, run:\n  git config --global --add safe.directory "${absolute}"`,
        details: stderr,
      });
    }
    if (/not a git repository/i.test(stderr)) {
      throw new AnimatorError(`"${absolute}" is not inside a git repository.`, {
        code: 'E_NOT_A_REPO',
        hint: 'cd into a git repository first, or pass one explicitly: git-commit-animator --repo path/to/repo',
        details: stderr,
      });
    }
    throw new AnimatorError(`Could not open the repository at "${absolute}": ${firstLine(stderr)}`, {
      code: 'E_GIT_FAILED',
      details: stderr,
    });
  }

  const [bareLine, gitDir] = probe.stdout.trim().split('\n');
  const bare = bareLine.trim() === 'true';
  let root = gitDir.trim();
  if (!bare) root = (await git(['rev-parse', '--show-toplevel'], { cwd: absolute })).trim();
  const name = path.basename(bare ? root.replace(/\.git$/i, '') : root) || 'repository';
  return { root: path.resolve(root), gitDir: gitDir.trim(), bare, name };
}

/**
 * Rejects revisions that could be interpreted as command-line options or are
 * otherwise malformed. Revisions are passed to git as separate argv entries,
 * so this is defense in depth against option injection (e.g. "--output=...").
 * @param {string} rev
 * @param {string} label
 */
export function validateRevision(rev, label) {
  if (typeof rev !== 'string' || rev.trim() === '') {
    throw new AnimatorError(`The ${label} revision is empty.`, { code: 'E_BAD_REVISION', exitCode: 2 });
  }
  if (rev.startsWith('-') || /[\0\n\r]/.test(rev)) {
    throw new AnimatorError(`"${rev}" is not a valid ${label} revision.`, {
      code: 'E_BAD_REVISION',
      hint: 'Use a commit hash, branch, tag or expression such as HEAD~2.',
      exitCode: 2,
    });
  }
}

async function assertHasCommits(repo) {
  const head = await runGit(['rev-parse', '--verify', '--quiet', 'HEAD^{commit}'], { cwd: repo.root });
  if (head.code === 0) return;
  const any = await runGit(['rev-list', '-n', '1', '--all'], { cwd: repo.root });
  if (any.code === 0 && any.stdout.trim() === '') {
    throw new AnimatorError('This repository has no commits yet.', {
      code: 'E_NO_COMMITS',
      hint: 'Create at least one commit (git add . && git commit -m "initial") and run the animator again.',
    });
  }
}

/**
 * Resolves a revision to a commit with metadata.
 *
 * @param {{ root: string }} repo
 * @param {string} rev
 * @param {string} label "base" or "target", used in error messages.
 */
export async function resolveCommit(repo, rev, label) {
  validateRevision(rev, label);
  const verify = await runGit(['rev-parse', '--verify', '--quiet', `${rev}^{commit}`], { cwd: repo.root });
  if (verify.code !== 0 || !verify.stdout.trim()) {
    await assertHasCommits(repo);
    const isHeadParent = /^HEAD(?:~\d*|\^+\d*)+$/.test(rev);
    throw new AnimatorError(`The ${label} revision "${rev}" does not exist in this repository.`, {
      code: 'E_BAD_REVISION',
      hint: isHeadParent
        ? 'The branch does not have that many commits. Run `git log --oneline` to pick a valid commit.'
        : 'Check the hash or ref name. Run `git log --oneline -n 15` to list recent commits.',
      exitCode: 2,
    });
  }
  const hash = verify.stdout.trim();
  const info = await git(['log', '-1', '--no-show-signature', '--format=%H%x00%h%x00%P%x00%an%x00%aI%x00%s', hash], { cwd: repo.root });
  const [full, short, parents, author, date, subject] = info.replace(/\n$/, '').split('\0');
  return {
    hash: full,
    shortHash: short,
    parents: parents ? parents.split(' ').filter(Boolean) : [],
    author,
    date,
    subject: subject ?? '',
    isEmptyTree: false,
  };
}

/**
 * Hash of the empty tree for this repository's object format (SHA-1 or SHA-256).
 * @param {{ root: string }} repo
 */
export async function emptyTree(repo) {
  const out = await git(['hash-object', '-t', 'tree', '--stdin'], { cwd: repo.root, input: '' });
  const hash = out.trim();
  return { hash, shortHash: hash.slice(0, 7), parents: [], author: '', date: '', subject: '(empty tree)', isEmptyTree: true };
}

/**
 * Resolves the base and target commits, applying smart defaults:
 * target defaults to HEAD and base to the first parent of target (or the
 * empty tree when target is a root commit). With `symmetric` (A...B), the
 * base becomes the merge base of the two revisions, like `git diff A...B`.
 *
 * @param {{ root: string }} repo
 * @param {{ base?: string | null, target?: string | null, symmetric?: boolean }} range
 */
export async function resolveRange(repo, { base, target, symmetric = false } = {}) {
  await assertHasCommits(repo);
  const targetCommit = await resolveCommit(repo, target || 'HEAD', 'target');
  let baseCommit;
  if (base && symmetric) {
    const other = await resolveCommit(repo, base, 'base');
    const mb = await runGit(['merge-base', other.hash, targetCommit.hash], { cwd: repo.root });
    if (mb.code !== 0 || !mb.stdout.trim()) {
      throw new AnimatorError(`"${base}" and "${target || 'HEAD'}" have no common ancestor.`, {
        code: 'E_NO_MERGE_BASE',
        hint: 'Use a two-dot range (A..B) or pass the two revisions separately.',
        exitCode: 2,
      });
    }
    baseCommit = await resolveCommit(repo, mb.stdout.trim(), 'base');
  } else if (base) baseCommit = await resolveCommit(repo, base, 'base');
  else if (targetCommit.parents.length) {
    try {
      baseCommit = await resolveCommit(repo, targetCommit.parents[0], 'base');
    } catch (error) {
      throw (await isShallowBoundary(repo, targetCommit.hash, true)) ? shallowCloneError(targetCommit) : error;
    }
  } else if (await isShallowBoundary(repo, targetCommit.hash)) {
    // In a shallow clone the oldest fetched commit *looks* parentless. Diffing
    // it against the empty tree would silently animate the whole repository.
    throw shallowCloneError(targetCommit);
  } else baseCommit = await emptyTree(repo);
  return { base: baseCommit, target: targetCommit };
}

/**
 * True when the repository is shallow and `hash` sits on the shallow
 * boundary (its real parents were not fetched).
 */
async function isShallowBoundary(repo, hash, anyShallow = false) {
  const res = await runGit(['rev-parse', '--is-shallow-repository', '--git-path', 'shallow'], { cwd: repo.root });
  if (res.code !== 0) return false;
  const [flag, shallowFile] = res.stdout.trim().split('\n');
  if (flag !== 'true') return false;
  if (anyShallow) return true;
  try {
    const list = await fs.readFile(path.resolve(repo.root, shallowFile), 'utf8');
    return list.split('\n').some((line) => line.trim() === hash);
  } catch {
    return false;
  }
}

function shallowCloneError(target) {
  return new AnimatorError(`The parent of ${target.shortHash} is not available because this is a shallow clone.`, {
    code: 'E_SHALLOW_CLONE',
    hint: 'Fetch one more commit of history:\n  git fetch --deepen=1\nIn GitHub Actions, use actions/checkout with `fetch-depth: 2`.',
    exitCode: 2,
  });
}

/**
 * Current branch name, or null for a detached HEAD.
 * @param {{ root: string }} repo
 */
export async function currentBranch(repo) {
  const res = await runGit(['symbolic-ref', '--quiet', '--short', 'HEAD'], { cwd: repo.root });
  return res.code === 0 ? res.stdout.trim() || null : null;
}

/**
 * Parses `git diff --raw -z` output.
 * @param {string} raw
 */
export function parseRawDiff(raw) {
  const tokens = raw.split('\0');
  const entries = [];
  for (let i = 0; i < tokens.length; i++) {
    const header = tokens[i];
    if (!header.startsWith(':')) continue;
    const [oldMode, newMode, oldSha, newSha, status] = header.slice(1).split(' ');
    const letter = status[0];
    const similarity = status.length > 1 ? Number(status.slice(1)) : null;
    const first = tokens[++i];
    const oldPath = first;
    let newPath = first;
    if (letter === 'R' || letter === 'C') newPath = tokens[++i];
    entries.push({ status: letter, similarity, oldMode, newMode, oldSha, newSha, oldPath, newPath });
  }
  return entries;
}

/**
 * Parses `git diff --numstat -z` output. Binary files report "-" counts.
 * @param {string} raw
 */
export function parseNumstat(raw) {
  const tokens = raw.split('\0');
  const entries = [];
  for (let i = 0; i < tokens.length; i++) {
    const record = tokens[i];
    if (!record) continue;
    const m = /^(-|\d+)\t(-|\d+)\t(.*)$/s.exec(record);
    if (!m) continue;
    let filePath = m[3];
    if (filePath === '') {
      // Rename/copy: the two paths follow as separate NUL-terminated fields.
      i += 2;
      filePath = tokens[i];
    }
    entries.push({
      path: filePath,
      binary: m[1] === '-' || m[2] === '-',
      additions: m[1] === '-' ? 0 : Number(m[1]),
      deletions: m[2] === '-' ? 0 : Number(m[2]),
    });
  }
  return entries;
}

/**
 * Parses unified diff hunks. Lines are classified as '+', '-' or ' '.
 * Hunk boundaries are tracked by line counts, so content that happens to look
 * like a diff header is never misinterpreted.
 * @param {string} text
 */
export function parseUnifiedDiff(text) {
  const hunks = [];
  let current = null;
  let oldLeft = 0;
  let newLeft = 0;
  let binary = false;

  for (const rawLine of text.split('\n')) {
    const line = rawLine.endsWith('\r') ? rawLine.slice(0, -1) : rawLine;
    if (current && (oldLeft > 0 || newLeft > 0)) {
      const sign = line[0];
      if (sign === '\\') continue;
      if (sign === '-' && oldLeft > 0) {
        current.lines.push({ type: '-', text: line.slice(1) });
        oldLeft--;
        continue;
      }
      if (sign === '+' && newLeft > 0) {
        current.lines.push({ type: '+', text: line.slice(1) });
        newLeft--;
        continue;
      }
      if ((sign === ' ' || line === '') && oldLeft > 0 && newLeft > 0) {
        current.lines.push({ type: ' ', text: line.slice(1) });
        oldLeft--;
        newLeft--;
        continue;
      }
    }
    const m = /^@@+ -(\d+)(?:,(\d+))? \+(\d+)(?:,(\d+))? @@/.exec(line);
    if (m) {
      current = {
        oldStart: Number(m[1]),
        oldLines: m[2] === undefined ? 1 : Number(m[2]),
        newStart: Number(m[3]),
        newLines: m[4] === undefined ? 1 : Number(m[4]),
        lines: [],
      };
      oldLeft = current.oldLines;
      newLeft = current.newLines;
      hunks.push(current);
      continue;
    }
    if (/^Binary files .* differ$/.test(line) || line.startsWith('GIT binary patch')) binary = true;
  }
  return { hunks, binary };
}

const strictUtf8 = new TextDecoder('utf-8', { fatal: true });

/**
 * True when a buffer looks binary. Starts with git's heuristic (a NUL byte in
 * the first 8 KB), then also rejects content that is not valid UTF-8 and is
 * dominated by control or high-bit bytes: git happily diffs such files as
 * text, but typing them out would render as mojibake. Legacy single-byte
 * encoded text (a few accented characters) still passes.
 */
export function isBinaryBuffer(buffer) {
  const limit = Math.min(buffer.length, 8000);
  let control = 0;
  let high = 0;
  for (let i = 0; i < limit; i++) {
    const b = buffer[i];
    if (b === 0) return true;
    if ((b < 0x20 && b !== 0x09 && b !== 0x0a && b !== 0x0d && b !== 0x0c && b !== 0x1b) || b === 0x7f) control++;
    else if (b >= 0x80) high++;
  }
  if (limit === 0) return false;
  try {
    strictUtf8.decode(buffer.subarray(0, Math.min(buffer.length, 64 * 1024)));
    return control / limit > 0.1;
  } catch {
    // A multi-byte sequence may be cut at the 64 KB boundary; judge by byte statistics instead.
    return control / limit > 0.02 || high / limit > 0.3;
  }
}

/** Decodes a blob as UTF-8 text with LF line endings and no BOM. */
export function decodeText(buffer) {
  let text = buffer.toString('utf8');
  if (text.charCodeAt(0) === 0xfeff) text = text.slice(1);
  // CRLF becomes LF; a lone CR is dropped (git does not treat it as a line break either).
  return text.includes('\r') ? text.replace(/\r\n/g, '\n').replace(/\r/g, '') : text;
}

/**
 * Reads several blobs with a single `git cat-file --batch` process.
 * @param {{ root: string }} repo
 * @param {string[]} shas
 * @returns {Promise<Map<string, Buffer>>}
 */
export async function readBlobs(repo, shas) {
  const unique = [...new Set(shas.filter((s) => s && !NULL_SHA_RE.test(s)))];
  const blobs = new Map();
  if (!unique.length) return blobs;
  const { code, stdout, stderr } = await runGit(['cat-file', '--batch'], {
    cwd: repo.root,
    input: `${unique.join('\n')}\n`,
    encoding: 'buffer',
  });
  if (code !== 0) {
    throw new AnimatorError(`git cat-file failed: ${firstLine(stderr)}`, { code: 'E_GIT_FAILED', details: stderr });
  }
  let offset = 0;
  while (offset < stdout.length) {
    const headerEnd = stdout.indexOf(0x0a, offset);
    if (headerEnd < 0) break;
    const header = stdout.toString('utf8', offset, headerEnd);
    const [sha, type, sizeText] = header.split(' ');
    if (type === 'missing' || sizeText === undefined) {
      offset = headerEnd + 1;
      continue;
    }
    const size = Number(sizeText);
    const start = headerEnd + 1;
    blobs.set(sha, stdout.subarray(start, start + size));
    offset = start + size + 1;
  }
  return blobs;
}

/** True for lockfiles, minified bundles and source maps. */
export function isGeneratedFile(filePath) {
  const lower = filePath.toLowerCase();
  const base = lower.slice(lower.lastIndexOf('/') + 1);
  return GENERATED_BASENAMES.has(base) || GENERATED_PATTERNS.some((re) => re.test(lower));
}

/**
 * Collects everything the animation needs from the repository: the commit
 * range, the list of changed files and, for each selected file, its old/new
 * contents and diff hunks.
 *
 * @param {object} options
 * @param {string} options.repoPath
 * @param {string | null} [options.base]
 * @param {string | null} [options.target]
 * @param {boolean} [options.symmetric] Treat base...target like `git diff A...B`.
 * @param {string[]} [options.pathspec]
 * @param {number} [options.maxFiles]
 * @param {boolean} [options.includeGenerated]
 * @param {number} [options.maxFileBytes]
 */
export async function collectDiff({
  repoPath,
  base = null,
  target = null,
  symmetric = false,
  pathspec = [],
  maxFiles = Infinity,
  includeGenerated = false,
  maxFileBytes = DEFAULT_MAX_FILE_BYTES,
}) {
  const repo = await openRepository(repoPath);
  const range = await resolveRange(repo, { base, target, symmetric });
  const branch = repo.bare ? null : await currentBranch(repo);
  const cwd = repo.root;

  const diffArgs = ['--no-ext-diff', '--no-textconv', '-M', range.base.hash, range.target.hash, '--', ...pathspec];
  const [raw, numstat] = await Promise.all([
    git(['diff', '--raw', '-z', '--no-abbrev', ...diffArgs], { cwd }),
    git(['diff', '--numstat', '-z', ...diffArgs], { cwd }),
  ]);
  const entries = parseRawDiff(raw);
  const stats = parseNumstat(numstat);
  const statsByPath = new Map(stats.map((s) => [s.path, s]));

  const skipped = [];
  const candidates = [];
  entries.forEach((entry, i) => {
    const displayPath = entry.status === 'D' ? entry.oldPath : entry.newPath;
    const stat = statsByPath.get(displayPath) ?? stats[i] ?? { binary: false, additions: 0, deletions: 0 };
    const file = { ...entry, path: displayPath, additions: stat.additions, deletions: stat.deletions, binary: stat.binary };
    if (entry.oldMode === '160000' || entry.newMode === '160000') skipped.push({ path: displayPath, reason: 'submodule' });
    else if (stat.binary) skipped.push({ path: displayPath, reason: 'binary file' });
    else if (!includeGenerated && isGeneratedFile(displayPath)) skipped.push({ path: displayPath, reason: 'lockfile / generated' });
    else if (entry.oldSha === entry.newSha) skipped.push({ path: displayPath, reason: 'no content change' });
    else candidates.push(file);
  });

  // Keep the most substantial changes when there are too many files, but
  // present them in the repository's natural path order.
  let selected = candidates;
  if (candidates.length > maxFiles) {
    const ranked = [...candidates].sort((a, b) => (b.additions + b.deletions * 0.3) - (a.additions + a.deletions * 0.3));
    const keep = new Set(ranked.slice(0, maxFiles));
    selected = candidates.filter((c) => keep.has(c));
    for (const c of candidates) if (!keep.has(c)) skipped.push({ path: c.path, reason: `over --max-files ${maxFiles}` });
  }

  // Check blob sizes before loading contents.
  const sizes = await blobSizes(repo, selected.flatMap((f) => [f.oldSha, f.newSha]));
  const sized = selected.filter((f) => {
    const biggest = Math.max(sizes.get(f.oldSha) ?? 0, sizes.get(f.newSha) ?? 0);
    if (biggest > maxFileBytes) {
      skipped.push({ path: f.path, reason: `larger than ${Math.round(maxFileBytes / 1024)} KB` });
      return false;
    }
    return true;
  });

  const blobs = await readBlobs(repo, sized.flatMap((f) => [f.oldSha, f.newSha]));
  const files = [];
  for (const f of sized) {
    const oldBuf = NULL_SHA_RE.test(f.oldSha) ? Buffer.alloc(0) : blobs.get(f.oldSha) ?? Buffer.alloc(0);
    const newBuf = NULL_SHA_RE.test(f.newSha) ? Buffer.alloc(0) : blobs.get(f.newSha) ?? Buffer.alloc(0);
    if (isBinaryBuffer(oldBuf) || isBinaryBuffer(newBuf)) {
      skipped.push({ path: f.path, reason: 'binary file' });
      continue;
    }
    const oldText = decodeText(oldBuf);
    const newText = decodeText(newBuf);
    const hunks = await diffTexts(repo, f, oldText, newText);
    if (!hunks.length) {
      skipped.push({ path: f.path, reason: 'whitespace / line-ending change only' });
      continue;
    }
    files.push({
      path: f.path,
      oldPath: f.oldPath,
      status: f.status,
      similarity: f.similarity,
      oldText,
      newText,
      hunks,
      additions: hunks.reduce((n, h) => n + h.newLines, 0),
      deletions: hunks.reduce((n, h) => n + h.oldLines, 0),
    });
  }

  return { repo, branch, base: range.base, target: range.target, files, skipped };
}

async function blobSizes(repo, shas) {
  const unique = [...new Set(shas.filter((s) => s && !NULL_SHA_RE.test(s)))];
  const sizes = new Map();
  if (!unique.length) return sizes;
  const out = await git(['cat-file', '--batch-check=%(objectname) %(objectsize)'], { cwd: repo.root, input: `${unique.join('\n')}\n` });
  for (const line of out.split('\n')) {
    const [sha, size] = line.split(' ');
    if (sha && size && /^\d+$/.test(size)) sizes.set(sha, Number(size));
  }
  return sizes;
}

/**
 * Produces zero-context hunks for one file. Added and deleted files are
 * synthesized directly; modified files are diffed blob-to-blob by git with
 * the histogram algorithm, which yields the most human-looking edits.
 */
async function diffTexts(repo, file, oldText, newText) {
  const oldCount = countLines(oldText);
  const newCount = countLines(newText);
  if (NULL_SHA_RE.test(file.oldSha) || oldCount === 0) {
    return newCount ? [{ oldStart: 0, oldLines: 0, newStart: 1, newLines: newCount, lines: [] }] : [];
  }
  if (NULL_SHA_RE.test(file.newSha) || newCount === 0) {
    return oldCount ? [{ oldStart: 1, oldLines: oldCount, newStart: 0, newLines: 0, lines: [] }] : [];
  }
  const out = await git([
    'diff', '-U0', '--no-color', '--no-ext-diff', '--no-textconv', '--diff-algorithm=histogram',
    '--ignore-cr-at-eol', file.oldSha, file.newSha,
  ], { cwd: repo.root });
  const { hunks } = parseUnifiedDiff(out);
  return hunks;
}

function countLines(text) {
  if (!text) return 0;
  let n = 0;
  for (let i = 0; i < text.length; i++) if (text.charCodeAt(i) === 10) n++;
  return text.endsWith('\n') ? n : n + 1;
}
