// Общая часть тестов в браузере: приложение со своего сервера, настоящий Code.gs вместо Google.
//
// Запросы к https://script.google.com перехватываются и передаются в doPost скрипта,
// запущенного поверх учебной таблицы в памяти. Страница при этом настоящая, с неизменённой
// политикой безопасности и сервис-воркером: проверяется то же, что уедет на GitHub Pages.

import { createRequire } from 'node:module';
import { createGasEnvironment, loadAppsScript } from '../../tools/gas-fake.mjs';
import { buildSpreadsheet, fillHistory } from '../../tools/fixture.mjs';
import { startServer } from '../../tools/dev-server.mjs';
import { CODE_GS, KEY } from '../helpers.mjs';

export { KEY };
/** Ключ того же вида, что создаёт функция setup: 40 шестнадцатеричных знаков. Учебный. */
export const HEX_KEY = '0123456789abcdef0123456789abcdef01234567';
export const BRIDGE_URL = 'https://script.google.com/macros/s/TESTDEPLOYMENTID_0123456789/exec';
/** Среда недели 3 учебной программы: силовая B и ходьба. */
export const TODAY = '2026-11-25';
export const START = '2026-11-09';
/** Четверг второй недели оставлен пустым: «пропущенный» день. */
export const SKIPPED = '2026-11-19';

let playwright = null;
try {
  playwright = createRequire(import.meta.url)('playwright');
} catch {
  playwright = null;
}

/** Причина пропуска тестов или false. */
export const SKIP = playwright ? false : 'Playwright не найден: тесты в браузере пропущены';

/**
 * @param {object} [options]
 * @param {string} [options.today] дата на часах телефона
 * @param {string} [options.clock] время на часах телефона (по Москве)
 * @param {'light'|'dark'} [options.scheme]
 * @param {number} [options.width]
 * @param {number} [options.scale] плотность пикселей: 2 — для снимков, которые увидит человек
 * @param {boolean} [options.connected] подключение уже сохранено в телефоне
 * @param {boolean} [options.history] прошлые дни заполнены выдуманными числами
 * @param {boolean} [options.sw] отдавать сервис-воркер
 * @param {string} [options.key] ключ, который хранит скрипт
 * @param {string} [options.userAgent] как браузер представляется странице (например, Safari на iPhone)
 */
export async function launch({
  today = TODAY, clock = '07:30:00', scheme = 'light', width = 390, height = 844, scale = 1,
  connected = true, history = true, sw = true, key = KEY, userAgent,
} = {}) {
  const spreadsheet = buildSpreadsheet({ start: START });
  if (history) fillHistory(spreadsheet, { before: today, skip: [SKIPPED] });
  const environment = createGasEnvironment({ spreadsheet, properties: { GJ_KEY: key } });
  const script = loadAppsScript(CODE_GS, environment);
  const server = await startServer({ sw });

  const browser = await playwright.chromium.launch();
  const context = await browser.newContext({
    viewport: { width, height },
    deviceScaleFactor: scale,
    hasTouch: true,
    isMobile: true,
    colorScheme: scheme,
    locale: 'ru-RU',
    timezoneId: 'Europe/Moscow',
    ...(userAgent ? { userAgent } : {}),
  });
  context.setDefaultTimeout(10000);

  /** mode: 'ok' — мостик работает; 'html' — страница входа вместо данных; 'down' — нет связи */
  const bridge = { mode: 'ok', calls: [] };
  await context.route('https://script.google.com/**', async (route) => {
    const request = route.request();
    bridge.calls.push({ method: request.method(), url: request.url(), body: request.postData(), headers: request.headers() });
    if (bridge.mode === 'down') return route.abort('internetdisconnected');
    if (bridge.mode === 'html') return route.fulfill({ status: 200, contentType: 'text/html; charset=utf-8', body: '<!doctype html><title>Вход</title>' });
    if (request.method() !== 'POST') return route.fulfill({ status: 405, contentType: 'text/html', body: '' });
    const out = script.doPost({ postData: { contents: request.postData() || '', type: 'text/plain' } });
    return route.fulfill({
      status: 200,
      contentType: 'application/json; charset=utf-8',
      headers: { 'Access-Control-Allow-Origin': '*' },
      body: out.getContent(),
    });
  });

  const page = await context.newPage();
  const problems = [];
  page.on('pageerror', (err) => problems.push(`ошибка страницы: ${err.message}`));
  page.on('console', (message) => {
    if (message.type() === 'error') problems.push(`консоль: ${message.text()}`);
  });
  await page.clock.install({ time: new Date(`${today}T${clock}+03:00`) });
  if (connected) {
    await page.addInitScript(([url, key]) => {
      if (!window.localStorage.getItem('gj:1:conn')) {
        window.localStorage.setItem('gj:1:conn', JSON.stringify({ url, key }));
        // пояснение о весе уже прочитано: в большинстве тестов оно только мешает
        window.localStorage.setItem('gj:1:settings', JSON.stringify({ weightNoteSeen: true }));
      }
    }, [BRIDGE_URL, key]);
  }

  const app = {
    page,
    context,
    browser,
    server,
    spreadsheet,
    journal: spreadsheet.getSheetByName('Журнал'),
    state: environment.state,
    bridge,
    problems,
    url: server.url,

    async open(hash = '') {
      await page.goto(`${server.url}${hash}`);
      await page.locator('.tabs').waitFor();
    },

    /** Проматывает часы страницы и даёт ей отрисоваться. */
    async tick(ms = 300) {
      await page.clock.runFor(ms);
      await page.waitForTimeout(60);
    },

    /** Ждёт, пока очередь уйдёт в таблицу и приложение покажет «Сохранено». */
    async synced() {
      await page.clock.runFor(1500);
      await page.locator('.pill', { hasText: 'Сохранено' }).waitFor({ timeout: 10000 });
    },

    card(name) {
      return page.locator('.ex', { has: page.locator('.ex__title', { hasText: new RegExp(`^${name}$`) }) });
    },

    rep(name, n) {
      return app.card(name).locator('.rep', { hasText: new RegExp(`^${n}$`) });
    },

    async close() {
      await browser.close();
      await server.close();
    },
  };
  return app;
}
