// Сценарии в настоящем браузере: приложение целиком, с сервис-воркером и политикой безопасности,
// а вместо Google — настоящий Code.gs поверх учебной таблицы в памяти.
// Названия тестов повторяют критерии приёмки: что должен видеть человек и что должно лечь в таблицу.

import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { BRIDGE_URL, HEX_KEY, SKIP, SKIPPED, TODAY, launch } from './harness.mjs';
import { findRow, journalRows, progressTable, protectedSnapshot, strengthExercises } from '../../tools/fixture.mjs';
import { ROOT, onlyInputCells } from '../helpers.mjs';
import { formatNumber } from '../../js/core/numbers.js';

const options = { skip: SKIP, timeout: 180_000 };
const fmt = (value, digits) => formatNumber(value, digits);

const CURL = 'Сгибание ног';
const ROW = 'Тяга сидя широким хватом';
const HACK = 'Гакк-жим';
const FLY = 'Сведение рук';
const RAISE = 'Разведение рук в стороны';
const WALK = 'Ходьба до и после силовой';

/** Запускает приложение, выполняет сценарий и закрывает браузер, даже если проверка упала. */
async function withApp(settings, scenario) {
  const app = await launch(settings);
  try {
    await scenario(app);
  } catch (err) {
    // GJ_SHOTS=папка — сохранить снимок экрана в момент падения
    if (process.env.GJ_SHOTS) {
      await app.page.screenshot({ path: path.join(process.env.GJ_SHOTS, `fail-${Date.now()}.png`) }).catch(() => {});
    }
    throw err;
  } finally {
    await app.close();
  }
}

/** Повторяет проверку, пока она не пройдёт: экран и таблица обновляются не мгновенно. */
async function eventually(check, timeout = 5000) {
  const deadline = Date.now() + timeout;
  for (;;) {
    try {
      return await check();
    } catch (err) {
      if (Date.now() > deadline) throw err;
      await new Promise((resolve) => setTimeout(resolve, 50));
    }
  }
}

/** Открывает приложение и ждёт, пока появится тренировка. */
async function ready(app, hash = '') {
  await app.open(hash);
  await app.page.locator('.day-head').waitFor();
}

const sheet = (page) => page.locator('dialog.sheet[open]');
const sheetGone = (page) => page.locator('dialog.sheet').waitFor({ state: 'detached' });
const tab = (page, name) => page.locator('.tab', { hasText: name });
const pill = (page, text) => page.locator('.pill', { hasText: text });
const text = async (locator) => ((await locator.textContent()) ?? '').replace(/\s+/g, ' ').trim();
const texts = async (locator) => (await locator.allTextContents()).map((value) => value.replace(/\s+/g, ' ').trim());
const stored = (page, key) => page.evaluate((name) => window.localStorage.getItem(`gj:1:${name}`), key);

/** Нажимает клавиши экранной клавиатуры: «18,75». */
async function keys(page, value) {
  for (const key of value) await sheet(page).locator(`.key:text-is("${key}")`).click();
}

/** Кнопка в открытом листе: «Готово», «Далее», «Стереть», «Сохранить», «Закрыть». */
const press = (page, name) => sheet(page).getByRole('button', { name, exact: true }).click();

/** Раскрывает карточку упражнения, если она свёрнута. */
async function expand(card) {
  const head = card.locator('.ex__head');
  if ((await head.getAttribute('aria-expanded')) === 'false') await head.click();
  await card.locator('.weight').waitFor();
}

/** Ошибки страницы, кроме сетевых: их тесты устраивают нарочно. */
const unexpected = (app) => app.problems.filter((line) => !/net::ERR_|Failed to load resource/.test(line));

/* ------------------------------------------------------------------ */
/* Подключение                                                         */
/* ------------------------------------------------------------------ */

test('первое подключение: адрес и ключ проверяются, план на сегодня приходит из таблицы', options, () => withApp({ connected: false, key: HEX_KEY }, async (app) => {
  const { page, spreadsheet } = app;
  await app.open();
  await page.getByRole('heading', { name: 'Подключите таблицу' }).waitFor();
  assert.match(await text(page.locator('.pill')), /Не подключено/);
  assert.equal(app.bridge.calls.length, 0, 'до подключения приложение никуда не обращается');

  await page.getByRole('link', { name: 'Открыть настройки' }).click();
  await page.getByRole('heading', { name: 'Подключение таблицы' }).waitFor();
  const address = page.getByLabel('Адрес веб-приложения');
  const keyField = page.getByLabel('Ключ', { exact: true });
  const submit = page.getByRole('button', { name: 'Подключить' });

  // тестовый адрес /dev и посторонний сайт отклоняются на месте: ключ никуда не уходит
  await address.fill(BRIDGE_URL.replace(/exec$/, 'dev'));
  await keyField.fill(HEX_KEY);
  await submit.click();
  await page.locator('.field__error', { hasText: '/dev' }).waitFor();
  await address.fill('https://example.com/macros/s/ABCDEFGH12345/exec');
  await submit.click();
  await page.locator('.field__error', { hasText: 'script.google.com' }).waitFor();
  assert.equal(app.bridge.calls.length, 0, 'ключ не уходит на неподходящий адрес');

  // неверный ключ: скрипт отказал, подключение не сохранено
  await address.fill(BRIDGE_URL);
  await keyField.fill('wrong-key');
  await submit.click();
  await page.locator('.field__error', { hasText: 'Ключ не подошёл' }).waitFor();
  assert.equal(await stored(page, 'conn'), null, 'неподтверждённое подключение не сохраняется');

  // адрес и ключ, присланные на телефон одним сообщением, раскладываются по полям
  await address.fill(`Адрес: ${BRIDGE_URL}\nКлюч: ${HEX_KEY}`);
  await eventually(async () => {
    assert.equal(await address.inputValue(), BRIDGE_URL);
    assert.equal(await keyField.inputValue(), HEX_KEY);
  });
  await submit.click();
  await page.locator('.toast', { hasText: 'Таблица подключена' }).waitFor();
  await page.locator('.day-head').waitFor();
  assert.equal(new URL(page.url()).hash, '#/today');
  assert.equal(await text(page.locator('.top__title')), 'Сегодня');
  assert.equal(await text(page.locator('.top__sub')), 'Среда, 25 ноября · неделя 3');

  // тренировка дня — строки листа «Журнал» в том же порядке, парами
  const rows = journalRows(spreadsheet).filter((row) => row.date === TODAY);
  assert.deepEqual(await texts(page.locator('.ex__title')), rows.map((row) => row.exercise));
  assert.equal(await text(page.locator('.day-head__title')), 'Силовая B и ходьба');
  assert.equal(await text(page.locator('.day-head__count')), `0 из ${rows.length}`);
  assert.deepEqual(await texts(page.locator('.group__title')), ['Пара 1', 'Пара 2', 'Пара 3', 'Ходьба']);

  // первая пара раскрыта: план, тренажёр, прошлый раз и вес с прошлого раза
  const last = findRow(spreadsheet, '2026-11-23', CURL);
  const first = app.card(CURL);
  assert.equal(await text(first.locator('.plan-chip')), '2 × 10–12');
  assert.equal(await text(first.locator('.ex__meta')), `${rows[0].machine} · на ногу`);
  assert.equal(await text(first.locator('.ex__last')), `Прошлый раз: ${fmt(last.weight)} кг · ${last.sets.filter((v) => v !== '').join(', ')}, пн 23.11`);
  assert.equal(await text(first.locator('.weight__num')), `${fmt(last.weight)} кг`);
  assert.equal(await text(first.locator('.weight__cap')), 'как в прошлый раз');
  assert.equal(await app.card(ROW).locator('.ex__head').getAttribute('aria-expanded'), 'true');

  // остальные пары свёрнуты и показывают план одной строкой
  const lastHack = findRow(spreadsheet, '2026-11-18', HACK);
  assert.equal(await app.card(HACK).locator('.ex__head').getAttribute('aria-expanded'), 'false');
  assert.equal(await text(app.card(HACK).locator('.ex__summary')), `3 × 10–12 · прошлый раз ${fmt(lastHack.weight)} кг`);

  const lastWalk = findRow(spreadsheet, '2026-11-23', WALK);
  assert.equal(await text(app.card(WALK).locator('.ex__meta')), 'Беговая дорожка · 3 км, наклон 3–4 %');
  assert.equal(await text(app.card(WALK).locator('.ex__last')), `Прошлый раз: ${fmt(lastWalk.km)} км · ${fmt(lastWalk.min)} мин, пн 23.11`);

  // пояснение о том, какой вес записывать, показывается один раз
  const note = page.locator('.banner', { hasText: 'Как записывать вес' });
  await note.waitFor();
  await note.getByRole('button', { name: 'Понятно' }).click();
  await note.waitFor({ state: 'detached' });
  await page.reload();
  await page.locator('.day-head').waitFor();
  assert.equal(await note.count(), 0);

  // к скрипту идут только «простые» POST: без предварительного OPTIONS и без ключа в адресе
  assert.ok(app.bridge.calls.length >= 2);
  for (const call of app.bridge.calls) {
    assert.equal(call.method, 'POST');
    assert.match(call.headers['content-type'], /^text\/plain/);
    assert.equal(call.url, BRIDGE_URL);
    assert.equal(typeof JSON.parse(call.body).key, 'string');
  }
  assert.equal(app.journal.writes.length, 0, 'чтение журнала ничего не пишет в таблицу');
  assert.deepEqual(unexpected(app), []);
}));

test('сброс: приложение забывает адрес, ключ и журнал, таблица не меняется', options, () => withApp({}, async (app) => {
  const { page } = app;
  await ready(app);
  await app.synced();
  await tab(page, 'Настройки').click();
  await page.getByRole('button', { name: 'Отключить таблицу' }).click();
  assert.match(await text(sheet(page)), /В таблице ничего не изменится/);
  await press(page, 'Отмена');
  await sheetGone(page);
  assert.notEqual(await stored(page, 'conn'), null, 'отмена ничего не стирает');

  await page.getByRole('button', { name: 'Отключить таблицу' }).click();
  await press(page, 'Отключить');
  await page.getByRole('heading', { name: 'Подключение таблицы' }).waitFor();
  assert.equal(await stored(page, 'conn'), null);
  assert.equal(await stored(page, 'snapshot'), null);
  assert.equal(await stored(page, 'outbox'), null);
  await tab(page, 'Сегодня').click();
  await page.getByRole('heading', { name: 'Подключите таблицу' }).waitFor();
  assert.equal(app.journal.writes.length, 0);
  assert.deepEqual(unexpected(app), []);
}));

test('iPhone: в Safari приложение просит поставить его на экран «Домой», без вибрации и удержания экрана работает', options, async () => {
  const IPHONE = 'Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1';
  const warning = 'Сначала поставьте приложение на экран «Домой»';

  // вкладка Safari: у значка на экране будет своё хранилище, поэтому подключать таблицу здесь рано
  await withApp({ connected: false, userAgent: IPHONE }, async (app) => {
    const { page } = app;
    await app.open('#/settings');
    await page.locator('.banner', { hasText: warning }).waitFor();
    await page.getByText('нажмите «Поделиться», затем «На экран „Домой“»').waitFor();
    assert.deepEqual(unexpected(app), []);
  });

  // запуск со значка: предупреждения нет; вибрации и удержания экрана у телефона нет, отдых всё равно виден
  await withApp({ userAgent: IPHONE }, async (app) => {
    const { page } = app;
    await page.addInitScript(() => {
      Object.defineProperty(Navigator.prototype, 'standalone', { get: () => true, configurable: true });
      delete Navigator.prototype.vibrate;
      delete Navigator.prototype.wakeLock;
    });
    await ready(app);
    await app.rep(CURL, 12).click();
    await app.rep(ROW, 12).click();
    await page.locator('.timer').waitFor();
    await app.tick(91_000);
    await page.locator('.timer--over').waitFor();
    await app.synced();
    assert.deepEqual(findRow(app.spreadsheet, TODAY, CURL).sets, [12, '', '']);

    await tab(page, 'Настройки').click();
    await page.getByRole('switch', { name: 'Звук в конце отдыха' }).waitFor();
    assert.equal(await page.getByRole('switch', { name: 'Вибрация в конце отдыха' }).count(), 0);
    await page.getByText('Этот телефон не даёт приложению держать экран включённым.').waitFor();
    await page.getByRole('button', { name: 'Изменить', exact: true }).click();
    await page.getByRole('heading', { name: 'Новое подключение' }).waitFor();
    assert.equal(await page.locator('.banner', { hasText: warning }).count(), 0);
    assert.equal(await page.getByText('нажмите «Поделиться»').count(), 0);
    assert.deepEqual(unexpected(app), []);
  });
});

test('телефон не даёт хранилище: приложение работает и предупреждает, что записи не переживут закрытие', options, () => withApp({ connected: false, key: HEX_KEY }, async (app) => {
  const { page, spreadsheet } = app;
  await page.addInitScript(() => {
    Storage.prototype.setItem = () => {
      throw new DOMException('Нет места', 'QuotaExceededError');
    };
  });
  await app.open('#/settings');
  await page.getByLabel('Адрес веб-приложения').fill(`${BRIDGE_URL} ${HEX_KEY}`);
  await page.getByRole('button', { name: 'Подключить' }).click();
  await page.locator('.day-head').waitFor();
  await page.locator('.banner', { hasText: 'Телефон не даёт сохранять данные' }).waitFor();
  await app.rep(CURL, 12).click();
  await app.synced();
  assert.deepEqual(findRow(spreadsheet, TODAY, CURL).sets, [12, '', '']);
  assert.deepEqual(unexpected(app), []);
}));

/* ------------------------------------------------------------------ */
/* Запись тренировки                                                   */
/* ------------------------------------------------------------------ */

test('запись: вес, повторы, ходьба и заметка попадают в свои ячейки листа «Журнал»', options, () => withApp({}, async (app) => {
  const { page, spreadsheet, journal } = app;
  const before = protectedSnapshot(spreadsheet);
  const cells = (exercise) => findRow(spreadsheet, TODAY, exercise);
  await ready(app);

  // одно касание числа: повторы уходят в первый подход, вес берётся с прошлого раза
  const lastCurl = findRow(spreadsheet, '2026-11-23', CURL);
  await app.rep(CURL, 12).click();
  assert.equal(await text(app.card(CURL).locator('.set__value').first()), '12');
  await app.synced();
  assert.equal(cells(CURL).weight, lastCurl.weight);
  assert.deepEqual(cells(CURL).sets, [12, '', '']);
  assert.equal(await text(app.card(CURL).locator('.weight__cap')), 'шаг 2,5 кг');

  // кнопка «+» прибавляет шаг к весу с прошлого раза
  const lastRow = findRow(spreadsheet, '2026-11-18', ROW);
  await app.card(ROW).getByRole('button', { name: /^Прибавить вес/ }).click();
  await app.synced();
  assert.equal(cells(ROW).weight, lastRow.weight + 2.5);
  await app.card(ROW).getByRole('button', { name: /^Убавить вес/ }).click();
  await app.synced();
  assert.equal(cells(ROW).weight, lastRow.weight);

  // «Другое»: повторы с клавиатуры приложения, лишние знаки не принимаются
  await app.card(ROW).getByRole('button', { name: 'Другое' }).click();
  await keys(page, '9');
  assert.equal(await sheet(page).locator('.key:text-is(",")').isDisabled(), true, 'повторы — только целое число');
  assert.equal(await text(sheet(page).locator('.display__value')), '9 повт.');
  await press(page, 'Готово');
  await app.synced();
  assert.deepEqual(cells(ROW).sets, [9, '', '']);

  // вес с десятичной запятой
  await app.card(CURL).locator('.weight__value').click();
  assert.match(await text(sheet(page)), /Вес, как он выставлен на тренажёре/);
  await keys(page, '18,759');
  assert.equal(await text(sheet(page).locator('.display__value')), '18,75 кг');
  await press(page, 'Готово');
  await app.synced();
  assert.equal(cells(CURL).weight, 18.75);

  // слишком большое число не записывается
  await app.card(ROW).locator('.weight__value').click();
  await keys(page, '1001');
  await press(page, 'Готово');
  assert.equal(await text(sheet(page).locator('.display__error')), 'Не больше 1000.');
  await press(page, 'Закрыть');
  await sheetGone(page);
  assert.equal(cells(ROW).weight, lastRow.weight);

  // записанный подход можно стереть: два касания ячейки, «Стереть»
  const firstSet = app.card(CURL).locator('.set').first();
  await firstSet.click();
  await firstSet.click();
  await press(page, 'Стереть');
  await app.synced();
  assert.deepEqual(cells(CURL).sets, ['', '', '']);
  assert.equal(cells(CURL).weight, 18.75, 'вес при этом остаётся');

  // третий подход сверх плана
  await app.card(CURL).getByRole('button', { name: 'Добавить подход' }).click();
  await app.rep(CURL, 10).click();
  await app.synced();
  assert.deepEqual(cells(CURL).sets, ['', '', 10]);

  // ходьба: два отрезка складываются, итог можно поправить
  const walk = app.card(WALK);
  await walk.getByRole('button', { name: 'Добавить отрезок' }).click();
  await keys(page, '1');
  await press(page, 'Далее');
  await keys(page, '12');
  await press(page, 'Готово');
  await sheetGone(page);
  await walk.getByRole('button', { name: 'Добавить отрезок' }).click();
  assert.match(await text(sheet(page)), /Прибавится к записанному: 1 км · 12 мин/);
  await keys(page, '2');
  await press(page, 'Далее');
  await keys(page, '26');
  await press(page, 'Готово');
  await app.synced();
  assert.equal(cells(WALK).km, 3);
  assert.equal(cells(WALK).min, 38);
  await walk.getByRole('button', { name: /^Минуты/ }).click();
  await keys(page, '40');
  await press(page, 'Готово');
  await app.synced();
  assert.equal(cells(WALK).km, 3);
  assert.equal(cells(WALK).min, 40);
  assert.equal(await text(walk.locator('.walk__pace')), 'Темп 13:20 мин/км · 4,5 км/ч');

  // заметка остаётся текстом, даже если похожа на формулу
  await app.card(CURL).locator('.note-btn').click();
  await sheet(page).locator('textarea').fill('=SUM(1;2)');
  await press(page, 'Сохранить');
  await app.synced();
  assert.equal(cells(CURL).note, '=SUM(1;2)');
  assert.equal(await text(app.card(CURL).locator('.note-btn')), '=SUM(1;2)');

  // таблица: тронуты только ячейки ввода сегодняшних строк, остальное как было
  assert.deepEqual(onlyInputCells(spreadsheet), [], 'скрипт писал только в столбцы E–J и L');
  assert.equal(protectedSnapshot(spreadsheet), before, 'формулы, заголовки и структура не тронуты');
  const todayRows = new Set(journalRows(spreadsheet).filter((row) => row.date === TODAY).map((row) => row.row));
  assert.ok(journal.writes.length > 0);
  assert.ok(journal.writes.every((write) => todayRows.has(write.row)), 'записи только в строках сегодняшнего дня');

  // «Прогресс» показывает то же, что посчитали бы формулы листа «Прогресс»
  await tab(page, 'Прогресс').click();
  const table = progressTable(spreadsheet);
  const week = table.find((item) => item.week === 3);
  await eventually(async () => assert.equal(await text(page.locator('.tile__value').first()), `${fmt(week.km)} из 17 км`));
  await page.locator('.select select').selectOption(CURL);
  const weights = page.locator('.chart-card').first();
  await weights.locator('summary').click();
  await eventually(async () => {
    const got = await weights.locator('tbody tr').evaluateAll((trs) => trs.map((tr) => [...tr.cells].map((td) => td.textContent)));
    assert.deepEqual(
      got.map(([title, value]) => [Number(/неделя (\d+)/.exec(title)[1]), value]),
      table.filter((item) => item.best[CURL]).map((item) => [item.week, fmt(item.best[CURL])]),
    );
  });
  assert.equal(week.best[CURL], 18.75);
  assert.deepEqual(unexpected(app), []);
}));

test('правки в таблице видны после обновления; подсказка о прибавке веса', options, () => withApp({}, async (app) => {
  const { page, spreadsheet, journal } = app;
  await ready(app);
  await app.synced();

  // человек правит таблицу руками: сегодняшний план, запись за сегодня и прошлую тренировку
  const today = findRow(spreadsheet, TODAY, HACK);
  const last = findRow(spreadsheet, '2026-11-18', HACK);
  const fly = findRow(spreadsheet, TODAY, FLY);
  journal.manualEdit(today.row, 4, '3 × 6–8');
  journal.manualEdit(last.row, 6, 15);
  journal.manualEdit(last.row, 7, 15);
  journal.manualEdit(fly.row, 5, 17.5);
  journal.manualEdit(fly.row, 6, 13);

  await page.locator('.pill').click();
  await press(page, 'Обновить');
  await eventually(async () => assert.match(await text(sheet(page)), /Все записи в таблице/));
  await press(page, 'Закрыть');
  await sheetGone(page);

  await eventually(async () => assert.equal(await text(app.card(FLY).locator('.ex__summary')), '17,5 кг · 13'));
  await expand(app.card(HACK));
  assert.equal(await text(app.card(HACK).locator('.plan-chip')), '3 × 6–8');
  assert.equal(await text(app.card(HACK).locator('.ex__last')), `Прошлый раз: ${fmt(last.weight)} кг · 15, 15, ср 18.11`);

  // в прошлый раз все подходы дошли до верхней границы: приложение предлагает прибавить шаг
  const hint = app.card(HACK).locator('.hint');
  assert.match(await text(hint), /все подходы дошли до 15/);
  const offer = `Взять ${fmt(last.weight + 2.5)} кг`;
  await hint.getByRole('button', { name: offer }).waitFor();

  // подсказку можно отключить в настройках
  await tab(page, 'Настройки').click();
  await page.getByRole('switch', { name: 'Подсказка о прибавке веса' }).click();
  await tab(page, 'Сегодня').click();
  await expand(app.card(HACK));
  assert.equal(await hint.count(), 0);
  await tab(page, 'Настройки').click();
  await page.getByRole('switch', { name: 'Подсказка о прибавке веса' }).click();
  await tab(page, 'Сегодня').click();
  await expand(app.card(HACK));
  await hint.getByRole('button', { name: offer }).click();
  await app.synced();
  assert.equal(findRow(spreadsheet, TODAY, HACK).weight, last.weight + 2.5);
  assert.equal(await hint.count(), 0, 'после выбора веса подсказка не нужна');
  assert.deepEqual(onlyInputCells(spreadsheet), []);
  assert.deepEqual(unexpected(app), []);
}));

/* ------------------------------------------------------------------ */
/* Без сети                                                            */
/* ------------------------------------------------------------------ */

test('без сети: приложение открывается, записи ждут в очереди и уходят, когда сеть вернулась', options, () => withApp({}, async (app) => {
  const { page, context, spreadsheet, journal } = app;
  await ready(app);
  await app.synced();
  await page.evaluate(() => navigator.serviceWorker.ready.then(() => true));
  await page.reload();
  await page.locator('.day-head').waitFor();
  assert.equal(await page.evaluate(() => Boolean(navigator.serviceWorker.controller)), true, 'страницу ведёт сервис-воркер');

  // сети нет: приложение открывается из телефона и показывает сохранённый журнал
  await context.setOffline(true);
  await page.reload();
  await page.locator('.day-head').waitFor();
  await pill(page, 'Нет сети').waitFor();
  assert.deepEqual(await texts(page.locator('.ex__title')), journalRows(spreadsheet).filter((row) => row.date === TODAY).map((row) => row.exercise));

  await app.rep(CURL, 12).click();
  await app.tick(2000);
  await pill(page, 'В очереди: 1').waitFor();
  await app.card(CURL).locator('.unsent').waitFor();
  assert.equal(journal.writes.length, 0);

  // приложение закрыли и открыли снова, сети всё ещё нет: запись на месте
  await page.reload();
  await page.locator('.day-head').waitFor();
  await pill(page, 'В очереди: 1').waitFor();
  assert.equal(await text(app.card(CURL).locator('.set__value').first()), '12');
  await page.locator('.pill').click();
  assert.match(await text(sheet(page)), /Нет сети\. Записи сохранены в телефоне и уйдут в таблицу, когда сеть появится/);
  await press(page, 'Закрыть');
  await sheetGone(page);
  await app.rep(ROW, 11).click();
  await pill(page, 'В очереди: 2').waitFor();

  // сеть вернулась: очередь уходит сама
  await context.setOffline(false);
  await app.synced();
  const lastCurl = findRow(spreadsheet, '2026-11-23', CURL);
  assert.deepEqual(findRow(spreadsheet, TODAY, CURL).sets, [12, '', '']);
  assert.equal(findRow(spreadsheet, TODAY, CURL).weight, lastCurl.weight);
  assert.deepEqual(findRow(spreadsheet, TODAY, ROW).sets, [11, '', '']);
  assert.equal(await app.card(CURL).locator('.unsent').count(), 0);
  assert.deepEqual(onlyInputCells(spreadsheet), []);
  assert.deepEqual(unexpected(app), []);
}));

test('сбои связи и таблицы: запись не теряется, причина названа, после исправления всё доходит', options, () => withApp({}, async (app) => {
  const { page, spreadsheet, journal, bridge } = app;
  const cells = (exercise) => findRow(spreadsheet, TODAY, exercise);
  await ready(app);
  await app.synced();

  // ключ в таблице сменили (resetKey): приложение просит настройку и держит запись у себя
  app.state.props.set('GJ_KEY', HEX_KEY);
  await app.rep(CURL, 12).click();
  await app.tick(1500);
  await pill(page, 'Нужна настройка').waitFor();
  const alert = page.locator('.banner', { hasText: 'Ключ не подходит' });
  await alert.waitFor();
  await app.card(CURL).locator('.unsent').waitFor();
  assert.equal(journal.writes.length, 0);
  await alert.getByRole('link', { name: 'Открыть настройки' }).click();
  await page.getByRole('button', { name: 'Изменить', exact: true }).click();
  await page.getByLabel('Адрес веб-приложения').fill(`${BRIDGE_URL} ${HEX_KEY}`);
  await page.getByRole('button', { name: 'Подключить' }).click();
  await page.locator('.toast', { hasText: 'Таблица подключена' }).waitFor();
  await page.locator('.day-head').waitFor();
  await app.synced();
  assert.deepEqual(cells(CURL).sets, [12, '', '']);

  // вместо данных пришла страница (доступ к развёртыванию закрыт): запись ждёт, приложение повторяет само
  bridge.mode = 'html';
  await app.rep(ROW, 12).click();
  await app.tick(1500);
  await page.locator('.banner', { hasText: 'Скрипт ответил страницей вместо данных' }).waitFor();
  await pill(page, 'В очереди: 1').waitFor();
  bridge.mode = 'ok';
  await app.tick(6000);
  await app.synced();
  assert.deepEqual(cells(ROW).sets, [12, '', '']);
  assert.equal(await page.locator('.banner', { hasText: 'Скрипт ответил страницей' }).count(), 0);

  // сеть есть, а скрипт недоступен
  bridge.mode = 'down';
  await app.rep(CURL, 11).click();
  await app.tick(1500);
  await pill(page, 'В очереди: 1').waitFor();
  await page.locator('.pill').click();
  await eventually(async () => assert.match(await text(sheet(page)), /Нет связи со скриптом таблицы\. Записи сохранены в телефоне\. Следующая попытка через \d+ с\./));
  await press(page, 'Закрыть');
  await sheetGone(page);
  bridge.mode = 'ok';
  await app.tick(6000);
  await app.synced();
  assert.deepEqual(cells(CURL).sets, [12, 11, '']);

  // в таблице переименовали столбец: скрипт отказывается писать, чтобы ничего не испортить
  const writesBefore = journal.writes.length;
  journal.manualEdit(2, 5, 'Вес');
  await app.rep(ROW, 11).click();
  await app.tick(1500);
  await page.locator('.banner', { hasText: 'Лист «Журнал» изменился' }).waitFor();
  await pill(page, 'Нужна настройка').waitFor();
  assert.equal(journal.writes.length, writesBefore);
  journal.manualEdit(2, 5, 'Вес, кг');
  await page.locator('.pill').click();
  await press(page, 'Обновить');
  await press(page, 'Закрыть');
  await sheetGone(page);
  await app.synced();
  assert.deepEqual(cells(ROW).sets, [12, 11, '']);

  // строку убрали из таблицы, пока запись ждала: приложение показывает, что не записалось
  const victim = cells(RAISE);
  journal.manualEdit(victim.row, 3, 'Махи в стороны');
  await expand(app.card(RAISE));
  await app.rep(RAISE, 14).click();
  await app.tick(1500);
  await pill(page, 'Не записано: 1').waitFor();
  await page.locator('.banner', { hasText: 'Не записано: 1' }).getByRole('button', { name: 'Посмотреть' }).click();
  const item = sheet(page).locator('.failed li');
  assert.match(await text(item), /ср 25\.11 · Разведение рук в стороны: .*подходы 14.*В журнале нет строки с такой датой и упражнением/);
  await item.getByRole('button', { name: 'Убрать' }).click();
  await press(page, 'Закрыть');
  await sheetGone(page);
  await pill(page, 'Сохранено').waitFor();
  await app.card('Махи в стороны').waitFor();
  assert.deepEqual(findRow(spreadsheet, TODAY, 'Махи в стороны').sets, ['', '', '']);
  assert.deepEqual(onlyInputCells(spreadsheet), []);
  assert.deepEqual(unexpected(app), []);
}));

/* ------------------------------------------------------------------ */
/* Таймер отдыха                                                       */
/* ------------------------------------------------------------------ */

test('таймер отдыха: запускается после круга пары, считает по часам и переживает перезапуск', options, () => withApp({}, async (app) => {
  const { page } = app;
  const timer = page.locator('.timer');
  const clock = page.locator('.timer__clock');
  /** Сколько секунд осталось на табло. Часы страницы идут сами, поэтому сверяем с запасом. */
  const left = async () => {
    const [min, sec] = (await text(clock)).split(':').map(Number);
    return min * 60 + sec;
  };
  const between = (value, low, high) => assert.ok(value >= low && value <= high, `${value} не в пределах ${low}…${high}`);
  await ready(app);

  await app.rep(CURL, 12).click();
  await app.tick(300);
  assert.equal(await timer.count(), 0, 'круг не закончен: у соседа по паре подход не записан');
  await app.rep(ROW, 12).click();
  await timer.waitFor();
  assert.equal(await text(page.locator('.timer__label')), 'Отдых');
  between(await left(), 80, 90);

  await timer.getByRole('button', { name: '+30 с' }).click();
  await eventually(async () => between(await left(), 110, 120));
  await app.tick(100_000);
  const before = await left();
  between(before, 5, 20);

  // приложение закрыли и открыли: отсчёт идёт по часам, а не с начала
  await page.reload();
  await timer.waitFor();
  between(await left(), 1, before);

  await app.tick(25_000);
  await page.locator('.timer--over').waitFor();
  assert.equal(await text(page.locator('.timer__label')), 'Отдых окончен');
  assert.match(await text(clock), /^\+0:0\d$/);
  assert.equal(await timer.getByRole('button', { name: '+30 с' }).count(), 0);
  await timer.getByRole('button', { name: 'Закрыть' }).click();
  await timer.waitFor({ state: 'detached' });
  assert.equal(await stored(page, 'timer'), null);

  // запуск вручную и остановка
  await page.locator('.rest-btn').click();
  await timer.waitFor();
  await timer.getByRole('button', { name: 'Стоп' }).click();
  await timer.waitFor({ state: 'detached' });

  // длительность и автозапуск настраиваются
  await tab(page, 'Настройки').click();
  await page.getByRole('button', { name: 'Больше отдыха' }).click();
  assert.equal(await text(page.locator('.stepper output')), '1:45');
  await page.getByRole('switch', { name: 'Автозапуск отдыха' }).click();
  await tab(page, 'Сегодня').click();
  assert.equal(await text(page.locator('.rest-btn')), 'Отдых 1:45');
  await app.rep(CURL, 11).click();
  await app.rep(ROW, 11).click();
  await app.tick(500);
  assert.equal(await timer.count(), 0, 'автозапуск выключен');
  await page.locator('.rest-btn').click();
  await timer.waitFor();
  between(await left(), 95, 105);
  assert.deepEqual(unexpected(app), []);
}));

/* ------------------------------------------------------------------ */
/* Другие дни и план                                                   */
/* ------------------------------------------------------------------ */

test('другой день: тренировку можно записать не в свой день, пропуск — не ошибка', options, () => withApp({}, async (app) => {
  const { page, spreadsheet } = app;
  const friday = '2026-11-27';
  await app.open('#/plan');
  await page.locator('.week').first().waitFor();
  await app.synced();

  // план: все недели, текущая на экране, сегодняшний день отмечен, пропущенный ничем не выделен
  assert.equal(await page.locator('.week').count(), 12);
  assert.equal(await text(page.locator('.week[aria-current="true"] .week__title')), 'Неделя 323–27 ноя');
  const todayRow = page.locator('.day-row--today');
  assert.equal(await todayRow.getAttribute('href'), '#/today');
  assert.match(await text(todayRow), /ср 25\.11.*Силовая B и ходьба.*сегодня/);
  const skipped = page.locator(`.day-row[href="#/day/${SKIPPED}"]`);
  assert.equal(await skipped.locator('.status--none').count(), 1);
  assert.equal(await page.getByText(/пропущен/i).count(), 0);
  assert.equal(await page.locator(`.day-row[href="#/day/2026-11-23"] .status--done`).count(), 1);

  // будущий день: записать можно, но таймер включается только по кнопке «Делаю сегодня»
  await page.locator(`.day-row[href="#/day/${friday}"]`).click();
  await page.locator('.day-head').waitFor();
  assert.equal(await text(page.locator('.top__title')), '27 ноября');
  assert.equal(await text(page.locator('.top__sub')), 'Пятница · неделя 3');
  const banner = page.locator('.banner', { hasText: 'План на пт 27.11' });
  assert.match(await text(banner), /Сегодня ср 25\.11/);
  await app.rep('Жим ногами', 12).click();
  await app.rep('Тяга сидя узким хватом', 12).click();
  await app.tick(500);
  assert.equal(await page.locator('.timer').count(), 0);

  await banner.getByRole('button', { name: 'Делаю сегодня' }).click();
  await page.locator('.banner', { hasText: 'Тренировка за пт 27.11 идёт сегодня. В заметке отмечено: сделано 25.11.' }).waitFor();
  await app.synced();
  assert.equal(findRow(spreadsheet, friday, 'Жим ногами').note, 'сделано 25.11');
  assert.deepEqual(findRow(spreadsheet, friday, 'Жим ногами').sets, [12, '', '']);
  await app.rep('Жим ногами', 11).click();
  await app.rep('Тяга сидя узким хватом', 11).click();
  await page.locator('.timer').waitFor();
  await page.locator('.timer').getByRole('button', { name: 'Стоп' }).click();

  // отметка «делаю сегодня» держится до конца дня
  await page.reload();
  await page.locator('.banner', { hasText: 'идёт сегодня' }).waitFor();

  // назад к плану: день отмечен как начатый
  await page.getByRole('link', { name: 'К плану' }).click();
  await page.locator('.week').first().waitFor();
  assert.match(await text(page.locator(`.day-row[href="#/day/${friday}"]`)), /частично/);

  // пропущенный день дозаписывается позже; дату можно поставить в заметку одним касанием
  await tab(page, 'Сегодня').click();
  const late = page.locator('.linklist', { hasText: 'Не записано раньше' });
  await late.locator(`.day-row[href="#/day/${SKIPPED}"]`).click();
  await page.locator('.banner', { hasText: 'Запись за чт 19.11' }).waitFor();
  const walk = app.card('Ходьба или интервалы');
  await walk.getByRole('button', { name: 'Добавить отрезок' }).click();
  await keys(page, '4,2');
  await press(page, 'Далее');
  await keys(page, '50');
  await press(page, 'Готово');
  await sheetGone(page);
  await walk.locator('.note-btn').click();
  await sheet(page).locator('.chip', { hasText: 'сделано 25.11' }).click();
  await eventually(async () => assert.equal(await sheet(page).locator('textarea').inputValue(), 'сделано 25.11'));
  await press(page, 'Сохранить');
  await app.synced();
  const filled = findRow(spreadsheet, SKIPPED, 'Ходьба или интервалы');
  assert.equal(filled.km, 4.2);
  assert.equal(filled.min, 50);
  assert.equal(filled.note, 'сделано 25.11');
  await tab(page, 'Сегодня').click();
  await page.locator('.top__title', { hasText: 'Сегодня' }).waitFor();
  await page.locator('.day-head').waitFor();
  assert.equal(await page.locator('.linklist', { hasText: 'Не записано раньше' }).count(), 0);
  assert.deepEqual(onlyInputCells(spreadsheet), []);
  assert.deepEqual(unexpected(app), []);
}));

test('план: при возврате со дня список остаётся на том же месте', options, () => withApp({}, async (app) => {
  const { page } = app;
  await app.open('#/plan');
  await page.locator('.week').first().waitFor();
  const scrollTop = () => page.locator('.screen').evaluate((el) => Math.round(el.scrollTop));
  assert.ok(await scrollTop() > 0, 'текущая неделя прокручена к началу экрана');
  await page.locator('.screen').evaluate((el) => {
    el.scrollTop = el.scrollHeight;
  });
  const bottom = await scrollTop();
  await page.locator('.week').last().locator('.day-row').last().click();
  await page.locator('.day-head').waitFor();
  await page.getByRole('link', { name: 'К плану' }).click();
  await page.locator('.week').first().waitFor();
  await eventually(async () => assert.equal(await scrollTop(), bottom));
  assert.deepEqual(unexpected(app), []);
}));

test('«сегодня» считается по часам телефона: день отдыха, полночь, до начала и после конца программы', options, async () => {
  // вторник, без двух минут полночь по Москве; таблица живёт в другом часовом поясе
  await withApp({ today: '2026-11-24', clock: '23:58:00' }, async (app) => {
    const { page } = app;
    await ready(app);
    assert.equal(await text(page.locator('.top__sub')), 'Вторник, 24 ноября · неделя 3');
    assert.equal(await text(page.locator('.day-head__title')), 'Ходьба');
    assert.deepEqual(await texts(page.locator('.ex__title')), ['Ходьба ровным темпом']);
    await app.tick(3 * 60 * 1000);
    await eventually(async () => assert.equal(await text(page.locator('.top__sub')), 'Среда, 25 ноября · неделя 3'));
    assert.equal(await text(page.locator('.day-head__title')), 'Силовая B и ходьба');
    assert.deepEqual(unexpected(app), []);
  });

  // понедельник до первой строки журнала
  await withApp({ today: '2026-11-09', history: false }, async (app) => {
    const { page } = app;
    await app.open();
    await page.getByRole('heading', { name: 'Программа ещё не началась' }).waitFor();
    assert.match(await text(page.locator('.linklist')), /Первая тренировка: вторник, 10 ноября.*Следующая тренировка.*вт 10\.11/);
  });

  // суббота: день отдыха, показана следующая тренировка
  await withApp({ today: '2026-11-28' }, async (app) => {
    const { page } = app;
    await app.open();
    await page.getByRole('heading', { name: 'Сегодня тренировки нет' }).waitFor();
    assert.match(await text(page.locator('.linklist').first()), /По плану день отдыха.*Следующая тренировка.*пн 30\.11/);
  });

  // после последней недели
  await withApp({ today: '2027-02-03', history: false }, async (app) => {
    const { page } = app;
    await app.open();
    await page.getByRole('heading', { name: 'Программа закончилась' }).waitFor();
  });
});

/* ------------------------------------------------------------------ */
/* Прогресс                                                            */
/* ------------------------------------------------------------------ */

test('прогресс: плитки, графики и таблицы совпадают с расчётом листа «Прогресс»', options, () => withApp({}, async (app) => {
  const { page, spreadsheet } = app;
  await app.open('#/progress');
  await page.locator('.chart svg').first().waitFor();
  await app.synced();
  const table = progressTable(spreadsheet);
  const week = table.find((item) => item.week === 3);

  assert.equal(await text(page.locator('.top__sub')), 'Неделя 3 из 12');
  assert.equal(await text(page.locator('.tile__value').nth(0)), `${fmt(week.km)} из 17 км`);
  assert.equal(await text(page.locator('.tile__value').nth(1)), '2 из 5');

  // упражнения — из журнала, графика без легенды: один ряд, подписана последняя точка
  const names = await texts(page.locator('.select option'));
  assert.deepEqual([...names].sort(), [...strengthExercises()].sort());
  const weights = page.locator('.chart-card').nth(0);
  const walks = page.locator('.chart-card').nth(1);

  for (const name of [names[0], HACK]) {
    await page.locator('.select select').selectOption(name);
    const expected = table.filter((item) => item.best[name]).map((item) => [item.week, fmt(item.best[name])]);
    await eventually(async () => {
      assert.equal(await weights.locator('.chart__dot').count(), expected.length);
      assert.equal(await text(weights.locator('.chart__label')), `${expected[expected.length - 1][1]} кг`);
    });
    const label = await weights.locator('.chart svg').getAttribute('aria-label');
    assert.equal(label, `Лучший вес по неделям, ${name}: ${expected.map(([w, v]) => `неделя ${w}: ${v} кг`).join(', ')}`);
  }

  // выбранное упражнение запоминается
  await page.reload();
  await page.locator('.chart svg').first().waitFor();
  assert.equal(await page.locator('.select select').inputValue(), HACK);

  // касание графика показывает значение и неделю
  const box = await weights.locator('.chart svg').boundingBox();
  await page.touchscreen.tap(box.x + 50, box.y + box.height / 2);
  const tip = weights.locator('.chart__tip');
  await tip.waitFor();
  assert.match(await text(tip), /^\d+(,\d+)? кгнеделя 1 · 10–13 ноя$/);
  await weights.locator('.chart svg').press('ArrowRight');
  await eventually(async () => assert.match(await text(tip), /неделя 2 · 16–20 ноя$/));
  await weights.locator('.chart svg').press('Escape');
  await tip.waitFor({ state: 'detached' });

  // ходьба: столбцы по неделям, линия цели, таблица с теми же числами
  const walked = table.filter((item) => item.km > 0);
  assert.equal(await walks.locator('.chart__bar').count(), walked.length);
  assert.equal(await text(walks.locator('.chart__note')), 'цель 17 км');
  await walks.locator('summary').click();
  const rows = await walks.locator('tbody tr').evaluateAll((trs) => trs.map((tr) => [...tr.cells].map((td) => td.textContent)));
  assert.deepEqual(
    rows.map(([title, km, min]) => [Number(/неделя (\d+)/.exec(title)[1]), km, min]),
    walked.map((item) => [item.week, fmt(item.km), fmt(item.min, 0)]),
  );
  assert.deepEqual(unexpected(app), []);
}));

/* ------------------------------------------------------------------ */
/* Вёрстка и темы                                                      */
/* ------------------------------------------------------------------ */

// Выполняется в странице: что вылезает за край экрана и во что трудно попасть пальцем.
function audit(minTarget) {
  const width = document.documentElement.clientWidth;
  const height = window.innerHeight;
  const name = (el, box) => {
    const cls = typeof el.className === 'string' && el.className ? `.${el.className.trim().split(/\s+/).join('.')}` : '';
    const label = (el.getAttribute('aria-label') || el.textContent || '').trim().replace(/\s+/g, ' ').slice(0, 30);
    return `${el.tagName.toLowerCase()}${cls} ${Math.round(box.width)}×${Math.round(box.height)} «${label}»`;
  };
  const out = { overflow: [], small: [], scroll: [] };
  if (document.documentElement.scrollWidth > width) out.scroll.push(`страница ${document.documentElement.scrollWidth} > ${width}`);
  const screen = document.querySelector('.screen');
  if (screen && screen.scrollWidth > screen.clientWidth) out.scroll.push(`экран ${screen.scrollWidth} > ${screen.clientWidth}`);
  const dialog = document.querySelector('dialog.sheet[open]');
  if (dialog) {
    const box = dialog.getBoundingClientRect();
    if (box.top < -0.5 || box.bottom > height + 0.5) out.overflow.push(`лист выше экрана: ${Math.round(box.top)}…${Math.round(box.bottom)} из ${height}`);
  }
  for (const el of document.querySelectorAll('#app *')) {
    // лента повторов прокручивается вбок нарочно; скрытый текст для диктора и внутренности графика не в счёт
    if (el.closest('.sr-only, svg') || (el.parentElement && el.parentElement.closest('.reps'))) continue;
    const box = el.getBoundingClientRect();
    if (!box.width || !box.height) continue;
    if (box.right > width + 0.5 || box.left < -0.5) out.overflow.push(name(el, box));
  }
  const scope = dialog || document;
  for (const el of scope.querySelectorAll('button, a[href], select, input, textarea, summary')) {
    const box = el.getBoundingClientRect();
    if (!box.width || !box.height) continue;
    if (box.width < minTarget - 0.5 || box.height < minTarget - 0.5) out.small.push(name(el, box));
  }
  return out;
}

/** Ждёт, пока на экране появится нужное место, и проверяет вёрстку. */
async function checkLayout(page, where, shown) {
  await shown.first().waitFor();
  const found = await page.evaluate(audit, 44);
  assert.deepEqual(found, { overflow: [], small: [], scroll: [] }, `вёрстка, ${where}`);
}

const BACKGROUND = { light: 'rgb(244, 243, 239)', dark: 'rgb(13, 13, 13)' };

for (const width of [360, 390, 430]) {
  for (const scheme of ['light', 'dark']) {
    const title = `вёрстка ${width} px, ${scheme === 'dark' ? 'тёмная' : 'светлая'} тема: ничего не вылезает, в кнопки легко попасть`;
    test(title, options, () => withApp({ width, scheme }, async (app) => {
      const { page } = app;
      const heading = (name) => page.getByRole('heading', { name, exact: true });
      const closeSheet = async () => {
        await press(page, 'Закрыть');
        await sheetGone(page);
      };
      await ready(app);
      await app.synced();
      assert.equal(await page.evaluate(() => getComputedStyle(document.body).backgroundColor), BACKGROUND[scheme]);
      await checkLayout(page, 'сегодня', page.locator('.day-head'));

      // круг пары: записанные подходы, таймер в нижней панели
      await app.rep(CURL, 12).click();
      await app.rep(ROW, 12).click();
      await checkLayout(page, 'сегодня с таймером', page.locator('.timer'));
      await expand(app.card(HACK));
      await checkLayout(page, 'сегодня, раскрыта вторая пара', app.card(HACK).locator('.reps'));

      await app.card(HACK).locator('.weight__value').click();
      await checkLayout(page, 'ввод веса', sheet(page).locator('.chips'));
      await closeSheet();
      await app.card(WALK).getByRole('button', { name: 'Добавить отрезок' }).click();
      await checkLayout(page, 'ввод ходьбы', sheet(page).locator('.display__field').nth(1));
      await closeSheet();
      await app.card(WALK).locator('.note-btn').click();
      await checkLayout(page, 'заметка', sheet(page).locator('textarea'));
      await closeSheet();
      await page.locator('.pill').click();
      await checkLayout(page, 'синхронизация', sheet(page).locator('.kv'));
      await closeSheet();

      await tab(page, 'План').click();
      await checkLayout(page, 'план', page.locator('.week'));
      await page.locator(`.day-row[href="#/day/${SKIPPED}"]`).click();
      await checkLayout(page, 'другой день', page.locator('.banner', { hasText: 'Запись за чт 19.11' }));

      await tab(page, 'Прогресс').click();
      await page.locator('.chart svg').first().waitFor();
      for (const summary of await page.locator('summary').all()) await summary.click();
      await checkLayout(page, 'прогресс', page.locator('details[open] table').nth(1));

      await tab(page, 'Настройки').click();
      await checkLayout(page, 'настройки', heading('Оформление'));
      await page.getByRole('button', { name: 'Изменить', exact: true }).click();
      await checkLayout(page, 'настройки, новое подключение', heading('Новое подключение'));
      await page.getByRole('button', { name: 'Отмена' }).click();
      await heading('Таблица').waitFor();
      await page.getByRole('button', { name: 'Отключить таблицу' }).click();
      await checkLayout(page, 'подтверждение', sheet(page).getByRole('button', { name: 'Отключить' }));
      await press(page, 'Отключить');
      await sheetGone(page);

      // без подключения: форма и пустые экраны
      await checkLayout(page, 'настройки без подключения', heading('Подключение таблицы'));
      await tab(page, 'Сегодня').click();
      await checkLayout(page, 'приветствие', heading('Подключите таблицу'));
      await tab(page, 'План').click();
      await checkLayout(page, 'план без подключения', heading('Плана пока нет'));
      await tab(page, 'Прогресс').click();
      await checkLayout(page, 'прогресс без подключения', heading('Пока нечего показывать'));
      assert.deepEqual(unexpected(app), []);
    }));
  }
}

test('тема: «Авто» следует за телефоном, выбранная вручную держится и не мигает при запуске', options, () => withApp({ scheme: 'light' }, async (app) => {
  const { page } = app;
  const background = () => page.evaluate(() => getComputedStyle(document.body).backgroundColor);
  const themeColors = () => page.evaluate(() => [...document.querySelectorAll('meta[name="theme-color"]')].map((meta) => meta.content));
  await ready(app);
  assert.equal(await background(), BACKGROUND.light);
  await page.emulateMedia({ colorScheme: 'dark' });
  assert.equal(await background(), BACKGROUND.dark);
  await page.emulateMedia({ colorScheme: 'light' });

  await tab(page, 'Настройки').click();
  await page.getByRole('button', { name: 'Тёмная', exact: true }).click();
  await eventually(async () => assert.equal(await background(), BACKGROUND.dark));
  assert.deepEqual(await themeColors(), ['#0d0d0d', '#0d0d0d'], 'полоса над приложением того же цвета, что и фон');

  // тема ставится до первой отрисовки, раньше чем загрузится приложение
  await page.addInitScript(() => {
    document.addEventListener('DOMContentLoaded', () => {
      window.__themeAtParse = document.documentElement.getAttribute('data-theme');
    });
  });
  await page.reload();
  await page.locator('.tabs').waitFor();
  assert.equal(await page.evaluate(() => window.__themeAtParse), 'dark');
  assert.equal(await background(), BACKGROUND.dark);

  await page.getByRole('button', { name: 'Светлая', exact: true }).click();
  await page.emulateMedia({ colorScheme: 'dark' });
  await eventually(async () => assert.equal(await background(), BACKGROUND.light));
  await page.getByRole('button', { name: 'Авто', exact: true }).click();
  await eventually(async () => assert.equal(await background(), BACKGROUND.dark));
  assert.deepEqual(await themeColors(), ['#f4f3ef', '#0d0d0d']);
  assert.deepEqual(unexpected(app), []);
}));

/* ------------------------------------------------------------------ */
/* Установка и обновление                                              */
/* ------------------------------------------------------------------ */

test('приложение ставится на экран телефона: манифест, значки, сервис-воркер только в своей папке', options, () => withApp({}, async (app) => {
  const { page } = app;
  await ready(app);
  const scope = await page.evaluate(() => navigator.serviceWorker.ready.then((registration) => registration.scope));
  assert.equal(scope, app.url);
  const manifest = await page.evaluate(async () => {
    const link = document.querySelector('link[rel="manifest"]');
    const response = await fetch(link.href);
    return { type: response.headers.get('content-type'), data: await response.json(), base: link.href };
  });
  assert.equal(manifest.data.display, 'standalone');
  assert.equal(new URL(manifest.data.start_url, manifest.base).href, app.url);
  assert.equal(new URL(manifest.data.scope, manifest.base).href, app.url);
  for (const icon of manifest.data.icons) {
    const status = await page.evaluate(async (src) => (await fetch(src)).status, new URL(icon.src, manifest.base).href);
    assert.equal(status, 200, icon.src);
  }

  // всё, из чего состоит приложение, лежит в кэше с именем «gj-…»
  await tab(page, 'Настройки').click();
  await page.getByText('Приложение сохранено в телефоне и открывается без сети.').waitFor();
  const cached = await page.evaluate(async () => {
    const names = await caches.keys();
    const cache = await caches.open(names[0]);
    return { names, files: (await cache.keys()).map((request) => new URL(request.url).pathname).sort() };
  });
  const sw = fs.readFileSync(path.join(ROOT, 'sw.js'), 'utf8');
  const version = /const VERSION = "([^"]+)"/.exec(sw)[1];
  const files = JSON.parse(/const FILES = (\[[^\]]+\])/.exec(sw)[1]);
  assert.deepEqual(cached.names, [`gj-${version}`]);
  assert.deepEqual(cached.files, files.map((file) => new URL(file, app.url).pathname).sort());
  assert.equal(await text(page.locator('.kv dd').last()), version);
  assert.deepEqual(unexpected(app), []);
}));

test('обновление: новая версия ждёт, ставится по кнопке или при следующем запуске, записи не теряются', options, () => withApp({}, async (app) => {
  const { page, server, spreadsheet } = app;
  const sw = fs.readFileSync(path.join(ROOT, 'sw.js'), 'utf8');
  const release = (version) => {
    server.override('sw.js', sw.replace(/const VERSION = "[^"]+"/, `const VERSION = "${version}"`));
    server.override('js/version.js', `export const VERSION = '${version}';\n`);
  };
  const versionShown = () => page.locator('.kv dd').last();
  const cacheNames = () => page.evaluate(() => caches.keys());

  await ready(app);
  await app.synced();
  await page.evaluate(() => navigator.serviceWorker.ready.then(() => true));
  await page.reload();
  await page.locator('.day-head').waitFor();

  // запись, которая не успела уйти: обновление не должно её потерять
  app.bridge.mode = 'down';
  await app.rep(CURL, 12).click();
  await app.tick(1500);
  await pill(page, 'В очереди: 1').waitFor();

  release('9.9.9+test');
  await tab(page, 'Настройки').click();
  await page.getByRole('button', { name: 'Проверить обновление' }).click();
  const bar = page.locator('.update');
  await bar.waitFor();
  assert.equal(await text(bar.locator('span')), 'Вышла новая версия');
  await page.getByRole('button', { name: 'Обновить приложение' }).waitFor();
  assert.equal((await cacheNames()).length, 2, 'новая версия скачана и ждёт рядом со старой');
  assert.notEqual(await text(versionShown()), '9.9.9+test', 'пока человек не нажал, работает старая версия');

  await bar.getByRole('button', { name: 'Обновить' }).click();
  await page.locator('.kv dd', { hasText: '9.9.9+test' }).waitFor();
  assert.deepEqual(await cacheNames(), ['gj-9.9.9+test'], 'старый кэш удалён');
  assert.equal(await bar.count(), 0);
  await pill(page, 'В очереди: 1').waitFor();

  // следующая версия вышла, человек не нажал «Обновить»: она применится при следующем запуске
  release('9.9.10+test');
  await page.getByRole('button', { name: 'Проверить обновление' }).click();
  await bar.waitFor();
  await page.reload();
  await page.locator('.kv dd', { hasText: '9.9.10+test' }).waitFor();
  await eventually(async () => assert.deepEqual(await cacheNames(), ['gj-9.9.10+test']));

  app.bridge.mode = 'ok';
  await app.tick(31_000);
  await app.synced();
  assert.deepEqual(findRow(spreadsheet, TODAY, CURL).sets, [12, '', '']);
  assert.deepEqual(unexpected(app), []);
}));
