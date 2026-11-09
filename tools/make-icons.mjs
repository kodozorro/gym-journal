// Рисует значки приложения: icons/icon.svg и PNG нужных размеров.
// Запускается редко, только когда меняется значок: node tools/make-icons.mjs
// Нужен Playwright с Chromium (он же используется в тестах tests/e2e).

import fs from 'node:fs';
import path from 'node:path';
import { createRequire } from 'node:module';
import { fileURLToPath } from 'node:url';

const ROOT = path.join(path.dirname(fileURLToPath(import.meta.url)), '..');
const OUT = path.join(ROOT, 'icons');
const BLUE = '#256abf';

// Гантель из пяти линий. Помещается в «безопасную зону» значка Android (круг 80 % ширины).
const GLYPH = '<g fill="none" stroke="#fff" stroke-width="40" stroke-linecap="round">' +
  '<path d="M176 256h160M160 168v176M352 168v176M104 208v96M408 208v96"/></g>';

const svg = (radius) => '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 512 512">' +
  `<rect width="512" height="512" rx="${radius}" fill="${BLUE}"/>${GLYPH}</svg>\n`;

const TARGETS = [
  { file: 'icon-192.png', size: 192, radius: 112, transparent: true },
  { file: 'icon-512.png', size: 512, radius: 112, transparent: true },
  // маску накладывает сам телефон: фон без скруглений и без прозрачности
  { file: 'icon-maskable-512.png', size: 512, radius: 0, transparent: false },
  { file: 'apple-touch-icon.png', size: 180, radius: 0, transparent: false },
];

fs.mkdirSync(OUT, { recursive: true });
fs.writeFileSync(path.join(OUT, 'icon.svg'), svg(112));

const { chromium } = createRequire(import.meta.url)('playwright');
const browser = await chromium.launch();
try {
  for (const target of TARGETS) {
    const page = await browser.newPage({ viewport: { width: target.size, height: target.size }, deviceScaleFactor: 1 });
    const markup = svg(target.radius).replace('<svg ', `<svg width="${target.size}" height="${target.size}" `);
    await page.setContent(`<!doctype html><style>html,body{margin:0;background:transparent}svg{display:block}</style>${markup}`);
    await page.screenshot({ path: path.join(OUT, target.file), omitBackground: target.transparent });
    await page.close();
    console.log(`icons/${target.file}`);
  }
} finally {
  await browser.close();
}
