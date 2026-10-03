#!/usr/bin/env node
import { main } from '../src/cli.js';

const [major, minor] = process.versions.node.split('.').map(Number);
if (major < 22 || (major === 22 && minor < 12)) {
  process.stderr.write(`\n  Git-Commit Animator requires Node.js 22.12 or newer (you have ${process.versions.node}).\n  Download it from https://nodejs.org\n\n`);
  process.exit(1);
}

process.exitCode = await main(process.argv.slice(2));
