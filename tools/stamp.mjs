// Ставит версию приложения: список файлов для работы без сети и отпечаток их содержимого.
//
//   node tools/stamp.mjs          записать версию в sw.js и js/version.js
//   node tools/stamp.mjs --check  проверить, что версия соответствует файлам (для тестов)
//
// Запускать после любой правки файлов приложения: по изменившемуся sw.js телефон понимает,
// что вышла новая версия, и скачивает её целиком.

import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

export const ROOT = path.join(path.dirname(fileURLToPath(import.meta.url)), '..');

/** Папки и файлы, из которых состоит приложение на телефоне. */
const APP_DIRS = ['css', 'js', 'icons', 'img'];
const APP_FILES = ['manifest.webmanifest'];
const VERSION_FILE = 'js/version.js';
const SW_FILE = 'sw.js';
const STAMP_RE = /\/\* stamp:begin[^\n]*\*\/\n[\s\S]*?\/\* stamp:end \*\//;

function walk(dir) {
  const out = [];
  for (const entry of fs.readdirSync(path.join(ROOT, dir), { withFileTypes: true })) {
    if (entry.name.startsWith('.')) continue;
    const rel = `${dir}/${entry.name}`;
    if (entry.isDirectory()) out.push(...walk(rel));
    else out.push(rel);
  }
  return out;
}

/** Файлы приложения в устойчивом порядке; './' — сама страница. */
export function appFiles() {
  const files = [...APP_FILES, ...APP_DIRS.flatMap(walk)].sort();
  return ['./', ...files];
}

function read(rel) {
  return fs.readFileSync(path.join(ROOT, rel));
}

/** Отпечаток содержимого. Сами места, куда пишется версия, в него не входят. */
export function fingerprint(files = appFiles()) {
  const hash = crypto.createHash('sha256');
  for (const rel of files) {
    if (rel === VERSION_FILE) continue;
    hash.update(`${rel}\n`);
    hash.update(read(rel === './' ? 'index.html' : rel));
    hash.update('\n');
  }
  hash.update(`${SW_FILE}\n`);
  hash.update(read(SW_FILE).toString('utf8').replace(STAMP_RE, ''));
  return hash.digest('hex').slice(0, 10);
}

export function expected() {
  const files = appFiles();
  const pkg = JSON.parse(read('package.json').toString('utf8'));
  const version = `${pkg.version}+${fingerprint(files)}`;
  const block = [
    '/* stamp:begin — блок пишет tools/stamp.mjs, руками не править */',
    `const VERSION = ${JSON.stringify(version)};`,
    `const FILES = ${JSON.stringify(files, null, 2)};`,
    '/* stamp:end */',
  ].join('\n');
  const sw = read(SW_FILE).toString('utf8');
  if (!STAMP_RE.test(sw)) throw new Error('В sw.js не найден блок stamp:begin … stamp:end');
  return {
    version,
    files,
    [SW_FILE]: sw.replace(STAMP_RE, () => block),
    [VERSION_FILE]: `// Файл создаёт tools/stamp.mjs. Руками не править.\nexport const VERSION = ${JSON.stringify(version).replace(/"/g, "'")};\n`,
  };
}

/** @returns {string[]} файлы, в которых версия устарела */
export function stale() {
  const want = expected();
  return [SW_FILE, VERSION_FILE].filter((rel) => read(rel).toString('utf8') !== want[rel]);
}

export function stamp() {
  const want = expected();
  for (const rel of [SW_FILE, VERSION_FILE]) {
    if (read(rel).toString('utf8') !== want[rel]) fs.writeFileSync(path.join(ROOT, rel), want[rel]);
  }
  return want.version;
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  if (process.argv.includes('--check')) {
    const old = stale();
    if (old.length) {
      console.error(`Версия устарела в файлах: ${old.join(', ')}. Запустите: npm run stamp`);
      process.exit(1);
    }
    console.log(`Версия актуальна: ${expected().version}`);
  } else {
    console.log(`Версия: ${stamp()}`);
  }
}
