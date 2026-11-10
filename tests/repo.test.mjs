// Проверки самого репозитория: в нём нет секретов, версия актуальна, приложение
// собрано так, что откроется без сети, а цвета читаются в обеих темах.

import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { ROOT } from './helpers.mjs';
import { appFiles, stale } from '../tools/stamp.mjs';

const SKIP_DIRS = new Set(['.git', 'node_modules', '.tmp', 'out']);
const BINARY = new Set(['.png', '.jpg', '.jpeg', '.gif', '.webp', '.ico', '.woff', '.woff2', '.pdf']);

function walk(dir = '') {
  const out = [];
  for (const entry of fs.readdirSync(path.join(ROOT, dir), { withFileTypes: true })) {
    if (SKIP_DIRS.has(entry.name)) continue;
    const rel = dir ? `${dir}/${entry.name}` : entry.name;
    if (entry.isDirectory()) out.push(...walk(rel));
    else out.push(rel);
  }
  return out;
}

const read = (rel) => fs.readFileSync(path.join(ROOT, rel), 'utf8');
const ALL = walk();
const TEXT = ALL.filter((rel) => !BINARY.has(path.extname(rel).toLowerCase()));

/* ------------------------------------------------------------------ */
/* Секреты и личные данные                                             */
/* ------------------------------------------------------------------ */

// Учебные значения, которые в репозитории лежать могут: они ни к чему не подходят.
const FAKE_DEPLOYMENTS = new Set(['TESTDEPLOYMENTID_0123456789', 'MOCK_DEPLOYMENT', 'ABCDEFGH12345']);
const FAKE_KEYS = new Set(['0123456789abcdef0123456789abcdef01234567']);

test('в репозитории нет ID таблицы, адреса веб-приложения и ключа', () => {
  const found = [];
  for (const rel of TEXT) {
    const text = read(rel);
    // ссылка на таблицу или её ID: 44 знака, начинается с единицы
    for (const m of text.matchAll(/spreadsheets\/d\/([A-Za-z0-9_-]{20,})/g)) found.push(`${rel}: ссылка на таблицу ${m[1].slice(0, 6)}…`);
    for (const m of text.matchAll(/(?<![A-Za-z0-9_-])1[A-Za-z0-9_-]{43}(?![A-Za-z0-9_-])/g)) found.push(`${rel}: похоже на ID таблицы ${m[0].slice(0, 6)}…`);
    // ID развёртывания Apps Script
    for (const m of text.matchAll(/AKfycb[A-Za-z0-9_-]{10,}/g)) found.push(`${rel}: ID развёртывания ${m[0].slice(0, 10)}…`);
    for (const m of text.matchAll(/script\.google\.com\/(?:a\/[^/\s]+\/)?macros\/s\/([A-Za-z0-9_-]+)\/(?:exec|dev)/g)) {
      if (!FAKE_DEPLOYMENTS.has(m[1])) found.push(`${rel}: адрес веб-приложения ${m[1].slice(0, 6)}…`);
    }
    // ключ скрипта: 40 шестнадцатеричных знаков
    for (const m of text.matchAll(/(?<![0-9a-f])[0-9a-f]{40}(?![0-9a-f])/gi)) {
      if (!FAKE_KEYS.has(m[0].toLowerCase())) found.push(`${rel}: похоже на ключ ${m[0].slice(0, 6)}…`);
    }
  }
  assert.deepEqual(found, []);
});

test('документ с описанием проекта и выгрузки таблицы не попали в репозиторий', () => {
  const suspicious = ALL.filter((rel) => /brief|передача|\.xlsx$|\.csv$|\.env/i.test(rel));
  assert.deepEqual(suspicious, []);
});

/* ------------------------------------------------------------------ */
/* Версия и работа без сети                                            */
/* ------------------------------------------------------------------ */

test('версия в sw.js и js/version.js соответствует файлам (npm run stamp)', () => {
  assert.deepEqual(stale(), [], 'после правки файлов приложения запустите npm run stamp');
});

test('всё, что загружает страница, сохранено для работы без сети', () => {
  const cached = new Set(appFiles());
  const missing = [];
  const need = (rel, from) => {
    if (!cached.has(rel)) missing.push(`${rel} (из ${from})`);
    else if (!fs.existsSync(path.join(ROOT, rel))) missing.push(`${rel} нет на диске`);
  };
  // модули: каждый import ведёт на сохранённый файл
  for (const rel of appFiles().filter((f) => f.endsWith('.js'))) {
    for (const m of read(rel).matchAll(/(?:import|export)\s[^'"]*?from\s+['"]([^'"]+)['"]|import\s+['"]([^'"]+)['"]/g)) {
      const target = m[1] || m[2];
      assert.ok(target.startsWith('.'), `${rel}: импорт «${target}» должен быть относительным`);
      need(path.posix.normalize(path.posix.join(path.posix.dirname(rel), target)), rel);
    }
  }
  // страница и манифест
  const html = read('index.html');
  for (const m of html.matchAll(/(?:src|href)="([^"]+)"/g)) need(m[1], 'index.html');
  const manifest = JSON.parse(read('manifest.webmanifest'));
  for (const item of manifest.icons) need(item.src, 'manifest.webmanifest');
  assert.deepEqual(missing, []);
});

test('манифест описывает устанавливаемое приложение в своей папке', () => {
  const manifest = JSON.parse(read('manifest.webmanifest'));
  assert.equal(manifest.display, 'standalone');
  assert.equal(manifest.lang, 'ru');
  // относительные адреса: сайт живёт в папке /gym-journal/, а не в корне
  assert.equal(manifest.start_url, './');
  assert.equal(manifest.scope, './');
  assert.ok(manifest.name && manifest.short_name && manifest.short_name.length <= 12);
  const sizes = manifest.icons.map((i) => `${i.sizes}/${i.purpose}`);
  assert.ok(sizes.includes('192x192/any') && sizes.includes('512x512/any') && sizes.includes('512x512/maskable'));
  for (const item of manifest.icons) {
    const bytes = fs.readFileSync(path.join(ROOT, item.src));
    assert.equal(bytes.subarray(1, 4).toString('latin1'), 'PNG', `${item.src} — не PNG`);
    const side = Number(item.sizes.split('x')[0]);
    assert.equal(bytes.readUInt32BE(16), side, `${item.src}: ширина`);
    assert.equal(bytes.readUInt32BE(20), side, `${item.src}: высота`);
  }
});

/* ------------------------------------------------------------------ */
/* Безопасность страницы                                               */
/* ------------------------------------------------------------------ */

test('страница не содержит встроенных скриптов и стилей, адреса относительные', () => {
  const html = read('index.html');
  const csp = /http-equiv="Content-Security-Policy" content="([^"]+)"/.exec(html);
  assert.ok(csp, 'есть политика безопасности');
  const policy = Object.fromEntries(csp[1].split(';').map((part) => part.trim().split(/\s+/)).map(([name, ...rest]) => [name, rest]));
  assert.deepEqual(policy['script-src'], ["'self'"]);
  assert.deepEqual(policy['style-src'], ["'self'"]);
  assert.deepEqual(policy['default-src'], ["'self'"]);
  assert.ok(policy['connect-src'].includes('https://script.google.com'));
  assert.ok(policy['connect-src'].every((src) => src === "'self'" || /^https:\/\/(?:script\.google\.com|(?:script|\*)\.googleusercontent\.com)$/.test(src)),
    'данные уходят только в Google Apps Script');

  assert.ok(!/<script(?![^>]*\ssrc=)[^>]*>/.test(html), 'нет встроенных скриптов');
  assert.ok(!/<style[\s>]/.test(html), 'нет встроенных стилей');
  assert.ok(!/\sstyle=/.test(html), 'нет атрибутов style');
  assert.ok(!/\son[a-z]+=/.test(html), 'нет обработчиков в атрибутах');
  for (const m of html.matchAll(/(?:src|href)="([^"]+)"/g)) {
    assert.ok(!/^(?:[a-z]+:)?\/\//i.test(m[1]) && !m[1].startsWith('/'), `адрес «${m[1]}» должен быть относительным`);
  }
});

test('код приложения не превращает текст в разметку или код', () => {
  const bad = [];
  for (const rel of appFiles().filter((f) => f.endsWith('.js')).concat('sw.js')) {
    const text = read(rel);
    for (const pattern of [/\.innerHTML\b/, /\.outerHTML\b/, /insertAdjacentHTML/, /document\.write/, /\beval\s*\(/, /new\s+Function\b/, /setAttribute\(\s*['"]style['"]/]) {
      if (pattern.test(text)) bad.push(`${rel}: ${pattern}`);
    }
  }
  assert.deepEqual(bad, []);
});

/* ------------------------------------------------------------------ */
/* Стили                                                               */
/* ------------------------------------------------------------------ */

const css = read('css/app.css');

function block(source, startIndex) {
  const open = source.indexOf('{', startIndex);
  let depth = 0;
  for (let i = open; i < source.length; i += 1) {
    if (source[i] === '{') depth += 1;
    if (source[i] === '}') {
      depth -= 1;
      if (depth === 0) return source.slice(open + 1, i);
    }
  }
  throw new Error('не закрыт блок CSS');
}

function tokens(body) {
  const out = {};
  for (const m of body.matchAll(/(--[a-z0-9-]+)\s*:\s*([^;]+);/g)) out[m[1]] = m[2].trim();
  return out;
}

const light = tokens(block(css, css.indexOf(':root {')));
const darkForced = tokens(block(css, css.indexOf(":root[data-theme='dark']")));
const darkSystem = tokens(block(css, css.indexOf(":root:not([data-theme='light'])")));

function luminance(hex) {
  const m = /^#([0-9a-f]{6})$/i.exec(hex);
  assert.ok(m, `ожидается цвет вида #rrggbb, а не «${hex}»`);
  const [r, g, b] = [0, 2, 4].map((i) => parseInt(m[1].slice(i, i + 2), 16) / 255)
    .map((c) => (c <= 0.04045 ? c / 12.92 : ((c + 0.055) / 1.055) ** 2.4));
  return 0.2126 * r + 0.7152 * g + 0.0722 * b;
}

function contrast(a, b) {
  const [hi, lo] = [luminance(a), luminance(b)].sort((x, y) => y - x);
  return (hi + 0.05) / (lo + 0.05);
}

// [текст, фон, наименьший контраст]: 4.5 — обычный текст, 3 — крупные цифры, значки и линии графиков
const PAIRS = [
  ['--ink', '--page', 4.5], ['--ink', '--surface', 4.5], ['--ink', '--surface-2', 4.5],
  ['--ink-2', '--page', 4.5], ['--ink-2', '--surface', 4.5], ['--ink-2', '--surface-2', 4.5],
  ['--ink-3', '--surface', 4.5], ['--ink-3', '--surface-2', 4.5], ['--ink-3', '--page', 4.5],
  ['--accent-ink', '--accent', 4.5], ['--accent-text', '--surface', 4.5], ['--accent-text', '--page', 4.5],
  ['--accent-soft-ink', '--accent-soft', 4.5],
  ['--ok-soft-ink', '--ok-soft', 4.5], ['--ok', '--surface', 4.5],
  ['--warn-soft-ink', '--warn-soft', 4.5],
  ['--danger-soft-ink', '--danger-soft', 4.5], ['--danger', '--surface', 4.5],
  ['--surface', '--ink', 4.5],
  ['--mark', '--surface', 3], ['--mark', '--mark-track', 1.5],
  ['--line-strong', '--surface', 3], ['--line-strong', '--page', 3],
  // рисунки упражнений лежат на фоне страницы
  ['--art-move', '--page', 3], ['--mark', '--page', 3],
];

for (const [name, theme] of [['светлая', light], ['тёмная', darkForced]]) {
  test(`тема ${name}: текст и значки читаются на своих фонах`, () => {
    const low = [];
    for (const [fg, bg, min] of PAIRS) {
      const ratio = contrast(theme[fg], theme[bg]);
      if (ratio < min) low.push(`${fg} на ${bg}: ${ratio.toFixed(2)} < ${min}`);
    }
    assert.ok(contrast('#ffffff', theme['--danger-fill']) >= 4.5, 'белый текст на красной кнопке');
    assert.deepEqual(low, []);
  });
}

test('тёмная тема задана одинаково для настройки телефона и для выбора в приложении', () => {
  assert.deepEqual(darkSystem, darkForced);
  assert.deepEqual(Object.keys(darkForced).sort(), Object.keys(light).filter((k) => !/^--(radius|gap|pad|font)/.test(k)).sort(),
    'в тёмной теме переопределены все цвета светлой');
});

test('классы, которые ставит код, описаны в стилях', () => {
  const used = new Set();
  const add = (list) => list.split(/\s+/).filter(Boolean).forEach((name) => used.add(name));
  for (const rel of appFiles().filter((f) => f.startsWith('js/ui/'))) {
    const text = read(rel);
    for (const m of text.matchAll(/class:\s*'([^']+)'/g)) add(m[1]);
    // cx('a', условие && 'b'): все строковые константы внутри скобок
    let from = 0;
    for (;;) {
      const start = text.indexOf('cx(', from);
      if (start < 0) break;
      let depth = 0;
      let end = start + 2;
      for (; end < text.length; end += 1) {
        if (text[end] === '(') depth += 1;
        if (text[end] === ')') {
          depth -= 1;
          if (depth === 0) break;
        }
      }
      for (const m of text.slice(start, end).matchAll(/'([a-z][a-z0-9_ -]*)'/g)) add(m[1]);
      from = end;
    }
  }
  assert.ok(used.size > 80, 'классы из кода найдены');
  const unknown = [...used].filter((name) => !new RegExp(`\\.${name}(?![a-zA-Z0-9_-])`).test(css)).sort();
  assert.deepEqual(unknown, []);
});
