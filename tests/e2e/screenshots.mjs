// Снимки экранов приложения на ширине 390 px в светлой и тёмной теме.
//
//   node tests/e2e/screenshots.mjs [папка] [--width 390] [--scale 2]
//
// Данные на снимках учебные: таблица в памяти с выдуманными числами (tools/fixture.mjs),
// с настоящей таблицей и Google скрипт не связывается. Кроме отдельных экранов делает
// сводный лист на каждую тему: light.png и dark.png.

import fs from 'node:fs';
import path from 'node:path';
import { createRequire } from 'node:module';
import { SKIP, SKIPPED, launch } from './harness.mjs';

if (SKIP) {
  console.error(SKIP);
  process.exit(1);
}

const args = process.argv.slice(2);
const option = (name, fallback) => {
  const index = args.indexOf(`--${name}`);
  return index >= 0 ? Number(args[index + 1]) : fallback;
};
const width = option('width', 390);
const scale = option('scale', 2);
const out = path.resolve(args.find((arg, i) => !arg.startsWith('--') && !(args[i - 1] || '').startsWith('--')) || 'screenshots');
fs.mkdirSync(out, { recursive: true });

const CURL = 'Сгибание ног';
const ROW = 'Тяга сидя широким хватом';
const HACK = 'Гакк-жим';
const WALK = 'Ходьба до и после силовой';

const SCENES = [];
const scene = (id, title, run) => SCENES.push({ id, title, run });

/** Клавиши экранной клавиатуры в открытом листе. */
async function keys(page, value) {
  for (const key of value) await page.locator(`dialog.sheet[open] .key:text-is("${key}")`).click();
}
const press = (page, name) => page.locator('dialog.sheet[open]').getByRole('button', { name, exact: true }).click();
const closed = (page) => page.locator('dialog.sheet').waitFor({ state: 'detached' });
const tab = (page, name) => page.locator('.tab', { hasText: name }).click();
const expand = async (card) => {
  const head = card.locator('.ex__head');
  if ((await head.getAttribute('aria-expanded')) === 'false') await head.click();
  await card.locator('.weight').waitFor();
};
const scrollTo = (page, top) => page.locator('.screen').evaluate((el, y) => {
  el.scrollTop = y === 'end' ? el.scrollHeight : y;
}, top);

scene('01-today', 'Сегодня: пара упражнений, вес и повторы с прошлого раза', async (app) => {
  await app.open();
  await app.page.locator('.day-head').waitFor();
  await app.synced();
});

scene('02-round', 'Круг пары записан: пошёл отдых', async (app) => {
  await app.rep(CURL, 12).click();
  await app.rep(ROW, 12).click();
  await app.page.locator('.timer').waitFor();
  await app.synced();
  await app.tick(20_000);
});

scene('03-weight', 'Ввод веса: своя клавиатура, шаг кнопок «+» и «−»', async (app) => {
  await app.card(ROW).locator('.weight__value').click();
  await keys(app.page, '27,5');
});

scene('04-next-pair', 'Пара закончена: записанное свернулось, открылась следующая', async (app) => {
  const { page } = app;
  await press(page, 'Готово');
  await closed(page);
  await page.locator('.timer').getByRole('button', { name: 'Стоп' }).click();
  await app.rep(CURL, 11).click();
  await app.rep(ROW, 11).click();
  await app.rep(ROW, 10).click();
  await app.synced();
  await page.locator('.timer').getByRole('button', { name: 'Стоп' }).click().catch(() => {});
  await app.tick(600);
});

scene('05-walk', 'Ходьба: отрезки до и после силовой складываются', async (app) => {
  const { page } = app;
  const walk = app.card(WALK);
  await walk.getByRole('button', { name: 'Добавить отрезок' }).click();
  await keys(page, '1,5');
  await press(page, 'Далее');
  await keys(page, '18');
  await press(page, 'Готово');
  await closed(page);
  await app.synced();
  await scrollTo(page, 'end');
  await walk.getByRole('button', { name: 'Добавить отрезок' }).click();
  await keys(page, '1,5');
});

scene('06-offline', 'Нет сети: запись ждёт в очереди', async (app) => {
  const { page, context } = app;
  await press(page, 'Закрыть');
  await closed(page);
  await context.setOffline(true);
  await scrollTo(page, 0);
  await expand(app.card(HACK));
  await app.rep(HACK, 12).click();
  await app.tick(2000);
  await page.locator('.pill', { hasText: 'В очереди' }).waitFor();
  await page.locator('.pill').click();
  await page.locator('dialog.sheet[open] .kv').waitFor();
});

scene('07-plan', 'План: недели программы, сделанное и сегодняшний день', async (app) => {
  const { page, context } = app;
  await press(page, 'Закрыть');
  await closed(page);
  await context.setOffline(false);
  await app.synced();
  await tab(page, 'План');
  await page.locator('.week').first().waitFor();
  await page.locator('.week[aria-current="true"]').evaluate((el) => el.previousElementSibling && el.previousElementSibling.scrollIntoView({ block: 'start' }));
  await app.tick(300);
});

scene('08-other-day', 'Пропущенный день можно записать позже', async (app) => {
  const { page } = app;
  await page.locator(`.day-row[href="#/day/${SKIPPED}"]`).click();
  await page.locator('.banner', { hasText: 'Запись за' }).waitFor();
  await app.tick(300);
});

scene('09-progress', 'Прогресс: неделя и лучший вес по упражнению', async (app) => {
  const { page } = app;
  await tab(page, 'Прогресс');
  await page.locator('.chart svg').first().waitFor();
  await page.locator('.select select').selectOption(CURL);
  await app.tick(300);
  const box = await page.locator('.chart-card').first().locator('.chart svg').boundingBox();
  await page.touchscreen.tap(box.x + box.width * 0.22, box.y + box.height / 2);
  await page.locator('.chart__tip').waitFor();
});

scene('10-progress-walk', 'Прогресс: ходьба по неделям и цель', async (app) => {
  const { page } = app;
  await page.locator('.chart-card').nth(1).evaluate((el) => el.scrollIntoView({ block: 'end' }));
  await app.tick(300);
});

scene('11-settings', 'Настройки: таблица, отдых, шаг веса', async (app) => {
  const { page } = app;
  await tab(page, 'Настройки');
  await page.getByRole('heading', { name: 'Тренировка' }).waitFor();
  await app.tick(300);
});

scene('12-settings-app', 'Настройки: тема, работа без сети, версия', async (app) => {
  await scrollTo(app.page, 'end');
  await app.tick(300);
});

scene('13-connect', 'Первое подключение: адрес скрипта и ключ', async (app) => {
  const { page } = app;
  await page.getByRole('button', { name: 'Отключить таблицу' }).click();
  await press(page, 'Отключить');
  await closed(page);
  await page.getByRole('heading', { name: 'Подключение таблицы' }).waitFor();
  await scrollTo(page, 0);
  await app.tick(3500);
});

scene('14-welcome', 'Первый запуск', async (app) => {
  const { page } = app;
  await tab(page, 'Сегодня');
  await page.getByRole('heading', { name: 'Подключите таблицу' }).waitFor();
  await app.tick(300);
});

async function shoot(scheme) {
  const app = await launch({ scheme, width, scale });
  const files = [];
  try {
    for (const item of SCENES) {
      await item.run(app);
      const file = path.join(out, `${scheme}-${item.id}.png`);
      await app.page.screenshot({ path: file });
      files.push({ ...item, file });
      console.log(`${scheme}: ${item.id}`);
    }
    const problems = app.problems.filter((line) => !/net::ERR_|Failed to load resource/.test(line));
    if (problems.length) console.error(`Ошибки страницы (${scheme}):\n${problems.join('\n')}`);
  } finally {
    await app.close();
  }
  return files;
}

/** Сводный лист: все экраны одной темы на одной картинке, с подписями. */
async function contactSheet(scheme, files) {
  const { chromium } = createRequire(import.meta.url)('playwright');
  const browser = await chromium.launch();
  try {
    const columns = 5;
    const gap = 24;
    const page = await browser.newPage({
      viewport: { width: columns * width + (columns + 1) * gap, height: 800 },
      deviceScaleFactor: scale,
    });
    const dark = scheme === 'dark';
    const cells = files.map((item) => {
      const data = fs.readFileSync(item.file).toString('base64');
      return `<figure><img src="data:image/png;base64,${data}" width="${width}" alt=""><figcaption>${item.title}</figcaption></figure>`;
    }).join('');
    await page.setContent(`<!doctype html><meta charset="utf-8"><style>
      body { margin: 0; padding: ${gap}px; background: ${dark ? '#1c1c1c' : '#e6e4dd'}; color: ${dark ? '#f2f2f2' : '#1a1a1a'};
        font: 15px/1.35 system-ui, sans-serif; display: grid; grid-template-columns: repeat(${columns}, ${width}px); gap: ${gap}px; }
      h1 { grid-column: 1 / -1; margin: 0; font-size: 22px; }
      figure { margin: 0; }
      img { display: block; border-radius: 14px; }
      figcaption { padding: 8px 2px 0; }
    </style><h1>Журнал тренировок · ${width} px · ${dark ? 'тёмная' : 'светлая'} тема · учебные данные</h1>${cells}`);
    await page.screenshot({ path: path.join(out, `${scheme}.png`), fullPage: true });
  } finally {
    await browser.close();
  }
}

for (const scheme of ['light', 'dark']) {
  const files = await shoot(scheme);
  await contactSheet(scheme, files);
}
console.log(`Готово: ${out}`);
