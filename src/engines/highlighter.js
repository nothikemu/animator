/**
 * Zero-dependency syntax highlighter.
 *
 * The renderer needs per-line token streams that stay stable while a line is
 * only partially typed, so we tokenize the *final* file contents once and let
 * the renderer slice those tokens to the visible character count. That keeps
 * colors from flickering mid-keystroke and moves all lexing out of the hot
 * frame loop.
 *
 * Output format: an array with one entry per line (split on "\n"); each entry
 * is an array of `[className, text]` pairs. `className` is one of
 * TOKEN_CLASSES or '' for plain text. Adjacent tokens of the same class are
 * merged to keep payloads small.
 *
 * Scanners are deliberately pragmatic: they are linear-time, never throw on
 * malformed input, and degrade to plain text rather than mis-coloring large
 * regions.
 */

import path from 'node:path';

/** Token classes understood by the renderer stylesheet. */
export const TOKEN_CLASSES = Object.freeze([
  'kw', 'str', 'num', 'com', 'fn', 'type', 'const', 'op', 'punc',
  'prop', 'tag', 'attr', 'var', 'deco', 'regex',
]);

const words = (list) => new Set(list.split(/\s+/).filter(Boolean));

const IDENT_RE = /[A-Za-z_$À-￿][\w$À-￿]*/y;
const IDENT_NO_DOLLAR_RE = /[A-Za-z_À-￿][\wÀ-￿]*/y;
const SHELL_WORD_RE = /[A-Za-z_][\w.\-]*/y;
const NUMBER_RE = /(?:0[xX][\da-fA-F][\da-fA-F_]*|0[bB][01][01_]*|0[oO][0-7][0-7_]*|(?:\d[\d_]*(?:\.\d[\d_]*)?|\.\d[\d_]*)(?:[eE][+-]?\d[\d_]*)?)(?:[a-zA-Z_]\w*)?/y;
const OPERATOR_RE = /[+\-*/%=&|^!<>?:~\\]+/y;
const PUNCT = new Set(['(', ')', '[', ']', '{', '}', ';', ',', '.']);
const ALL_CAPS_RE = /^[A-Z][A-Z0-9_]+$/;
const PASCAL_RE = /^[A-Z][a-z0-9]\w*$/;

/** Keywords after which a `/` starts a regular expression literal (JS/TS). */
const REGEX_AFTER_WORDS = words('return typeof instanceof in of new delete void throw case do else yield await');
const TYPE_INTRODUCERS = words('class interface struct enum trait impl type extends implements new record union typealias protocol extension object');

// ---------------------------------------------------------------------------
// Language definitions
// ---------------------------------------------------------------------------

const C_STRINGS = [{ open: '"', close: '"' }, { open: "'", close: "'" }];

const JS_KEYWORDS = 'as async await break case catch class const continue debugger default delete do else export extends finally for from function get if import in instanceof let new of return set static super switch this throw try typeof var void while with yield';
const JS_TYPES = 'Array ArrayBuffer Boolean Date Error Function JSON Map Math Number Object Promise Proxy Reflect RegExp Set String Symbol WeakMap WeakSet BigInt Intl console window document globalThis process require module exports Buffer';

/** @type {Record<string, any>} */
const LANGUAGES = {
  plaintext: { name: 'Plain Text', scanner: 'plain' },

  javascript: {
    name: 'JavaScript',
    scanner: 'code',
    lineComments: ['//'],
    blockComments: [['/*', '*/']],
    strings: [{ open: '`', close: '`', multiline: true }, ...C_STRINGS],
    keywords: words(JS_KEYWORDS),
    constants: words('true false null undefined NaN Infinity'),
    types: words(JS_TYPES),
    regex: true,
    decorators: true,
    pascalTypes: true,
    memberProps: true,
  },

  typescript: {
    name: 'TypeScript',
    scanner: 'code',
    lineComments: ['//'],
    blockComments: [['/*', '*/']],
    strings: [{ open: '`', close: '`', multiline: true }, ...C_STRINGS],
    keywords: words(`${JS_KEYWORDS} interface type enum implements declare abstract private protected public readonly namespace module keyof infer is asserts satisfies override unique accessor`),
    constants: words('true false null undefined NaN Infinity'),
    types: words(`${JS_TYPES} string number boolean any unknown never object symbol bigint Record Partial Required Readonly Pick Omit ReturnType`),
    regex: true,
    decorators: true,
    pascalTypes: true,
    memberProps: true,
  },

  python: {
    name: 'Python',
    scanner: 'code',
    lineComments: ['#'],
    strings: [
      { open: '"""', close: '"""', multiline: true },
      { open: "'''", close: "'''", multiline: true },
      ...C_STRINGS,
    ],
    stringPrefixes: words('r u b f br rb fr rf'),
    keywords: words('and as assert async await break class continue def del elif else except finally for from global if import in is lambda nonlocal not or pass raise return try while with yield match case'),
    constants: words('True False None NotImplemented Ellipsis __name__ __file__'),
    types: words('int float str bool bytes list dict set frozenset tuple object type complex range Exception ValueError TypeError KeyError'),
    variables: words('self cls'),
    decorators: true,
    pascalTypes: true,
    memberProps: true,
  },

  ruby: {
    name: 'Ruby',
    scanner: 'code',
    lineComments: ['#'],
    strings: C_STRINGS,
    keywords: words('BEGIN END alias and begin break case class def defined? do else elsif end ensure for if in module next not or redo rescue retry return super then undef unless until when while yield require require_relative attr_accessor attr_reader attr_writer private protected public raise lambda proc loop include extend'),
    constants: words('true false nil'),
    variables: words('self'),
    sigils: { '@': 'var', $: 'var' },
    symbols: true,
    pascalTypes: true,
    memberProps: true,
  },

  go: {
    name: 'Go',
    scanner: 'code',
    lineComments: ['//'],
    blockComments: [['/*', '*/']],
    strings: [{ open: '`', close: '`', multiline: true, escape: false }, ...C_STRINGS],
    keywords: words('break case chan const continue default defer else fallthrough for func go goto if import interface map package range return select struct switch type var'),
    constants: words('true false nil iota'),
    types: words('bool byte complex64 complex128 error float32 float64 int int8 int16 int32 int64 rune string uint uint8 uint16 uint32 uint64 uintptr any comparable'),
    pascalTypes: true,
    memberProps: true,
  },

  rust: {
    name: 'Rust',
    scanner: 'code',
    lineComments: ['//'],
    blockComments: [['/*', '*/']],
    strings: [{ open: '"', close: '"', multiline: true }, { open: "'", close: "'", charLiteral: true }],
    stringPrefixes: words('b r br'),
    keywords: words('as async await break const continue crate dyn else enum extern fn for if impl in let loop match mod move mut pub ref return self static struct super trait type unsafe use where while yield macro_rules'),
    constants: words('true false'),
    types: words('i8 i16 i32 i64 i128 isize u8 u16 u32 u64 u128 usize f32 f64 bool char str String Vec Option Result Box Self'),
    macros: true,
    rustAttributes: true,
    pascalTypes: true,
    memberProps: true,
  },

  java: {
    name: 'Java',
    scanner: 'code',
    lineComments: ['//'],
    blockComments: [['/*', '*/']],
    strings: [{ open: '"""', close: '"""', multiline: true }, ...C_STRINGS],
    keywords: words('abstract assert break case catch class const continue default do else enum extends final finally for goto if implements import instanceof interface native new package private protected public return static strictfp super switch synchronized this throw throws transient try volatile while var record sealed permits yield'),
    constants: words('true false null'),
    types: words('boolean byte char double float int long short void String Object Integer Long Double Boolean List Map Set Optional'),
    decorators: true,
    pascalTypes: true,
    memberProps: true,
  },

  kotlin: {
    name: 'Kotlin',
    scanner: 'code',
    lineComments: ['//'],
    blockComments: [['/*', '*/']],
    strings: [{ open: '"""', close: '"""', multiline: true }, ...C_STRINGS],
    keywords: words('as break class continue do else for fun if in interface is object package return super this throw try typealias typeof val var when while by catch constructor finally get import init set where abstract annotation companion const data enum expect external final infix inline inner internal lateinit noinline open operator out override private protected public reified sealed suspend tailrec vararg'),
    constants: words('true false null'),
    types: words('Int Long Short Byte Double Float Boolean Char String Unit Any Nothing List Map Set Array'),
    decorators: true,
    pascalTypes: true,
    memberProps: true,
  },

  swift: {
    name: 'Swift',
    scanner: 'code',
    lineComments: ['//'],
    blockComments: [['/*', '*/']],
    strings: [{ open: '"""', close: '"""', multiline: true }, { open: '"', close: '"' }],
    keywords: words('associatedtype class deinit enum extension fileprivate func import init inout internal let open operator private protocol public rethrows static struct subscript typealias var break case continue default defer do else fallthrough for guard if in repeat return switch where while as catch is super self Self throw throws try async await actor some any'),
    constants: words('true false nil'),
    types: words('Int Double Float Bool String Character Array Dictionary Set Optional Any AnyObject Void'),
    decorators: true,
    pascalTypes: true,
    memberProps: true,
  },

  c: {
    name: 'C',
    scanner: 'code',
    lineComments: ['//'],
    blockComments: [['/*', '*/']],
    strings: C_STRINGS,
    keywords: words('auto break case const continue default do else enum extern for goto if inline register restrict return sizeof static struct switch typedef union volatile while'),
    constants: words('NULL true false'),
    types: words('char double float int long short signed unsigned void bool _Bool size_t ssize_t uint8_t uint16_t uint32_t uint64_t int8_t int16_t int32_t int64_t FILE'),
    preprocessor: true,
    memberProps: true,
  },

  cpp: {
    name: 'C++',
    scanner: 'code',
    lineComments: ['//'],
    blockComments: [['/*', '*/']],
    strings: C_STRINGS,
    keywords: words('alignas alignof asm auto break case catch class concept consteval constexpr constinit const const_cast continue co_await co_return co_yield decltype default delete do dynamic_cast else enum explicit export extern for friend goto if inline mutable namespace new noexcept operator private protected public register reinterpret_cast requires return sizeof static static_assert static_cast struct switch template this thread_local throw try typedef typeid typename union using virtual volatile while override final'),
    constants: words('true false nullptr NULL'),
    types: words('bool char char8_t char16_t char32_t double float int long short signed unsigned void wchar_t size_t std string vector map set unique_ptr shared_ptr optional'),
    preprocessor: true,
    pascalTypes: true,
    memberProps: true,
  },

  csharp: {
    name: 'C#',
    scanner: 'code',
    lineComments: ['//'],
    blockComments: [['/*', '*/']],
    strings: [
      { open: '$@"', close: '"', multiline: true, escape: false },
      { open: '@$"', close: '"', multiline: true, escape: false },
      { open: '@"', close: '"', multiline: true, escape: false },
      { open: '$"', close: '"' },
      ...C_STRINGS,
    ],
    keywords: words('abstract as base break case catch checked class const continue default delegate do else enum event explicit extern finally fixed for foreach goto if implicit in interface internal is lock namespace new operator out override params private protected public readonly ref return sealed sizeof stackalloc static struct switch this throw try typeof unchecked unsafe using virtual volatile while var async await dynamic get set value yield record init required global partial where when nameof'),
    constants: words('true false null'),
    types: words('bool byte char decimal double float int long object sbyte short string uint ulong ushort void Task List Dictionary IEnumerable'),
    preprocessor: true,
    pascalTypes: true,
    memberProps: true,
  },

  php: {
    name: 'PHP',
    scanner: 'code',
    lineComments: ['//', '#'],
    blockComments: [['/*', '*/']],
    strings: C_STRINGS,
    keywords: words('abstract and array as break callable case catch class clone const continue declare default do echo else elseif empty enddeclare endfor endforeach endif endswitch endwhile enum extends final finally fn for foreach function global goto if implements include include_once instanceof insteadof interface isset list match namespace new or print private protected public readonly require require_once return static switch throw trait try unset use var while xor yield'),
    constants: words('true false null TRUE FALSE NULL'),
    caseInsensitiveConstants: true,
    sigils: { $: 'var' },
    phpTags: true,
    pascalTypes: true,
    memberProps: true,
  },

  dart: {
    name: 'Dart',
    scanner: 'code',
    lineComments: ['//'],
    blockComments: [['/*', '*/']],
    strings: [
      { open: '"""', close: '"""', multiline: true },
      { open: "'''", close: "'''", multiline: true },
      ...C_STRINGS,
    ],
    keywords: words('abstract as assert async await base break case catch class const continue covariant default deferred do dynamic else enum export extends extension external factory final finally for get hide if implements import in interface is late library mixin new on operator part required rethrow return sealed set show static super switch sync this throw try typedef var when while with yield'),
    constants: words('true false null'),
    types: words('int double num bool String List Map Set Future Stream void Object Function'),
    decorators: true,
    pascalTypes: true,
    memberProps: true,
  },

  scala: {
    name: 'Scala',
    scanner: 'code',
    lineComments: ['//'],
    blockComments: [['/*', '*/']],
    strings: [{ open: '"""', close: '"""', multiline: true }, ...C_STRINGS],
    keywords: words('abstract case catch class def do else extends final finally for forSome if implicit import lazy match new object override package private protected return sealed super this throw trait try type val var while with yield given using enum export then end extension'),
    constants: words('true false null'),
    decorators: true,
    pascalTypes: true,
    memberProps: true,
  },

  elixir: {
    name: 'Elixir',
    scanner: 'code',
    lineComments: ['#'],
    strings: [{ open: '"""', close: '"""', multiline: true }, ...C_STRINGS],
    keywords: words('def defp defmodule defmacro defstruct defimpl defprotocol do end fn if else unless case cond with when import alias require use raise and or not in receive after rescue try catch quote unquote'),
    constants: words('true false nil'),
    symbols: true,
    sigils: { '@': 'deco' },
    pascalTypes: true,
    memberProps: true,
  },

  lua: {
    name: 'Lua',
    scanner: 'code',
    lineComments: ['--'],
    blockComments: [['--[[', ']]']],
    strings: [{ open: '[[', close: ']]', multiline: true, escape: false }, ...C_STRINGS],
    keywords: words('and break do else elseif end for function goto if in local not or repeat return then until while'),
    constants: words('true false nil'),
    memberProps: true,
  },

  sql: {
    name: 'SQL',
    scanner: 'code',
    lineComments: ['--'],
    blockComments: [['/*', '*/']],
    strings: [{ open: "'", close: "'", multiline: true, escape: false }],
    caseInsensitive: true,
    keywords: words('select from where insert into values update set delete create table drop alter add column primary key foreign references index view join inner left right full outer cross on group by order having limit offset union all distinct as and or not is in between like ilike exists case when then else end default unique check constraint begin commit rollback transaction returning with recursive cascade if database schema grant revoke trigger function procedure language replace temporary temp'),
    constants: words('null true false'),
    types: words('integer int smallint bigint serial bigserial varchar char text boolean bool date time timestamp timestamptz interval real float double decimal numeric uuid json jsonb bytea'),
  },

  shell: {
    name: 'Shell',
    scanner: 'code',
    lineComments: ['#'],
    hashNeedsBoundary: true,
    strings: [{ open: '"', close: '"', multiline: true }, { open: "'", close: "'", multiline: true, escape: false }],
    keywords: words('if then else elif fi for while until do done case esac in function return local export readonly declare unset shift exit select time break continue'),
    constants: words('true false'),
    builtins: words('echo printf cd pwd test read set source eval exec trap alias unalias type command builtin wait kill jobs bg fg umask ulimit getopts let mapfile'),
    shell: true,
    identifier: SHELL_WORD_RE,
  },

  dockerfile: {
    name: 'Dockerfile',
    scanner: 'code',
    lineComments: ['#'],
    hashNeedsBoundary: true,
    strings: [{ open: '"', close: '"' }, { open: "'", close: "'", escape: false }],
    keywords: words('FROM RUN CMD COPY ADD ENV ARG WORKDIR EXPOSE ENTRYPOINT USER VOLUME LABEL HEALTHCHECK SHELL ONBUILD STOPSIGNAL MAINTAINER AS if then else fi for do done in'),
    shell: true,
    identifier: SHELL_WORD_RE,
  },

  makefile: {
    name: 'Makefile',
    scanner: 'code',
    lineComments: ['#'],
    hashNeedsBoundary: true,
    strings: [{ open: '"', close: '"' }, { open: "'", close: "'", escape: false }],
    keywords: words('ifeq ifneq ifdef ifndef else endif include define endef export override'),
    makeRules: true,
    shell: true,
    identifier: SHELL_WORD_RE,
  },

  json: {
    name: 'JSON',
    scanner: 'code',
    lineComments: ['//'],
    blockComments: [['/*', '*/']],
    strings: [{ open: '"', close: '"' }],
    keywords: new Set(),
    constants: words('true false null'),
    jsonKeys: true,
  },

  yaml: { name: 'YAML', scanner: 'yaml' },
  toml: { name: 'TOML', scanner: 'ini' },
  ini: { name: 'INI', scanner: 'ini' },
  css: { name: 'CSS', scanner: 'css' },
  scss: { name: 'SCSS', scanner: 'css', lineComments: true },
  markup: { name: 'HTML', scanner: 'markup' },
  xml: { name: 'XML', scanner: 'markup' },
  vue: { name: 'Vue', scanner: 'markup' },
  markdown: { name: 'Markdown', scanner: 'markdown' },
};

const EXTENSIONS = {
  js: 'javascript', mjs: 'javascript', cjs: 'javascript', jsx: 'javascript',
  ts: 'typescript', mts: 'typescript', cts: 'typescript', tsx: 'typescript',
  py: 'python', pyi: 'python', pyw: 'python',
  rb: 'ruby', rake: 'ruby', gemspec: 'ruby',
  go: 'go', rs: 'rust',
  java: 'java', kt: 'kotlin', kts: 'kotlin', swift: 'swift',
  c: 'c', h: 'c',
  cc: 'cpp', cpp: 'cpp', cxx: 'cpp', hpp: 'cpp', hh: 'cpp', hxx: 'cpp', ino: 'cpp',
  cs: 'csharp', php: 'php', dart: 'dart', scala: 'scala', sc: 'scala',
  ex: 'elixir', exs: 'elixir', lua: 'lua', sql: 'sql',
  sh: 'shell', bash: 'shell', zsh: 'shell', ksh: 'shell', fish: 'shell',
  json: 'json', jsonc: 'json', json5: 'json', webmanifest: 'json',
  yml: 'yaml', yaml: 'yaml', toml: 'toml',
  ini: 'ini', cfg: 'ini', conf: 'ini', properties: 'ini', env: 'ini',
  css: 'css', scss: 'scss', sass: 'scss', less: 'scss',
  html: 'markup', htm: 'markup', xhtml: 'markup', svelte: 'markup', astro: 'markup',
  xml: 'xml', svg: 'xml', plist: 'xml', xsd: 'xml', csproj: 'xml',
  vue: 'vue',
  md: 'markdown', markdown: 'markdown', mdx: 'markdown',
  dockerfile: 'dockerfile', mk: 'makefile',
};

const FILENAMES = {
  dockerfile: 'dockerfile', containerfile: 'dockerfile',
  makefile: 'makefile', gnumakefile: 'makefile',
  gemfile: 'ruby', rakefile: 'ruby', podfile: 'ruby', vagrantfile: 'ruby',
  '.bashrc': 'shell', '.zshrc': 'shell', '.profile': 'shell', '.bash_profile': 'shell',
  '.gitignore': 'ini', '.gitattributes': 'ini', '.editorconfig': 'ini', '.npmrc': 'ini', '.env': 'ini',
  'cmakelists.txt': 'shell', jenkinsfile: 'java',
};

/**
 * Detects the language of a file from its path.
 * @param {string} filePath
 * @returns {{ id: string, name: string }}
 */
export function detectLanguage(filePath) {
  const base = path.posix.basename(String(filePath).replaceAll('\\', '/')).toLowerCase();
  let id = FILENAMES[base];
  if (!id && base.startsWith('dockerfile')) id = 'dockerfile';
  if (!id && base.startsWith('.env')) id = 'ini';
  if (!id) {
    const dot = base.lastIndexOf('.');
    if (dot >= 0) id = EXTENSIONS[base.slice(dot + 1)];
  }
  if (!id || !LANGUAGES[id]) id = 'plaintext';
  return { id, name: LANGUAGES[id].name };
}

/** @returns {string[]} Every supported language id. */
export function supportedLanguages() {
  return Object.keys(LANGUAGES);
}

// ---------------------------------------------------------------------------
// Token sink
// ---------------------------------------------------------------------------

class TokenSink {
  constructor() {
    /** @type {Array<Array<[string, string]>>} */
    this.lines = [[]];
  }

  /**
   * @param {string} cls
   * @param {string} text
   */
  emit(cls, text) {
    if (!text) return;
    let start = 0;
    for (;;) {
      const nl = text.indexOf('\n', start);
      const part = nl < 0 ? (start === 0 ? text : text.slice(start)) : text.slice(start, nl);
      if (part) this.push(cls, part);
      if (nl < 0) return;
      this.lines.push([]);
      start = nl + 1;
    }
  }

  /**
   * @param {string} cls
   * @param {string} part
   */
  push(cls, part) {
    const line = this.lines[this.lines.length - 1];
    const last = line[line.length - 1];
    if (last && last[0] === cls) last[1] += part;
    else line.push([cls, part]);
  }
}

// ---------------------------------------------------------------------------
// Shared helpers
// ---------------------------------------------------------------------------

/**
 * Returns the index just past a string literal starting at `i`.
 * Unterminated single-line strings stop at the end of the line.
 */
function scanString(text, i, spec, end) {
  const { open, close } = spec;
  const escape = spec.escape !== false;
  let j = i + open.length;
  while (j < end) {
    const c = text[j];
    if (escape && c === '\\') {
      j += 2;
      continue;
    }
    if (c === '\n' && !spec.multiline) return j;
    if (text.startsWith(close, j)) return j + close.length;
    j++;
  }
  return end;
}

function matchAt(re, text, i) {
  re.lastIndex = i;
  const m = re.exec(text);
  return m ? m[0] : null;
}

function nextNonSpace(text, i, end) {
  while (i < end && (text[i] === ' ' || text[i] === '\t')) i++;
  return i < end ? text[i] : '';
}

function lineEnd(text, i, end) {
  const nl = text.indexOf('\n', i);
  return nl < 0 || nl > end ? end : nl;
}

// ---------------------------------------------------------------------------
// Scanners
// ---------------------------------------------------------------------------

function scanPlain(text, _lang, sink, start = 0, end = text.length) {
  sink.emit('', text.slice(start, end));
}

/**
 * Generic scanner for C-family, scripting and data languages. Behaviour is
 * driven by flags on the language definition.
 */
function scanCode(text, lang, sink, start = 0, end = text.length) {
  const lineComments = lang.lineComments ?? [];
  const blockComments = lang.blockComments ?? [];
  const strings = [...(lang.strings ?? [])].sort((a, b) => b.open.length - a.open.length);
  const keywords = lang.keywords ?? new Set();
  const constants = lang.constants ?? new Set();
  const types = lang.types ?? new Set();
  const builtins = lang.builtins ?? new Set();
  const variables = lang.variables ?? new Set();
  const identRe = lang.identifier ?? (lang.sigils?.$ ? IDENT_NO_DOLLAR_RE : IDENT_RE);
  const ci = Boolean(lang.caseInsensitive);

  let i = start;
  let prevClass = '';
  let prevText = '';
  let prevWord = '';
  let lineStart = true;
  let cmdPos = true;

  const emit = (cls, s) => {
    sink.emit(cls, s);
    if (cls !== 'com') {
      prevClass = cls;
      prevText = s;
    }
    lineStart = false;
  };

  outer: while (i < end) {
    const ch = text[i];

    if (ch === '\n') {
      sink.emit('', '\n');
      i++;
      lineStart = true;
      cmdPos = true;
      continue;
    }
    if (ch === ' ' || ch === '\t' || ch === '\r') {
      let j = i + 1;
      while (j < end && (text[j] === ' ' || text[j] === '\t' || text[j] === '\r')) j++;
      sink.emit('', text.slice(i, j));
      i = j;
      continue;
    }

    // PHP open/close tags.
    if (lang.phpTags && (text.startsWith('<?php', i) || text.startsWith('<?=', i) || text.startsWith('?>', i))) {
      const tag = text.startsWith('<?php', i) ? '<?php' : text.startsWith('<?=', i) ? '<?=' : '?>';
      emit('deco', tag);
      i += tag.length;
      continue;
    }

    // Makefile: `target: deps` and `VAR := value` at the start of a line.
    if (lang.makeRules && lineStart && ch !== '\t') {
      const le = lineEnd(text, i, end);
      const line = text.slice(i, le);
      const assign = /^([A-Za-z_][\w.\-]*)(\s*)(\?=|:=|::=|\+=|!=|=)/.exec(line);
      if (assign) {
        emit('prop', assign[1]);
        sink.emit('', assign[2]);
        emit('op', assign[3]);
        i += assign[0].length;
        continue;
      }
      const rule = /^([^\s:#=][^:#=]*?)(\s*)(::?)(?!=)/.exec(line);
      if (rule) {
        emit('fn', rule[1]);
        sink.emit('', rule[2]);
        emit('punc', rule[3]);
        i += rule[0].length;
        continue;
      }
    }

    // C preprocessor directives: `#include <x.h>`, `#define FOO`.
    if (lang.preprocessor && lineStart && ch === '#') {
      const word = matchAt(/#\s*[A-Za-z_]\w*/y, text, i);
      if (word) {
        emit('kw', word);
        i += word.length;
        if (/include|import/.test(word)) {
          const rest = matchAt(/\s*<[^>\n]*>/y, text, i);
          if (rest) {
            const ws = rest.length - rest.trimStart().length;
            sink.emit('', rest.slice(0, ws));
            emit('str', rest.slice(ws));
            i += rest.length;
          }
        }
        continue;
      }
    }

    // Rust attributes: #[derive(Debug)] / #![allow(...)]
    if (lang.rustAttributes && ch === '#' && (text[i + 1] === '[' || (text[i + 1] === '!' && text[i + 2] === '['))) {
      let depth = 0;
      let j = i;
      while (j < end && text[j] !== '\n') {
        if (text[j] === '[') depth++;
        else if (text[j] === ']' && --depth === 0) {
          j++;
          break;
        }
        j++;
      }
      emit('deco', text.slice(i, j));
      i = j;
      continue;
    }

    for (const [open, close] of blockComments) {
      if (text.startsWith(open, i)) {
        const idx = text.indexOf(close, i + open.length);
        const stop = idx < 0 || idx + close.length > end ? end : idx + close.length;
        emit('com', text.slice(i, stop));
        i = stop;
        continue outer;
      }
    }

    for (const marker of lineComments) {
      if (text.startsWith(marker, i)) {
        if (marker === '#' && lang.hashNeedsBoundary && i > start && !/\s/.test(text[i - 1])) break;
        const stop = lineEnd(text, i, end);
        emit('com', text.slice(i, stop));
        i = stop;
        continue outer;
      }
    }

    // Shell / PHP / Ruby style sigil variables.
    if (lang.shell && ch === '$') {
      const v = matchAt(/\$(?:\{[^}\n]*\}|\([^)\n]*\)|[A-Za-z_]\w*|[0-9@#?$!*\-])/y, text, i);
      if (v) {
        emit('var', v);
        i += v.length;
        cmdPos = false;
        continue;
      }
    }
    if (lang.sigils && lang.sigils[ch]) {
      const v = matchAt(/[@$]{1,2}[A-Za-z_]\w*/y, text, i);
      if (v) {
        emit(lang.sigils[ch], v);
        i += v.length;
        continue;
      }
    }

    // Ruby / Elixir symbols (:name), avoiding `::` and ternaries.
    if (lang.symbols && ch === ':' && text[i + 1] !== ':' && prevText !== ':' && /[A-Za-z_]/.test(text[i + 1] ?? '')) {
      if (prevClass === '' || prevClass === 'punc' || prevClass === 'op' || prevClass === 'kw') {
        const sym = matchAt(/:[A-Za-z_]\w*[?!]?/y, text, i);
        if (sym) {
          emit('const', sym);
          i += sym.length;
          continue;
        }
      }
    }

    // Decorators / annotations.
    if (lang.decorators && ch === '@') {
      const d = matchAt(/@[A-Za-z_][\w.]*/y, text, i);
      if (d) {
        emit('deco', d);
        i += d.length;
        continue;
      }
    }

    // Strings.
    for (const spec of strings) {
      if (!text.startsWith(spec.open, i)) continue;
      if (spec.charLiteral) {
        const lit = matchAt(/'(?:\\(?:u\{[0-9a-fA-F]+\}|x[0-9a-fA-F]{2}|.)|[^\\'\n])'/y, text, i);
        if (lit) {
          emit('str', lit);
          i += lit.length;
          continue outer;
        }
        const lifetime = matchAt(/'[A-Za-z_]\w*/y, text, i);
        if (lifetime) {
          emit('deco', lifetime);
          i += lifetime.length;
          continue outer;
        }
        continue;
      }
      const stop = scanString(text, i, spec, end);
      const literal = text.slice(i, stop);
      const isKey = lang.jsonKeys && nextNonSpace(text, stop, end) === ':';
      emit(isKey ? 'prop' : 'str', literal);
      i = stop;
      cmdPos = false;
      continue outer;
    }

    // Numbers.
    if ((ch >= '0' && ch <= '9') || (ch === '.' && text[i + 1] >= '0' && text[i + 1] <= '9')) {
      const n = matchAt(NUMBER_RE, text, i);
      if (n) {
        emit('num', n);
        i += n.length;
        cmdPos = false;
        continue;
      }
    }

    // Shell flags such as -f or --force.
    if (lang.shell && ch === '-' && (i === start || /\s/.test(text[i - 1])) && /[A-Za-z-]/.test(text[i + 1] ?? '')) {
      const flag = matchAt(/--?[A-Za-z][\w-]*/y, text, i);
      if (flag) {
        emit('attr', flag);
        i += flag.length;
        continue;
      }
    }

    // Identifiers, keywords and friends.
    const word = matchAt(identRe, text, i);
    if (word) {
      let wordEnd = i + word.length;
      const lookup = ci ? word.toLowerCase() : word;

      // Python-style string prefixes: f"...", rb'...'.
      if (lang.stringPrefixes?.has(word.toLowerCase()) && (text[wordEnd] === '"' || text[wordEnd] === "'")) {
        const spec = strings.find((s) => text.startsWith(s.open, wordEnd) && !s.charLiteral);
        if (spec) {
          const stop = scanString(text, wordEnd, word.toLowerCase().includes('r') ? { ...spec, escape: false } : spec, end);
          emit('str', text.slice(i, stop));
          i = stop;
          continue;
        }
      }

      let cls = '';
      const next = text[wordEnd] ?? '';
      if (keywords.has(lookup)) cls = 'kw';
      else if (constants.has(lang.caseInsensitiveConstants ? word.toLowerCase() : lookup) || constants.has(lookup)) cls = 'const';
      else if (variables.has(word)) cls = 'var';
      else if (lang.macros && next === '!' && text[wordEnd + 1] !== '=') {
        cls = 'fn';
        wordEnd += 1;
      } else if (lang.shell && cmdPos) cls = builtins.has(word) || !lang.makeRules ? 'fn' : '';
      else if (TYPE_INTRODUCERS.has(prevWord)) cls = 'type';
      else if (nextNonSpace(text, wordEnd, end) === '(' && !types.has(word)) cls = 'fn';
      else if (types.has(lookup)) cls = 'type';
      else if (lang.memberProps && text[i - 1] === '.' && text[i - 2] !== '.') cls = PASCAL_RE.test(word) && lang.pascalTypes ? 'type' : 'prop';
      else if (lang.pascalTypes && PASCAL_RE.test(word)) cls = 'type';
      else if (ALL_CAPS_RE.test(word) && !lang.shell) cls = 'const';

      emit(cls, text.slice(i, wordEnd));
      prevWord = cls === 'kw' ? lookup : '';
      i = wordEnd;
      if (lang.shell) cmdPos = cls === 'kw' && /^(then|do|else|elif|if|while|until|time)$/.test(lookup);
      continue;
    }

    // Regular expression literals (JS/TS).
    if (lang.regex && ch === '/') {
      const allowed = prevClass === '' && prevText === ''
        || (prevClass === 'op')
        || (prevClass === 'punc' && !')]}'.includes(prevText.slice(-1)))
        || (prevClass === 'kw' && REGEX_AFTER_WORDS.has(prevText));
      if (allowed) {
        let j = i + 1;
        let inClass = false;
        let ok = false;
        while (j < end) {
          const c = text[j];
          if (c === '\n') break;
          if (c === '\\') {
            j += 2;
            continue;
          }
          if (c === '[') inClass = true;
          else if (c === ']') inClass = false;
          else if (c === '/' && !inClass) {
            ok = j > i + 1;
            break;
          }
          j++;
        }
        if (ok) {
          j++;
          while (j < end && /[a-z]/.test(text[j])) j++;
          emit('regex', text.slice(i, j));
          i = j;
          continue;
        }
      }
    }

    if (PUNCT.has(ch)) {
      emit('punc', ch);
      i++;
      if (lang.shell && (ch === ';' || ch === '(' || ch === '{')) cmdPos = true;
      continue;
    }

    const op = matchAt(OPERATOR_RE, text, i);
    if (op) {
      emit('op', op);
      i += op.length;
      if (lang.shell && (op.includes('|') || op.includes('&'))) cmdPos = true;
      continue;
    }

    emit('', ch);
    i++;
  }
}

/** HTML / XML / Vue / Svelte with embedded <script> and <style> blocks. */
function scanMarkup(text, _lang, sink, start = 0, end = text.length) {
  let i = start;
  while (i < end) {
    const lt = text.indexOf('<', i);
    const textEnd = lt < 0 || lt >= end ? end : lt;
    if (textEnd > i) {
      emitMarkupText(text.slice(i, textEnd), sink);
      i = textEnd;
      if (i >= end) break;
    }

    if (text.startsWith('<!--', i)) {
      const idx = text.indexOf('-->', i + 4);
      const stop = idx < 0 ? end : Math.min(end, idx + 3);
      sink.emit('com', text.slice(i, stop));
      i = stop;
      continue;
    }
    if (text.startsWith('<![CDATA[', i)) {
      const idx = text.indexOf(']]>', i);
      const stop = idx < 0 ? end : Math.min(end, idx + 3);
      sink.emit('str', text.slice(i, stop));
      i = stop;
      continue;
    }
    if (text.startsWith('<!', i) || text.startsWith('<?', i)) {
      const idx = text.indexOf('>', i);
      const stop = idx < 0 ? end : Math.min(end, idx + 1);
      sink.emit('deco', text.slice(i, stop));
      i = stop;
      continue;
    }

    const tagMatch = matchAt(/<\/?[A-Za-z][\w:.-]*/y, text, i);
    if (!tagMatch) {
      sink.emit('', '<');
      i++;
      continue;
    }
    const closing = tagMatch[1] === '/';
    const tagName = tagMatch.slice(closing ? 2 : 1).toLowerCase();
    sink.emit('punc', closing ? '</' : '<');
    sink.emit('tag', tagMatch.slice(closing ? 2 : 1));
    i += tagMatch.length;

    // Attributes until > or />
    while (i < end) {
      const c = text[i];
      if (c === '>') {
        sink.emit('punc', '>');
        i++;
        break;
      }
      if (c === '/' && text[i + 1] === '>') {
        sink.emit('punc', '/>');
        i += 2;
        break;
      }
      if (c === '"' || c === "'") {
        const stop = scanString(text, i, { open: c, close: c, multiline: true, escape: false }, end);
        sink.emit('str', text.slice(i, stop));
        i = stop;
        continue;
      }
      if (c === '=') {
        sink.emit('op', '=');
        i++;
        continue;
      }
      const attr = matchAt(/[^\s=>"'/]+/y, text, i);
      if (attr) {
        sink.emit('attr', attr);
        i += attr.length;
        continue;
      }
      sink.emit('', c);
      i++;
    }

    // Embedded script / style content.
    if (!closing && (tagName === 'script' || tagName === 'style')) {
      const closeIdx = text.toLowerCase().indexOf(`</${tagName}`, i);
      const stop = closeIdx < 0 || closeIdx > end ? end : closeIdx;
      const inner = tagName === 'script' ? LANGUAGES.typescript : LANGUAGES.scss;
      SCANNERS[inner.scanner](text, inner, sink, i, stop);
      i = stop;
    }
  }
}

function emitMarkupText(s, sink) {
  let last = 0;
  for (const m of s.matchAll(/&(?:#\d+|#x[\da-fA-F]+|[A-Za-z]+);/g)) {
    sink.emit('', s.slice(last, m.index));
    sink.emit('const', m[0]);
    last = m.index + m[0].length;
  }
  sink.emit('', s.slice(last));
}

/** CSS / SCSS / Less. */
function scanCss(text, lang, sink, start = 0, end = text.length) {
  let i = start;
  let depth = 0;
  let mode = 'selector'; // selector | property | value
  let parenDepth = 0;

  const statementMode = (from) => {
    // Inside a block: a statement whose first delimiter is `{` is a nested selector.
    for (let j = from; j < end; j++) {
      const c = text[j];
      if (c === '{') return 'selector';
      if (c === ';' || c === '}') return 'property';
      if (c === '"' || c === "'") j = scanString(text, j, { open: c, close: c }, end) - 1;
    }
    return 'property';
  };

  while (i < end) {
    const ch = text[i];
    if (ch === '\n' || ch === ' ' || ch === '\t' || ch === '\r') {
      let j = i + 1;
      while (j < end && /[ \t\r\n]/.test(text[j])) j++;
      sink.emit('', text.slice(i, j));
      i = j;
      continue;
    }
    if (text.startsWith('/*', i)) {
      const idx = text.indexOf('*/', i + 2);
      const stop = idx < 0 ? end : Math.min(end, idx + 2);
      sink.emit('com', text.slice(i, stop));
      i = stop;
      continue;
    }
    if (lang.lineComments && text.startsWith('//', i) && text[i - 1] !== ':') {
      const stop = lineEnd(text, i, end);
      sink.emit('com', text.slice(i, stop));
      i = stop;
      continue;
    }
    if (ch === '"' || ch === "'") {
      const stop = scanString(text, i, { open: ch, close: ch }, end);
      sink.emit('str', text.slice(i, stop));
      i = stop;
      continue;
    }
    if (ch === '{') {
      sink.emit('punc', ch);
      depth++;
      i++;
      mode = statementMode(i);
      continue;
    }
    if (ch === '}') {
      sink.emit('punc', ch);
      depth = Math.max(0, depth - 1);
      i++;
      mode = depth > 0 ? statementMode(i) : 'selector';
      continue;
    }
    if (ch === ';') {
      sink.emit('punc', ch);
      i++;
      mode = depth > 0 ? statementMode(i) : 'selector';
      continue;
    }
    if (ch === '@') {
      const at = matchAt(/@[\w-]+/y, text, i);
      if (at) {
        sink.emit('kw', at);
        i += at.length;
        continue;
      }
    }
    if (ch === '$' || (ch === '-' && text[i + 1] === '-')) {
      const v = matchAt(/(?:\$|--)[\w-]+/y, text, i);
      if (v) {
        const isDecl = mode !== 'value' && nextNonSpace(text, i + v.length, end) === ':';
        sink.emit(isDecl ? 'prop' : 'var', v);
        i += v.length;
        continue;
      }
    }

    if (mode === 'selector') {
      if (ch === '(' || ch === ')') {
        parenDepth = Math.max(0, parenDepth + (ch === '(' ? 1 : -1));
        sink.emit('punc', ch);
        i++;
        continue;
      }
      if (ch >= '0' && ch <= '9') {
        const num = matchAt(/\d+\.?\d*(?:[a-zA-Z%]+)?/y, text, i);
        sink.emit('num', num);
        i += num.length;
        continue;
      }
      if (parenDepth > 0) {
        const feature = matchAt(/[A-Za-z-][\w-]*(?=\s*:)/y, text, i);
        if (feature) {
          sink.emit('prop', feature);
          i += feature.length;
          continue;
        }
      }
      if (ch === '.' || ch === '#') {
        const sel = matchAt(/[.#][\w-]+/y, text, i);
        if (sel) {
          sink.emit(ch === '.' ? 'type' : 'fn', sel);
          i += sel.length;
          continue;
        }
      }
      if (ch === ':' && parenDepth === 0) {
        const pseudo = matchAt(/::?[\w-]+/y, text, i);
        if (pseudo) {
          sink.emit('deco', pseudo);
          i += pseudo.length;
          continue;
        }
      }
      if (ch === '[') {
        const idx = text.indexOf(']', i);
        const stop = idx < 0 ? end : Math.min(end, idx + 1);
        sink.emit('attr', text.slice(i, stop));
        i = stop;
        continue;
      }
      const el = matchAt(/[A-Za-z][\w-]*/y, text, i);
      if (el) {
        sink.emit('tag', el);
        i += el.length;
        continue;
      }
      if (ch === '&' || ch === '*') {
        sink.emit('op', ch);
        i++;
        continue;
      }
    } else if (mode === 'property') {
      const prop = matchAt(/[A-Za-z-][\w-]*/y, text, i);
      if (prop) {
        sink.emit('prop', prop);
        i += prop.length;
        continue;
      }
      if (ch === ':') {
        sink.emit('punc', ':');
        i++;
        mode = 'value';
        parenDepth = 0;
        continue;
      }
    } else {
      if (ch === '#') {
        const color = matchAt(/#[\da-fA-F]{3,8}\b/y, text, i);
        if (color) {
          sink.emit('num', color);
          i += color.length;
          continue;
        }
      }
      if ((ch >= '0' && ch <= '9') || ((ch === '.' || ch === '-') && /[\d.]/.test(text[i + 1] ?? ''))) {
        const num = matchAt(/-?(?:\d+\.?\d*|\.\d+)(?:[a-zA-Z%]+)?/y, text, i);
        if (num) {
          sink.emit('num', num);
          i += num.length;
          continue;
        }
      }
      if (ch === '!') {
        const imp = matchAt(/!\s*important/y, text, i);
        if (imp) {
          sink.emit('kw', imp);
          i += imp.length;
          continue;
        }
      }
      const ident = matchAt(/[A-Za-z_-][\w-]*/y, text, i);
      if (ident) {
        sink.emit(text[i + ident.length] === '(' ? 'fn' : 'const', ident);
        i += ident.length;
        continue;
      }
      if (ch === '(') parenDepth++;
      if (ch === ')') parenDepth = Math.max(0, parenDepth - 1);
    }

    sink.emit(/[(),:>+~]/.test(ch) ? 'punc' : 'op', ch);
    i++;
  }
}

/** Emits a scalar value (YAML/TOML/INI right-hand side) with inline comments. */
function emitScalar(s, sink, commentChars) {
  let i = 0;
  while (i < s.length) {
    const ch = s[i];
    if (ch === ' ' || ch === '\t') {
      let j = i + 1;
      while (j < s.length && (s[j] === ' ' || s[j] === '\t')) j++;
      sink.emit('', s.slice(i, j));
      i = j;
      continue;
    }
    if (commentChars.includes(ch) && (i === 0 || /\s/.test(s[i - 1]))) {
      sink.emit('com', s.slice(i));
      return;
    }
    if (ch === '"' || ch === "'") {
      const stop = scanString(s, i, { open: ch, close: ch, escape: ch === '"' }, s.length);
      sink.emit('str', s.slice(i, stop));
      i = stop;
      continue;
    }
    if (ch === '&' || ch === '*') {
      const anchor = matchAt(/[&*][\w-]+/y, s, i);
      if (anchor) {
        sink.emit('var', anchor);
        i += anchor.length;
        continue;
      }
    }
    if (ch === '!') {
      const tag = matchAt(/!!?[\w-]*/y, s, i);
      if (tag) {
        sink.emit('deco', tag);
        i += tag.length;
        continue;
      }
    }
    if ('[]{},'.includes(ch)) {
      sink.emit('punc', ch);
      i++;
      continue;
    }
    if (ch === '|' || ch === '>') {
      sink.emit('op', ch);
      i++;
      continue;
    }
    const wordMatch = matchAt(/[^\s,[\]{}#]+(?:[ \t]+[^\s,[\]{}#]+)*/y, s, i);
    if (wordMatch) {
      const w = wordMatch;
      let cls = 'str';
      if (/^(?:true|false|yes|no|on|off|null|~|True|False|Yes|No|On|Off|Null|NULL|TRUE|FALSE)$/.test(w)) cls = 'const';
      else if (/^[-+]?(?:0x[\da-fA-F_]+|0o[0-7_]+|0b[01_]+|\d[\d_]*(?:\.\d+)?(?:[eE][-+]?\d+)?|\.inf|\.nan|inf|nan)$/.test(w)) cls = 'num';
      else if (/^\d{4}-\d{2}-\d{2}(?:[T ][\d:.]+(?:Z|[+-]\d{2}:\d{2})?)?$/.test(w)) cls = 'num';
      sink.emit(cls, w);
      i += w.length;
      continue;
    }
    sink.emit('', ch);
    i++;
  }
}

function scanYaml(text, _lang, sink, start = 0, end = text.length) {
  const lines = text.slice(start, end).split('\n');
  let blockIndent = -1;
  lines.forEach((line, idx) => {
    if (idx > 0) sink.emit('', '\n');
    const indent = line.length - line.trimStart().length;
    if (blockIndent >= 0) {
      if (line.trim() === '' || indent > blockIndent) {
        sink.emit('', line.slice(0, indent));
        sink.emit('str', line.slice(indent));
        return;
      }
      blockIndent = -1;
    }
    if (/^\s*#/.test(line)) {
      sink.emit('', line.slice(0, indent));
      sink.emit('com', line.slice(indent));
      return;
    }
    if (/^(?:---|\.\.\.)\s*$/.test(line)) {
      sink.emit('punc', line);
      return;
    }
    const m = /^(\s*)((?:-[ \t]+)*)((?:"[^"]*"|'[^']*'|[^\s#'"\-][^#]*?|-[^\s#][^#]*?))([ \t]*:)(?=[ \t]|$)/.exec(line);
    let rest = line;
    if (m) {
      sink.emit('', m[1]);
      if (m[2]) sink.emit('op', m[2]);
      sink.emit('prop', m[3]);
      sink.emit('punc', m[4]);
      rest = line.slice(m[0].length);
    } else {
      const dash = /^(\s*)((?:-[ \t]+|-$)+)/.exec(line);
      if (dash) {
        sink.emit('', dash[1]);
        sink.emit('op', dash[2]);
        rest = line.slice(dash[0].length);
      }
    }
    if (/^\s*[|>][-+0-9]*\s*(?:#.*)?$/.test(rest)) blockIndent = indent;
    emitScalar(rest, sink, '#');
  });
}

function scanIni(text, _lang, sink, start = 0, end = text.length) {
  const lines = text.slice(start, end).split('\n');
  lines.forEach((line, idx) => {
    if (idx > 0) sink.emit('', '\n');
    const indent = line.length - line.trimStart().length;
    const body = line.slice(indent);
    sink.emit('', line.slice(0, indent));
    if (body.startsWith('#') || body.startsWith(';')) {
      sink.emit('com', body);
      return;
    }
    const section = /^(\[\[?)([^\]]*)(\]\]?)(.*)$/.exec(body);
    if (section) {
      sink.emit('punc', section[1]);
      sink.emit('type', section[2]);
      sink.emit('punc', section[3]);
      emitScalar(section[4], sink, '#;');
      return;
    }
    const kv = /^((?:"[^"]*"|'[^']*'|[^=:#;\s][^=:#;]*?))(\s*)([=:])(.*)$/.exec(body);
    if (kv) {
      sink.emit('prop', kv[1]);
      sink.emit('', kv[2]);
      sink.emit('op', kv[3]);
      emitScalar(kv[4], sink, '#;');
      return;
    }
    emitScalar(body, sink, '#;');
  });
}

function scanMarkdown(text, _lang, sink, start = 0, end = text.length) {
  const lines = text.slice(start, end).split('\n');
  let fence = null; // { marker, lang }
  let fenceBuffer = [];

  const flushFence = () => {
    if (!fenceBuffer.length) return;
    const body = fenceBuffer.join('\n');
    const lang = LANGUAGES[fence.lang] ?? null;
    if (lang && lang.scanner !== 'markdown') SCANNERS[lang.scanner](body, lang, sink, 0, body.length);
    else sink.emit('str', body);
    fenceBuffer = [];
  };

  lines.forEach((line, idx) => {
    if (fence) {
      if (line.trimStart().startsWith(fence.marker)) {
        flushFence();
        if (idx > 0) sink.emit('', '\n');
        sink.emit('com', line);
        fence = null;
      } else if (fenceBuffer.length === 0) {
        if (idx > 0) sink.emit('', '\n');
        fenceBuffer.push(line);
      } else {
        fenceBuffer.push(line);
      }
      return;
    }
    if (idx > 0) sink.emit('', '\n');
    const open = /^(\s*)(`{3,}|~{3,})\s*([\w+#-]*)/.exec(line);
    if (open) {
      const info = open[3].toLowerCase();
      fence = { marker: open[2], lang: EXTENSIONS[info] ?? (LANGUAGES[info] ? info : null) };
      sink.emit('com', line);
      return;
    }
    if (/^#{1,6}\s/.test(line)) {
      sink.emit('kw', line);
      return;
    }
    if (/^\s*>/.test(line)) {
      sink.emit('com', line);
      return;
    }
    if (/^\s*(?:[-*_]\s*){3,}$/.test(line)) {
      sink.emit('punc', line);
      return;
    }
    let rest = line;
    const bullet = /^(\s*)([-*+]|\d+[.)])(\s+)/.exec(line);
    if (bullet) {
      sink.emit('', bullet[1]);
      sink.emit('op', bullet[2]);
      sink.emit('', bullet[3]);
      rest = line.slice(bullet[0].length);
    }
    emitMarkdownInline(rest, sink);
  });
  if (fence) flushFence();
}

function emitMarkdownInline(s, sink) {
  const re = /(`+)([^`]*?)\1|(\*\*|__)(?=\S)(.+?)\3|(\*|_)(?=\S)([^*_]+?)\5|(!?\[)([^\]]*)(\]\()([^)\s]*)(\))|(\|)/g;
  let last = 0;
  for (const m of s.matchAll(re)) {
    sink.emit('', s.slice(last, m.index));
    if (m[1]) sink.emit('str', m[0]);
    else if (m[3]) sink.emit('type', m[0]);
    else if (m[5]) sink.emit('deco', m[0]);
    else if (m[7]) {
      sink.emit('punc', m[7]);
      sink.emit('fn', m[8]);
      sink.emit('punc', m[9]);
      sink.emit('com', m[10]);
      sink.emit('punc', m[11]);
    } else sink.emit('punc', m[0]);
    last = m.index + m[0].length;
  }
  sink.emit('', s.slice(last));
}

const SCANNERS = {
  plain: scanPlain,
  code: scanCode,
  markup: scanMarkup,
  css: scanCss,
  yaml: scanYaml,
  ini: scanIni,
  markdown: scanMarkdown,
};

/**
 * Tokenizes `text` into per-line token arrays.
 *
 * @param {string} text Source text with LF line endings.
 * @param {string} languageId One of supportedLanguages().
 * @returns {Array<Array<[string, string]>>}
 */
export function tokenize(text, languageId) {
  const lang = LANGUAGES[languageId] ?? LANGUAGES.plaintext;
  const sink = new TokenSink();
  try {
    SCANNERS[lang.scanner](text, lang, sink, 0, text.length);
  } catch {
    // A highlighter bug must never break a render: fall back to plain text.
    const plain = new TokenSink();
    plain.emit('', text);
    return plain.lines;
  }
  return sink.lines;
}
