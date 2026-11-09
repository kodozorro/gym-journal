// Тесты мостика: настоящий apps-script/Code.gs выполняется в Node поверх таблицы в памяти.

import { test } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import { boot, KEY, CODE_GS, onlyInputCells } from './helpers.mjs';
import { post, FakeSheet, zonedMidnight } from '../tools/gas-fake.mjs';
import { buildSpreadsheet, findRow, journalRows, protectedSnapshot, progressTable, strengthExercises } from '../tools/fixture.mjs';
import { weeklyBest, weeklyWalk } from '../js/core/stats.js';

const WED = '2026-11-11'; // первая силовая в учебном журнале
const TUE = '2026-11-10';

test('doGet отвечает короткой справкой и не отдаёт данных', () => {
  const { script } = boot();
  const out = script.doGet();
  assert.equal(out.mimeType, 'application/json');
  const body = JSON.parse(out.getContent());
  assert.equal(body.ok, true);
  assert.equal(body.api, 1);
  assert.equal('journal' in body, false);
});

test('без ключа в свойствах скрипт просит запустить setup', () => {
  const { call } = boot({ noKey: true });
  const out = call({ action: 'pull' });
  assert.equal(out.ok, false);
  assert.equal(out.error, 'no_key');
  assert.equal('journal' in out, false);
});

test('неверный, пустой и нестроковый ключ отклоняются', () => {
  const { script } = boot();
  for (const key of ['wrong', '', KEY + 'x', KEY.slice(0, -1), 12345, null, { a: 1 }, undefined]) {
    const out = post(script, { key, action: 'pull' }).json;
    assert.equal(out.ok, false, `ключ ${JSON.stringify(key)}`);
    assert.equal(out.error, 'unauthorized');
    assert.equal('journal' in out, false);
  }
  assert.equal(post(script, { key: KEY, action: 'ping' }).json.ok, true);
});

test('плохие запросы получают JSON с кодом ошибки', () => {
  const { script, call } = boot();
  assert.equal(post(script, '').json.error, 'bad_request');
  assert.equal(post(script, 'не json').json.error, 'bad_json');
  assert.equal(post(script, '[1,2]').json.error, 'bad_request');
  assert.equal(post(script, '"строка"').json.error, 'bad_request');
  assert.equal(post(script, JSON.stringify({ key: KEY, pad: 'x'.repeat(200001) })).json.error, 'too_large');
  assert.equal(call({ action: 'drop' }).error, 'unknown_action');
  assert.equal(call({}).error, 'unknown_action');
  // Google вызывает doPost и без тела запроса
  const out = script.doPost(undefined);
  assert.equal(JSON.parse(out.getContent()).error, 'bad_request');
  assert.equal(out.mimeType, 'application/json');
});

test('setup создаёт ключ один раз, resetKey меняет его', () => {
  const { script, logs, call } = boot({ noKey: true });
  const key = script.setup();
  assert.match(key, /^[0-9a-f]{40}$/);
  assert.ok(logs.some((line) => line.includes(key)), 'ключ напечатан в журнале выполнения');
  assert.equal(script.setup(), key, 'повторный запуск ключ не меняет');
  assert.equal(post(script, { key, action: 'ping' }).json.ok, true);
  assert.equal(call({ action: 'ping' }).error, 'unauthorized');
  const next = script.resetKey();
  assert.notEqual(next, key);
  assert.equal(post(script, { key, action: 'ping' }).json.error, 'unauthorized');
  assert.equal(post(script, { key: next, action: 'ping' }).json.ok, true);
});

test('pull отдаёт журнал, дату старта и цель по ходьбе', () => {
  const { call, spreadsheet } = boot();
  const out = call({ action: 'pull' });
  assert.equal(out.ok, true);
  assert.equal(out.api, 1);
  assert.equal(out.tz, 'Etc/GMT');
  assert.equal(out.start, '2026-11-09');
  assert.equal(out.walkGoalKm, 17);
  // первая неделя без понедельника: 16 строк, дальше 11 недель по 23 строки
  assert.equal(out.journal.length, 16 + 11 * 23);
  assert.deepEqual(out.journal[0], {
    date: TUE, workout: 'Ходьба', exercise: 'Ходьба ровным темпом', plan: '4 км, наклон 3–6 %',
    machine: 'Беговая дорожка', week: 1, weight: null, sets: [null, null, null], km: null, min: null, note: '',
  });
  assert.deepEqual(out.journal[1], {
    date: WED, workout: 'Силовая B', exercise: 'Сгибание ног', plan: '2 × 12–15 на ногу',
    machine: 'Kneeling Leg Curl Machine', week: 1, weight: null, sets: [null, null, null], km: null, min: null, note: '',
  });
  assert.equal(out.journal.at(-1).date, '2027-01-29');
  assert.equal(out.journal.at(-1).week, 12);
  assert.ok(out.journal.every((row) => !row.exercise.startsWith('Недели')), 'строки-подсказки пропущены');
  assert.ok(out.journal.every((row) => !('occ' in row)), 'повторов даты и упражнения нет');
  assert.deepEqual(onlyInputCells(spreadsheet), []);
  assert.equal(spreadsheet.getSheetByName('Журнал').writes.length, 0, 'чтение ничего не пишет');
});

test('даты читаются по часовому поясу таблицы, а не скрипта', () => {
  for (const timeZone of ['Asia/Tbilisi', 'America/Los_Angeles', 'Pacific/Kiritimati', 'Europe/London']) {
    const { call } = boot({ sheet: { timeZone } });
    const out = call({ action: 'pull' });
    assert.equal(out.tz, timeZone);
    assert.equal(out.start, '2026-11-09', timeZone);
    assert.equal(out.journal[0].date, TUE, timeZone);
    assert.equal(out.journal.at(-1).date, '2027-01-29', timeZone);
  }
});

test('push пишет вес и подходы силовой строки в столбцы E–H', () => {
  const { call, spreadsheet } = boot();
  const before = protectedSnapshot(spreadsheet);
  const out = call({ action: 'push', entries: [{ date: WED, exercise: 'Гакк-жим', weight: 42.5, sets: [15, 14, null] }] });
  assert.equal(out.ok, true);
  assert.deepEqual(out.results, [{ date: WED, exercise: 'Гакк-жим', status: 'written' }]);
  const row = findRow(spreadsheet, WED, 'Гакк-жим');
  assert.equal(row.weight, 42.5);
  assert.deepEqual(row.sets, [15, 14, '']);
  assert.equal(row.km, '');
  assert.equal(row.note, '');
  assert.deepEqual(onlyInputCells(spreadsheet), []);
  assert.equal(protectedSnapshot(spreadsheet), before, 'формулы, заголовки и подсказки не изменились');
  assert.equal('journal' in out, false, 'без pull:true журнал не отдаётся');
});

test('push пишет километры и минуты ходьбы в столбцы I и J', () => {
  const { call, spreadsheet, state } = boot();
  const out = call({ action: 'push', entries: [{ date: TUE, exercise: 'Ходьба ровным темпом', km: 4.2, min: 52 }] });
  assert.equal(out.results[0].status, 'written');
  const row = findRow(spreadsheet, TUE, 'Ходьба ровным темпом');
  assert.equal(row.km, 4.2);
  assert.equal(row.min, 52);
  assert.equal(row.weight, '');
  assert.deepEqual(onlyInputCells(spreadsheet), []);
  assert.equal(state.flushes, 1, 'изменения сброшены в таблицу до ответа');
});

test('числа округляются, а записываются именно числами', () => {
  const { call, spreadsheet, journal } = boot();
  call({ action: 'push', entries: [
    { date: WED, exercise: 'Гакк-жим', weight: 42.555 },
    { date: TUE, exercise: 'Ходьба ровным темпом', km: 3.14159, min: 30.26 },
  ] });
  assert.equal(findRow(spreadsheet, WED, 'Гакк-жим').weight, 42.56);
  const walk = findRow(spreadsheet, TUE, 'Ходьба ровным темпом');
  assert.equal(walk.km, 3.14);
  assert.equal(walk.min, 30.3);
  assert.ok(journal.writes.every((w) => typeof w.value === 'number'), 'в ячейки ушли числа, а не строки');
  assert.deepEqual(onlyInputCells(spreadsheet), []);
});

test('в строку ходьбы не пишутся вес и подходы, в силовую — километры', () => {
  const { call, spreadsheet, journal } = boot();
  const out = call({ action: 'push', entries: [
    { date: TUE, exercise: 'Ходьба ровным темпом', weight: 40 },
    { date: TUE, exercise: 'Ходьба ровным темпом', sets: [10] },
    { date: WED, exercise: 'Гакк-жим', km: 3 },
    { date: WED, exercise: 'Гакк-жим', min: 30 },
  ] });
  assert.deepEqual(out.results.map((r) => r.status), ['rejected', 'rejected', 'rejected', 'rejected']);
  assert.ok(out.results.every((r) => typeof r.reason === 'string' && r.reason.length > 0));
  assert.equal(journal.writes.length, 0);
  assert.deepEqual(onlyInputCells(spreadsheet), []);
});

test('строка ищется по дате и упражнению; ненайденная запись не мешает остальным', () => {
  const { call, spreadsheet, journal } = boot();
  const out = call({ action: 'push', entries: [
    { date: '2026-11-08', exercise: 'Гакк-жим', weight: 30 }, // такой даты в журнале нет
    { date: WED, exercise: 'Приседания со штангой', weight: 30 }, // такого упражнения в этот день нет
    { date: WED, exercise: 'Жим ногами', weight: 30 }, // упражнение пятницы, а не среды
    { date: WED, exercise: 'Гакк-жим', weight: 30 },
  ] });
  assert.deepEqual(out.results.map((r) => r.status), ['not_found', 'not_found', 'not_found', 'written']);
  assert.equal(journal.writes.length, 1);
  assert.equal(findRow(spreadsheet, WED, 'Гакк-жим').weight, 30);
  assert.equal(findRow(spreadsheet, '2026-11-13', 'Жим ногами').weight, '');
});

test('одно и то же упражнение в разные дни пишется в свою строку', () => {
  const { call, spreadsheet } = boot();
  call({ action: 'push', entries: [
    { date: WED, exercise: 'Сгибание ног', weight: 20, sets: [15, 15] },
    { date: '2026-11-13', exercise: 'Сгибание ног', weight: 22.5, sets: [14, 13] },
  ] });
  assert.equal(findRow(spreadsheet, WED, 'Сгибание ног').weight, 20);
  assert.equal(findRow(spreadsheet, '2026-11-13', 'Сгибание ног').weight, 22.5);
  assert.equal(findRow(spreadsheet, '2026-11-16', 'Сгибание ног').weight, '');
});

test('неверные записи отклоняются целиком и ничего не пишут', () => {
  const { call, spreadsheet, journal } = boot();
  const bad = [
    null,
    'строка',
    [1, 2],
    { exercise: 'Гакк-жим', weight: 30 },
    { date: '11.11.2026', exercise: 'Гакк-жим', weight: 30 },
    { date: '2026-02-30', exercise: 'Гакк-жим', weight: 30 },
    { date: WED, weight: 30 },
    { date: WED, exercise: '', weight: 30 },
    { date: WED, exercise: 'Г'.repeat(201), weight: 30 },
    { date: WED, exercise: 'Гакк-жим', weight: -1 },
    { date: WED, exercise: 'Гакк-жим', weight: 1000.5 },
    { date: WED, exercise: 'Гакк-жим', weight: '30' },
    { date: WED, exercise: 'Гакк-жим', weight: true },
    { date: WED, exercise: 'Гакк-жим', sets: 15 },
    { date: WED, exercise: 'Гакк-жим', sets: [1, 2, 3, 4] },
    { date: WED, exercise: 'Гакк-жим', sets: [12.5] },
    { date: WED, exercise: 'Гакк-жим', sets: [-1] },
    { date: WED, exercise: 'Гакк-жим', sets: [501] },
    { date: WED, exercise: 'Гакк-жим', sets: ['12'] },
    { date: WED, exercise: 'Гакк-жим', weight: 30, sets: [12, '=1+1'] },
    { date: WED, exercise: 'Гакк-жим', note: 5 },
    { date: WED, exercise: 'Гакк-жим', note: 'я'.repeat(501) },
    { date: WED, exercise: 'Гакк-жим', occ: -1, weight: 30 },
    { date: WED, exercise: 'Гакк-жим', occ: 1.5, weight: 30 },
    { date: WED, exercise: 'Гакк-жим', occ: 51, weight: 30 },
    { date: TUE, exercise: 'Ходьба ровным темпом', km: 201 },
    { date: TUE, exercise: 'Ходьба ровным темпом', km: '4' },
    { date: TUE, exercise: 'Ходьба ровным темпом', min: 1441 },
    { date: TUE, exercise: 'Ходьба ровным темпом', min: -5 },
  ];
  const out = call({ action: 'push', entries: bad });
  assert.equal(out.ok, true);
  assert.equal(out.results.length, bad.length);
  out.results.forEach((result, i) => {
    assert.equal(result.status, 'rejected', `запись №${i}: ${JSON.stringify(bad[i])}`);
    assert.ok(result.reason, `у записи №${i} есть причина`);
  });
  assert.equal(journal.writes.length, 0);
  assert.deepEqual(onlyInputCells(spreadsheet), []);
});

test('entries не список или слишком длинный', () => {
  const { call, journal } = boot();
  assert.equal(call({ action: 'push' }).error, 'bad_request');
  assert.equal(call({ action: 'push', entries: {} }).error, 'bad_request');
  const many = Array.from({ length: 401 }, () => ({ date: WED, exercise: 'Гакк-жим', weight: 30 }));
  assert.equal(call({ action: 'push', entries: many }).error, 'too_many');
  assert.equal(journal.writes.length, 0);
  assert.deepEqual(call({ action: 'push', entries: [] }).results, []);
});

test('повторная отправка той же записи ничего не меняет', () => {
  const { call, journal } = boot();
  const entries = [
    { date: WED, exercise: 'Гакк-жим', weight: 40, sets: [15, 15, null], note: 'сиденье 4' },
    { date: TUE, exercise: 'Ходьба ровным темпом', km: 4, min: 50 },
  ];
  assert.deepEqual(call({ action: 'push', entries }).results.map((r) => r.status), ['written', 'written']);
  const writes = journal.writes.length;
  assert.deepEqual(call({ action: 'push', entries }).results.map((r) => r.status), ['unchanged', 'unchanged']);
  assert.equal(journal.writes.length, writes, 'второй запрос не тронул ни одной ячейки');
});

test('пишутся только присланные поля; null очищает ячейку', () => {
  const { call, spreadsheet } = boot();
  call({ action: 'push', entries: [{ date: WED, exercise: 'Гакк-жим', weight: 40, sets: [15, 14], note: 'узкая постановка' }] });
  call({ action: 'push', entries: [{ date: WED, exercise: 'Гакк-жим', sets: [15, 15] }] });
  let row = findRow(spreadsheet, WED, 'Гакк-жим');
  assert.equal(row.weight, 40, 'вес не тронут');
  assert.deepEqual(row.sets, [15, 15, '']);
  assert.equal(row.note, 'узкая постановка', 'заметка не тронута');

  call({ action: 'push', entries: [{ date: WED, exercise: 'Гакк-жим', weight: null, sets: [null, 15] }] });
  row = findRow(spreadsheet, WED, 'Гакк-жим');
  assert.equal(row.weight, '');
  assert.deepEqual(row.sets, ['', 15, '']);

  call({ action: 'push', entries: [{ date: WED, exercise: 'Гакк-жим', sets: [], note: '' }] });
  row = findRow(spreadsheet, WED, 'Гакк-жим');
  assert.deepEqual(row.sets, ['', '', '']);
  assert.equal(row.note, '');
  assert.deepEqual(onlyInputCells(spreadsheet), []);
});

test('ноль — это значение, а не пустая ячейка', () => {
  const { call, spreadsheet } = boot();
  const out = call({ action: 'push', pull: true, entries: [{ date: WED, exercise: 'Гакк-жим', weight: 0, sets: [12, 0] }] });
  const row = findRow(spreadsheet, WED, 'Гакк-жим');
  assert.equal(row.weight, 0);
  assert.deepEqual(row.sets, [12, 0, '']);
  const pulled = out.journal.find((r) => r.date === WED && r.exercise === 'Гакк-жим');
  assert.equal(pulled.weight, 0);
  assert.deepEqual(pulled.sets, [12, 0, null]);
});

test('заметка хранится текстом и не превращается в формулу, число или дату', () => {
  const { call, spreadsheet } = boot();
  const notes = ['=1+1', '=IMPORTRANGE("x";"A1")', '+5', '-3', '10.11', '42', '3,5', 'true', 'ИСТИНА', "'кавычка", 'обычная заметка'];
  const rows = journalRows(spreadsheet).filter((r) => r.workout && r.workout !== 'Ходьба').slice(0, notes.length);
  const entries = rows.map((r, i) => ({ date: r.date, exercise: r.exercise, note: notes[i] }));
  const out = call({ action: 'push', pull: true, entries });
  assert.ok(out.results.every((r) => r.status === 'written'));
  assert.deepEqual(spreadsheet.violations, [], 'ни одна заметка не разобрана таблицей как формула или число');
  rows.forEach((r, i) => {
    assert.equal(findRow(spreadsheet, r.date, r.exercise).note, notes[i]);
    assert.equal(out.journal.find((j) => j.date === r.date && j.exercise === r.exercise).note, notes[i]);
  });
  // повтор не переписывает ячейки
  assert.ok(call({ action: 'push', entries }).results.every((r) => r.status === 'unchanged'));
});

test('заметка чистится от управляющих символов и пробелов по краям', () => {
  const { call, spreadsheet } = boot();
  call({ action: 'push', entries: [{ date: WED, exercise: 'Гакк-жим', note: '  сиденье\u0000 4\u0007  ' }] });
  assert.equal(findRow(spreadsheet, WED, 'Гакк-жим').note, 'сиденье 4');
});

test('две строки с одной датой и упражнением различаются номером повтора', () => {
  const spreadsheet = buildSpreadsheet();
  const sheet = spreadsheet.getSheetByName('Журнал');
  const last = sheet.getLastRow();
  // пользователь вручную добавил вторую ходьбу во вторник
  const extra = last + 1;
  sheet.seed(extra, 1, zonedMidnight(TUE, 'Etc/GMT'), { protect: true });
  sheet.seed(extra, 2, 'Ходьба', { protect: true });
  sheet.seed(extra, 3, 'Ходьба ровным темпом', { protect: true });
  sheet.seed(extra, 13, 1, { protect: true });
  const { call } = boot({ spreadsheet });

  const pulled = call({ action: 'pull' }).journal.filter((r) => r.date === TUE);
  assert.equal(pulled.length, 2);
  assert.equal('occ' in pulled[0], false);
  assert.equal(pulled[1].occ, 1);

  const out = call({ action: 'push', entries: [
    { date: TUE, exercise: 'Ходьба ровным темпом', km: 4 },
    { date: TUE, exercise: 'Ходьба ровным темпом', occ: 1, km: 1.5 },
    { date: TUE, exercise: 'Ходьба ровным темпом', occ: 2, km: 9 },
  ] });
  assert.deepEqual(out.results, [
    { date: TUE, exercise: 'Ходьба ровным темпом', status: 'written' },
    { date: TUE, exercise: 'Ходьба ровным темпом', status: 'written', occ: 1 },
    { date: TUE, exercise: 'Ходьба ровным темпом', status: 'not_found', occ: 2, reason: out.results[2].reason },
  ]);
  assert.equal(sheet.peek(3, 9), 4);
  assert.equal(sheet.peek(extra, 9), 1.5);
});

test('ручные правки в таблице видны при следующем чтении', () => {
  const { call, spreadsheet, journal } = boot();
  const target = findRow(spreadsheet, WED, 'Гакк-жим');
  journal.manualEdit(target.row, 5, 37.5);
  journal.manualEdit(target.row, 6, 12);
  journal.manualEdit(target.row, 7, 'много'); // текст в числовой ячейке приложению не передаётся
  journal.manualEdit(target.row, 12, 'поправил вручную');
  const row = call({ action: 'pull' }).journal.find((r) => r.date === WED && r.exercise === 'Гакк-жим');
  assert.equal(row.weight, 37.5);
  assert.deepEqual(row.sets, [12, null, null]);
  assert.equal(row.note, 'поправил вручную');
});

test('push с pull:true возвращает журнал уже с новыми значениями', () => {
  const { call } = boot();
  const out = call({ action: 'push', pull: true, entries: [{ date: WED, exercise: 'Гакк-жим', weight: 45, sets: [12, 12, 11] }] });
  assert.equal(out.start, '2026-11-09');
  assert.equal(out.walkGoalKm, 17);
  const row = out.journal.find((r) => r.date === WED && r.exercise === 'Гакк-жим');
  assert.equal(row.weight, 45);
  assert.deepEqual(row.sets, [12, 12, 11]);
});

test('занятая блокировка даёт busy, а после записи блокировка отпускается', () => {
  const { call, state, journal } = boot();
  state.lock.available = false;
  const busy = call({ action: 'push', entries: [{ date: WED, exercise: 'Гакк-жим', weight: 30 }] });
  assert.equal(busy.ok, false);
  assert.equal(busy.error, 'busy');
  assert.equal(journal.writes.length, 0);

  state.lock.available = true;
  assert.equal(call({ action: 'push', entries: [{ date: WED, exercise: 'Гакк-жим', weight: 30 }] }).ok, true);
  assert.equal(state.lock.held, false);
  assert.equal(state.lock.acquired, 1);
  assert.equal(state.lock.released, 1);
});

test('изменённые заголовки останавливают и чтение, и запись', () => {
  const spreadsheet = buildSpreadsheet();
  spreadsheet.getSheetByName('Журнал').seed(2, 5, 'Вес'); // было «Вес, кг»
  const { call, journal, state } = boot({ spreadsheet });
  const pull = call({ action: 'pull' });
  assert.equal(pull.ok, false);
  assert.equal(pull.error, 'layout_changed');
  assert.match(pull.message, /столбце E/);
  const push = call({ action: 'push', entries: [{ date: WED, exercise: 'Гакк-жим', weight: 30 }] });
  assert.equal(push.error, 'layout_changed');
  assert.equal(journal.writes.length, 0);
  assert.equal(state.lock.held, false, 'блокировка отпущена и после ошибки');
});

test('нет листа «Журнал» или самой таблицы', () => {
  const noJournal = buildSpreadsheet();
  noJournal.sheets = noJournal.sheets.filter((sheet) => sheet.name !== 'Журнал');
  assert.equal(boot({ spreadsheet: noJournal }).call({ action: 'pull' }).error, 'no_journal');
  assert.equal(boot({ spreadsheet: null }).call({ action: 'pull' }).error, 'no_spreadsheet');
  // ping проверяет только ключ и работает даже без таблицы
  assert.equal(boot({ spreadsheet: null }).call({ action: 'ping' }).ok, true);
});

test('без листа «Прогресс» журнал всё равно читается', () => {
  const spreadsheet = buildSpreadsheet();
  spreadsheet.sheets = spreadsheet.sheets.filter((sheet) => sheet.name !== 'Прогресс');
  const out = boot({ spreadsheet }).call({ action: 'pull' });
  assert.equal(out.ok, true);
  assert.equal(out.start, null);
  assert.equal(out.walkGoalKm, null);
  assert.equal(out.journal.length, 16 + 11 * 23);
});

test('любое исключение внутри скрипта превращается в JSON с кодом internal', () => {
  const { script, state, spreadsheet } = boot();
  spreadsheet.getSheetByName = () => {
    throw new Error('Service Spreadsheets failed');
  };
  const out = script.doPost({ postData: { contents: JSON.stringify({ key: KEY, action: 'push', entries: [] }) } });
  assert.equal(out.mimeType, 'application/json');
  const body = JSON.parse(out.getContent());
  assert.equal(body.ok, false);
  assert.equal(body.error, 'internal');
  assert.match(body.message, /Spreadsheets failed/);
  assert.equal(state.lock.held, false);
});

test('пустой журнал без строк данных', () => {
  const sheet = new FakeSheet('Журнал');
  const full = buildSpreadsheet().getSheetByName('Журнал');
  for (let col = 1; col <= 13; col += 1) sheet.seed(2, col, full.peek(2, col), { protect: true });
  const spreadsheet = buildSpreadsheet();
  spreadsheet.sheets = [sheet, ...spreadsheet.sheets.filter((s) => s.name !== 'Журнал')];
  const { call } = boot({ spreadsheet });
  assert.deepEqual(call({ action: 'pull' }).journal, []);
  assert.equal(call({ action: 'push', entries: [{ date: WED, exercise: 'Гакк-жим', weight: 30 }] }).results[0].status, 'not_found');
});

test('неделя тренировок: сводка приложения совпадает с формулами листа «Прогресс»', () => {
  const { call, spreadsheet } = boot();
  const entries = [];
  const weights = new Map();
  for (const row of journalRows(spreadsheet).filter((r) => r.week === 1 || r.week === 2 || r.week === 4)) {
    if (row.workout === 'Ходьба') {
      entries.push({ date: row.date, exercise: row.exercise, km: 3 + (entries.length % 3) * 0.5, min: 35 + (entries.length % 5) });
    } else {
      const next = (weights.get(row.exercise) ?? 17.5) + 2.5;
      weights.set(row.exercise, next);
      entries.push({ date: row.date, exercise: row.exercise, weight: next, sets: [15, 14, null] });
    }
  }
  // одна строка без веса и одна с нулём: формула MAXIFS их не считает
  entries.push({ date: '2026-12-09', exercise: 'Гакк-жим', sets: [10, 10, 10] });
  entries.push({ date: '2026-12-16', exercise: 'Гакк-жим', weight: 0 });
  const out = call({ action: 'push', pull: true, entries });
  assert.ok(out.results.every((r) => r.status === 'written'), JSON.stringify(out.results.filter((r) => r.status !== 'written')));
  assert.deepEqual(onlyInputCells(spreadsheet), []);

  const table = progressTable(spreadsheet);
  assert.deepEqual(table.map((w) => w.week), [1, 2, 4, 6], 'неделя с нулевым весом попадает в сводку, неделя без веса — нет');

  const walk = weeklyWalk(out.journal, out.start);
  assert.deepEqual(walk.map((w) => w.week), table.map((w) => w.week));
  walk.forEach((w, i) => {
    assert.ok(Math.abs(w.km - table[i].km) < 1e-9, `км недели ${w.week}`);
    assert.ok(Math.abs(w.min - table[i].min) < 1e-9, `минуты недели ${w.week}`);
  });
  for (const name of strengthExercises()) {
    const best = Object.fromEntries(weeklyBest(out.journal, name, out.start).map((w) => [w.week, w.best]));
    for (const week of table) assert.equal(best[week.week], week.best[name], `${name}, неделя ${week.week}`);
  }
});

test('код скрипта просит только доступ к своей таблице', () => {
  const source = fs.readFileSync(CODE_GS, 'utf8');
  assert.match(source, /@OnlyCurrentDoc/);
  for (const service of ['openById', 'openByUrl', 'UrlFetchApp', 'DriveApp', 'GmailApp', 'MailApp', 'ScriptApp', 'eval(']) {
    assert.equal(source.includes(service), false, `в коде нет ${service}`);
  }
  // синтаксис без новшеств: скрипт должен работать и там, где нет ?. и ??
  assert.equal(/\?\.|\?\?/.test(source.replace(/\/\*[\s\S]*?\*\/|\/\/.*$/gm, '')), false);
});
