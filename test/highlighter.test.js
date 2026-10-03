import assert from 'node:assert/strict';
import { describe, it } from 'node:test';
import { detectLanguage, supportedLanguages, tokenize, TOKEN_CLASSES } from '../src/engines/highlighter.js';

const SAMPLES = {
  javascript: "import fs from 'node:fs';\n// c\nconst re = /a[/]b+/gi, x = a / b;\nexport async function main() {\n  return console.log(`hi ${x}`, obj.prop, new Foo());\n}\n",
  typescript: 'interface User { id: number; name?: string }\nconst u: User = { id: 1 } satisfies User;\n',
  python: '@dataclass\nclass P(Base):\n    """doc\n    string"""\n    def f(self, x: int) -> str:\n        return f"{x}" + r\'\\d\'  # c\n',
  rust: "#[derive(Debug)]\nfn longest<'a>(x: &'a str) -> &'a str { let c = 'x'; println!(\"{}\", x); x }\n",
  go: 'package main\n\nfunc main() {\n\ts := `raw\nstring`\n\tfmt.Println(s, nil)\n}\n',
  shell: '#!/usr/bin/env bash\nset -euo pipefail\nif [ -f "$HOME/.rc" ]; then echo ${VAR} | grep --color x # note\nfi\n',
  yaml: 'name: CI\non:\n  push:\n    branches: [main]\nsteps:\n  - run: |\n      npm ci\n      npm test\n  enabled: true # yes\n',
  css: '.btn:hover, a > span { color: #fff; margin: 0 4px !important; }\n@media (max-width: 600px) { .x { --gap: 2rem; } }\n',
  markup: '<!doctype html>\n<div class="a" id=\'b\'>Hi &amp; bye<!-- c --></div>\n<script>const x = 1;</script>\n<style>p { color: red }</style>\n',
  markdown: '# Title\nSome `code`, **bold** and [a link](https://x.y).\n```js\nconst a = 1;\n```\n- item\n',
  json: '{\n  "name": "x",\n  "n": -1.5e3,\n  "ok": true\n}\n',
  makefile: 'CC := gcc\nall: main.o\n\t$(CC) -o app $@ # build\n',
  c: '#include <stdio.h>\nint main(void) { printf("%d\\n", 42); return 0; }\n',
  toml: '[package]\nname = "x" # n\nversion = 1\n',
  sql: "SELECT id, name FROM users WHERE email = 'a@b.c' -- note\nORDER BY id DESC;\n",
  plaintext: 'just some words\nand more\n',
};

const text = (lines) => lines.map((line) => line.map((t) => t[1]).join('')).join('\n');
const find = (lines, cls, value) => lines.flat().some(([c, t]) => c === cls && t === value);

describe('tokenize', () => {
  for (const [lang, source] of Object.entries(SAMPLES)) {
    it(`round-trips ${lang} source exactly`, () => {
      const lines = tokenize(source, lang);
      assert.equal(text(lines), source);
      assert.equal(lines.length, source.split('\n').length);
      for (const [cls] of lines.flat()) assert.ok(cls === '' || TOKEN_CLASSES.includes(cls), `unknown class ${cls}`);
    });
  }

  it('never loses characters on adversarial input', () => {
    const nasty = ['"unterminated', "'", '/* open', '`', '<div attr="x', '#', '${', '\\', '"""', '\u{1F680}\u200d', '\t\r'];
    let seed = 7;
    const rand = () => {
      seed = (seed * 1103515245 + 12345) % 2 ** 31;
      return seed / 2 ** 31;
    };
    for (const lang of supportedLanguages()) {
      for (let i = 0; i < 20; i++) {
        let s = '';
        for (let k = 0; k < 30; k++) s += rand() < 0.3 ? '\n' : nasty[Math.floor(rand() * nasty.length)];
        assert.equal(text(tokenize(s, lang)), s, `${lang} lost characters`);
      }
    }
  });

  it('classifies common JavaScript constructs', () => {
    const lines = tokenize(SAMPLES.javascript, 'javascript');
    assert.ok(find(lines, 'kw', 'import'));
    assert.ok(find(lines, 'str', "'node:fs'"));
    assert.ok(find(lines, 'com', '// c'));
    assert.ok(find(lines, 'regex', '/a[/]b+/gi'), 'regex with slash in class');
    assert.ok(find(lines, 'fn', 'main'));
    assert.ok(find(lines, 'prop', 'prop'));
    assert.ok(find(lines, 'type', 'Foo'), 'constructor after new');
    assert.ok(!lines.flat().some(([c, t]) => c === 'regex' && t.includes('/ b')), 'division is not a regex');
  });

  it('handles multi-line strings and comments across lines', () => {
    const py = tokenize(SAMPLES.python, 'python');
    assert.deepEqual(py[2].at(-1), ['str', '"""doc']);
    assert.deepEqual(py[3], [['str', '    string"""']]);
    const go = tokenize(SAMPLES.go, 'go');
    assert.ok(go[4].some(([c]) => c === 'str'));
  });

  it('distinguishes Rust lifetimes from char literals', () => {
    const lines = tokenize(SAMPLES.rust, 'rust');
    assert.ok(find(lines, 'deco', "'a"));
    assert.ok(find(lines, 'str', "'x'"));
    assert.ok(find(lines, 'fn', 'println!'));
    assert.ok(find(lines, 'deco', '#[derive(Debug)]'));
  });

  it('marks JSON keys and YAML keys as properties', () => {
    assert.ok(find(tokenize(SAMPLES.json, 'json'), 'prop', '"name"'));
    const yaml = tokenize(SAMPLES.yaml, 'yaml');
    assert.ok(find(yaml, 'prop', 'branches'));
    assert.ok(find(yaml, 'str', 'npm ci'), 'block scalar content');
    assert.ok(find(yaml, 'const', 'true'));
  });

  it('highlights embedded script blocks in HTML', () => {
    const lines = tokenize(SAMPLES.markup, 'markup');
    assert.ok(find(lines, 'tag', 'div'));
    assert.ok(find(lines, 'attr', 'class'));
    assert.ok(find(lines, 'kw', 'const'));
    assert.ok(find(lines, 'prop', 'color'));
  });
});

describe('detectLanguage', () => {
  const cases = {
    'src/index.ts': 'typescript',
    'a/b/App.jsx': 'javascript',
    'main.py': 'python',
    'Dockerfile': 'dockerfile',
    'docker/Dockerfile.prod': 'dockerfile',
    'Makefile': 'makefile',
    'README.md': 'markdown',
    '.github/workflows/ci.yml': 'yaml',
    'Cargo.toml': 'toml',
    'styles.scss': 'scss',
    '.env.local': 'ini',
    'unknown.xyz': 'plaintext',
    'C:\\repo\\lib.rs': 'rust',
  };
  for (const [file, id] of Object.entries(cases)) {
    it(`${file} → ${id}`, () => assert.equal(detectLanguage(file).id, id));
  }
});
