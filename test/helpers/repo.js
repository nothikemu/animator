import { execFileSync } from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';

/**
 * Creates a throwaway git repository for tests.
 * @returns {{ dir: string, git: (...args: string[]) => string, write: (file: string, content: string | Buffer) => void, commit: (message: string) => string, cleanup: () => void }}
 */
export function createRepo() {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'gca-test-'));
  const git = (...args) => execFileSync('git', args, {
    cwd: dir,
    encoding: 'utf8',
    env: {
      ...process.env,
      GIT_AUTHOR_NAME: 'Test',
      GIT_AUTHOR_EMAIL: 'test@example.com',
      GIT_COMMITTER_NAME: 'Test',
      GIT_COMMITTER_EMAIL: 'test@example.com',
      GIT_CONFIG_NOSYSTEM: '1',
    },
  }).trim();
  git('init', '-q', '-b', 'main');
  git('config', 'commit.gpgsign', 'false');
  return {
    dir,
    git,
    write(file, content) {
      const full = path.join(dir, file);
      fs.mkdirSync(path.dirname(full), { recursive: true });
      fs.writeFileSync(full, content);
    },
    remove(file) {
      fs.rmSync(path.join(dir, file), { force: true });
    },
    commit(message) {
      git('add', '-A');
      git('commit', '-q', '--allow-empty', '-m', message);
      return git('rev-parse', 'HEAD');
    },
    cleanup() {
      fs.rmSync(dir, { recursive: true, force: true });
    },
  };
}
