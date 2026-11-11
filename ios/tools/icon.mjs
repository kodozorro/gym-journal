// Рисует значки приложения на Swift из значка веб-приложения (icons/icon.svg).
//
//   node ios/tools/icon.mjs
//
// Нужен Playwright с Chromium, как для сценариев в браузере. Значок iPhone — квадрат без
// скруглений: углы скругляет сама система. На часах значок круглый, поэтому гантель там меньше.

import fs from 'node:fs';
import path from 'node:path';
import { createRequire } from 'node:module';
import { fileURLToPath } from 'node:url';

const ROOT = path.join(path.dirname(fileURLToPath(import.meta.url)), '..', '..');
const SIZE = 1024;

const TARGETS = [
  { file: 'ios/App/Resources/Assets.xcassets/AppIcon.appiconset/icon-1024.png', scale: 1 },
  { file: 'ios/Watch/Resources/Assets.xcassets/AppIcon.appiconset/icon-1024.png', scale: 0.82 },
];

/** Значок веб-приложения без скруглённых углов, с гантелью нужного размера. */
export function iconSvg(source, scale) {
  const fill = /<rect[^>]*fill="(#[0-9a-fA-F]{6})"/.exec(source);
  const glyph = /<g[^>]*>.*<\/g>/s.exec(source);
  if (!fill || !glyph) throw new Error('icons/icon.svg устроен не так, как ждёт скрипт');
  const shift = (256 * (1 - scale)).toFixed(2);
  return `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 512 512" width="${SIZE}" height="${SIZE}">`
    + `<rect width="512" height="512" fill="${fill[1]}"/>`
    + `<g transform="translate(${shift} ${shift}) scale(${scale})">${glyph[0]}</g></svg>`;
}

async function main() {
  const { chromium } = createRequire(import.meta.url)('playwright');
  const source = fs.readFileSync(path.join(ROOT, 'icons/icon.svg'), 'utf8');
  const browser = await chromium.launch();
  try {
    const page = await browser.newPage({ viewport: { width: SIZE, height: SIZE }, deviceScaleFactor: 1 });
    for (const target of TARGETS) {
      await page.setContent(`<body style="margin:0">${iconSvg(source, target.scale)}</body>`);
      const file = path.join(ROOT, target.file);
      fs.mkdirSync(path.dirname(file), { recursive: true });
      await page.screenshot({ path: file, type: 'png', clip: { x: 0, y: 0, width: SIZE, height: SIZE } });
      console.log(`записан: ${target.file}`);
    }
  } finally {
    await browser.close();
  }
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  main().catch((error) => {
    console.error(error.message);
    process.exit(1);
  });
}
