// Тесты синхронизации: движок приложения разговаривает с настоящим Code.gs поверх таблицы в памяти.

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { boot, KEY, memoryBackend, fakeClock, bridgeFetch, onlyInputCells } from './helpers.mjs';
import { findRow, protectedSnapshot } from '../tools/fixture.mjs';
import { createStorage, PREFIX } from '../js/data/storage.js';
import { createSync, FLUSH_DELAY } from '../js/data/sync.js';
import { callBridge, normalizeBridgeUrl, extractConnection, BridgeError } from '../js/data/api.js';

const URL = 'https://script.google.com/macros/s/TESTDEPLOYMENTID_0123456789/exec';
const WED = '2026-11-11';
const row = (journal, date, exercise) => journal.find((r) => r.date === date && r.exercise === exercise);

function setup({ backend = memoryBackend(), world = boot(), control = {}, online = { value: true } } = {}) {
  const clock = fakeClock();
  const bridge = bridgeFetch(world.script, control);
  let changes = 0;
  const sync = createSync({
    storage: createStorage(backend),
    fetch: bridge.fetch,
    now: clock.now,
    setTimer: clock.setTimer,
    clearTimer: clock.clearTimer,
    isOnline: () => online.value,
    onChange: () => {
      changes += 1;
    },
  });
  return { backend, world, control, online, clock, bridge, sync, changes: () => changes };
}

async function connected(options) {
  const ctx = setup(options);
  const result = await ctx.sync.connect({ url: URL, key: KEY });
  assert.deepEqual(result, { ok: true });
  return ctx;
}

test('адрес мостика: принимается только развёртывание на script.google.com', () => {
  assert.deepEqual(normalizeBridgeUrl(`  ${URL}  `), { url: URL });
  assert.deepEqual(normalizeBridgeUrl(`${URL}?x=1#frag`), { url: URL });
  assert.deepEqual(normalizeBridgeUrl(`<${URL}>`), { url: URL });
  assert.equal(normalizeBridgeUrl('https://script.google.com/a/macros/example.com/s/ABCDEFGH12345/exec').url, 'https://script.google.com/a/macros/example.com/s/ABCDEFGH12345/exec');
  assert.match(normalizeBridgeUrl(URL.replace('/exec', '/dev')).error, /\/dev/);
  for (const bad of ['', 'script.google.com/macros/s/ABCDEFGH12345/exec', 'http://script.google.com/macros/s/ABCDEFGH12345/exec',
    'https://script.google.com.evil.example/macros/s/ABCDEFGH12345/exec', 'https://evil.example/https://script.google.com/macros/s/ABCDEFGH12345/exec',
    'https://docs.google.com/spreadsheets/d/x/edit', 'https://script.google.com/macros/s/ABCDEFGH12345/exec/extra', 'http://localhost:4174/exec']) {
    assert.ok(normalizeBridgeUrl(bad).error, bad);
  }
  assert.deepEqual(normalizeBridgeUrl('http://localhost:4174/macros/s/x/exec', { allowLocal: true }), { url: 'http://localhost:4174/macros/s/x/exec' });
  assert.ok(normalizeBridgeUrl('http://192.168.1.5:4174/exec', { allowLocal: true }).error);
});

test('адрес и ключ достаются из одного вставленного сообщения', () => {
  const key = '0123456789abcdef0123456789abcdef01234567';
  assert.deepEqual(extractConnection(`Адрес: ${URL}\nКлюч: ${key}`), { url: URL, key });
  assert.deepEqual(extractConnection(`${key} ${URL}`), { url: URL, key });
  assert.deepEqual(extractConnection(URL), { url: URL });
  assert.deepEqual(extractConnection(key), { key });
  assert.deepEqual(extractConnection('привет'), {});
  assert.deepEqual(extractConnection(`${key}0`), {}, 'строка длиннее 40 знаков — не ключ');
});

test('callBridge: ключ едет в теле простого запроса, а не в адресе или заголовке', async () => {
  const { script } = boot();
  const bridge = bridgeFetch(script);
  const data = await callBridge({ url: URL, key: KEY }, 'ping', {}, { fetch: bridge.fetch });
  assert.equal(data.ok, true);
  const { url, init, body } = bridge.calls[0];
  assert.equal(url, URL);
  assert.equal(url.includes(KEY), false);
  assert.equal(init.method, 'POST');
  assert.deepEqual(init.headers, { 'Content-Type': 'text/plain;charset=utf-8' });
  assert.equal(init.credentials, 'omit');
  assert.equal(init.redirect, 'follow');
  assert.deepEqual(body, { key: KEY, action: 'ping' });
});

test('callBridge: ошибки сети, времени, формата и скрипта различаются по коду', async () => {
  const { script } = boot();
  const conn = { url: URL, key: KEY };
  const code = async (promise) => {
    try {
      await promise;
      return 'ok';
    } catch (err) {
      assert.ok(err instanceof BridgeError);
      assert.ok(err.message.length > 0);
      return err.code;
    }
  };
  assert.equal(await code(callBridge(conn, 'ping', {}, { fetch: bridgeFetch(script, { offline: true }).fetch })), 'network');
  assert.equal(await code(callBridge(conn, 'ping', {}, { fetch: bridgeFetch(script, { html: true }).fetch })), 'not_json');
  assert.equal(await code(callBridge({ url: URL, key: 'wrong' }, 'ping', {}, { fetch: bridgeFetch(script).fetch })), 'unauthorized');
  assert.equal(await code(callBridge(conn, 'nope', {}, { fetch: bridgeFetch(script).fetch })), 'unknown_action');
  const hang = (url, init) => new Promise((resolve, reject) => {
    init.signal.addEventListener('abort', () => reject(new DOMException('Aborted', 'AbortError')));
  });
  assert.equal(await code(callBridge(conn, 'ping', {}, { fetch: hang, timeoutMs: 20 })), 'timeout');
  const otherApi = async () => new Response(JSON.stringify({ ok: true, api: 2 }));
  assert.equal(await code(callBridge(conn, 'ping', {}, { fetch: otherApi })), 'api_mismatch');
  const array = async () => new Response('[1,2,3]');
  assert.equal(await code(callBridge(conn, 'ping', {}, { fetch: array })), 'not_json');
});

test('без подключения записи копятся на телефоне, а сеть не трогается', async () => {
  const { sync, bridge, clock, backend } = setup();
  assert.equal(sync.getState().phase, 'unconfigured');
  sync.queue({ date: WED, exercise: 'Гакк-жим' }, { weight: 40 });
  await clock.advance(10 * 60 * 1000);
  assert.equal(bridge.calls.length, 0);
  assert.equal(sync.getState().pending, 1);
  assert.ok(backend.getItem(`${PREFIX}outbox`).includes('Гакк-жим'));
  assert.equal((await sync.sync()).error.code, 'unconfigured');
});

test('подключение сохраняется только после удачного чтения журнала', async () => {
  const { sync, backend } = setup();
  const wrong = await sync.connect({ url: URL, key: 'не тот ключ' });
  assert.equal(wrong.ok, false);
  assert.equal(wrong.error.code, 'unauthorized');
  assert.equal(sync.getState().configured, false);
  assert.equal(backend.getItem(`${PREFIX}conn`), null);
  assert.equal((await sync.connect({ url: URL })).ok, false);

  assert.deepEqual(await sync.connect({ url: URL, key: KEY }), { ok: true });
  const state = sync.getState();
  assert.equal(state.configured, true);
  assert.equal(state.phase, 'idle');
  assert.equal(state.snapshot.start, '2026-11-09');
  assert.equal(state.snapshot.walkGoalKm, 17);
  assert.equal(state.journal.length, 16 + 11 * 23);
  assert.deepEqual(JSON.parse(backend.getItem(`${PREFIX}conn`)), { url: URL, key: KEY });
});

test('правка видна сразу, а в таблицу уходит одним запросом через секунду', async () => {
  const { sync, world, bridge, clock } = await connected();
  const before = protectedSnapshot(world.spreadsheet);
  const calls = bridge.calls.length;
  const target = row(sync.getState().journal, WED, 'Гакк-жим');
  sync.queue(target, { weight: 40 });
  sync.queue(target, { sets: [15, null, null] });

  let state = sync.getState();
  assert.equal(row(state.journal, WED, 'Гакк-жим').weight, 40, 'значение на экране сразу');
  assert.equal(row(state.journal, WED, 'Гакк-жим').pending, true);
  assert.equal(state.pending, 1);
  assert.equal(bridge.calls.length, calls, 'запрос ещё не ушёл');
  assert.equal(findRow(world.spreadsheet, WED, 'Гакк-жим').weight, '');

  await clock.advance(FLUSH_DELAY);
  assert.equal(bridge.calls.length, calls + 1);
  assert.deepEqual(bridge.calls.at(-1).body.entries, [{ date: WED, exercise: 'Гакк-жим', weight: 40, sets: [15, null, null] }]);
  const sheetRow = findRow(world.spreadsheet, WED, 'Гакк-жим');
  assert.equal(sheetRow.weight, 40);
  assert.deepEqual(sheetRow.sets, [15, '', '']);

  state = sync.getState();
  assert.equal(state.pending, 0);
  assert.equal(state.phase, 'idle');
  assert.equal(row(state.journal, WED, 'Гакк-жим').weight, 40);
  assert.equal(row(state.journal, WED, 'Гакк-жим').pending, undefined, 'значение уже пришло из таблицы');
  assert.deepEqual(onlyInputCells(world.spreadsheet), []);
  assert.equal(protectedSnapshot(world.spreadsheet), before);
  assert.deepEqual(clock.scheduled(), [], 'после удачной отправки таймеров не осталось');
});

test('без сети запись ждёт на телефоне и доходит после её появления', async () => {
  const { sync, world, control, clock, bridge } = await connected();
  control.offline = true;
  sync.queue(row(sync.getState().journal, WED, 'Гакк-жим'), { weight: 40, sets: [15, 14, null] });
  await clock.advance(FLUSH_DELAY);
  let state = sync.getState();
  assert.equal(state.phase, 'waiting');
  assert.equal(state.error.code, 'network');
  assert.equal(state.pending, 1);
  assert.equal(row(state.journal, WED, 'Гакк-жим').weight, 40, 'запись остаётся на экране');
  assert.equal(findRow(world.spreadsheet, WED, 'Гакк-жим').weight, '');

  // повторы идут с растущей паузой: 5, 15, 30 секунд…
  const attempts = bridge.calls.length;
  assert.deepEqual(clock.scheduled(), [5000]);
  await clock.advance(5000);
  assert.equal(bridge.calls.length, attempts + 1);
  assert.deepEqual(clock.scheduled(), [15000]);
  await clock.advance(15000);
  assert.deepEqual(clock.scheduled(), [30000]);
  assert.equal(sync.getState().pending, 1);

  control.offline = false;
  sync.wake();
  await clock.settle();
  state = sync.getState();
  assert.equal(state.phase, 'idle');
  assert.equal(state.error, null);
  assert.equal(state.pending, 0);
  assert.deepEqual(findRow(world.spreadsheet, WED, 'Гакк-жим').sets, [15, 14, '']);
  assert.deepEqual(clock.scheduled(), []);
});

test('когда телефон сам знает, что сети нет, запросы не отправляются', async () => {
  const { sync, online, bridge, clock } = await connected();
  const calls = bridge.calls.length;
  online.value = false;
  sync.queue(row(sync.getState().journal, WED, 'Гакк-жим'), { weight: 40 });
  await clock.advance(FLUSH_DELAY);
  assert.equal(bridge.calls.length, calls);
  assert.equal(sync.getState().phase, 'waiting');
  assert.equal(sync.getState().error.code, 'offline');
  online.value = true;
  sync.wake();
  await clock.settle();
  assert.equal(sync.getState().pending, 0);
  assert.equal(bridge.calls.length, calls + 1);
});

test('очередь переживает закрытие приложения', async () => {
  const backend = memoryBackend();
  const world = boot();
  const first = await connected({ backend, world, control: {} });
  first.control.offline = true;
  first.sync.queue(row(first.sync.getState().journal, WED, 'Гакк-жим'), { weight: 40, sets: [15, 15, null] });
  first.sync.queue(row(first.sync.getState().journal, WED, 'Сведение рук'), { note: 'сиденье 3' });
  await first.clock.advance(FLUSH_DELAY);
  first.sync.stop(); // приложение закрыли без сети

  const second = setup({ backend, world });
  const state = second.sync.getState();
  assert.equal(state.configured, true, 'подключение помнится');
  assert.equal(state.pending, 2);
  assert.equal(row(state.journal, WED, 'Гакк-жим').weight, 40, 'запись видна и без сети');
  assert.equal(state.journal.length, 16 + 11 * 23, 'журнал открыт из сохранённого снимка');
  await second.sync.sync();
  assert.equal(second.sync.getState().pending, 0);
  assert.equal(findRow(world.spreadsheet, WED, 'Гакк-жим').weight, 40);
  assert.equal(findRow(world.spreadsheet, WED, 'Сведение рук').note, 'сиденье 3');
});

test('правка, сделанная пока запрос в пути, уходит следующим кругом', async () => {
  const { sync, world, control, clock, bridge } = await connected();
  let release;
  control.gate = new Promise((resolve) => {
    release = resolve;
  });
  const target = row(sync.getState().journal, WED, 'Гакк-жим');
  sync.queue(target, { weight: 40, sets: [15, null, null] });
  await clock.advance(FLUSH_DELAY);
  assert.equal(sync.getState().phase, 'syncing');
  const inFlight = bridge.calls.length;
  sync.queue(target, { sets: [15, 14, null] }); // второй подход записан, пока первый запрос не вернулся
  sync.sync(); // и пользователь ещё нажал «Обновить»
  assert.equal(bridge.calls.length, inFlight, 'второй запрос не уходит параллельно');
  control.gate = null;
  release();
  await clock.settle();
  await clock.settle();
  assert.equal(bridge.calls.length, inFlight + 1);
  assert.deepEqual(bridge.calls.at(-1).body.entries[0].sets, [15, 14, null]);
  assert.deepEqual(findRow(world.spreadsheet, WED, 'Гакк-жим').sets, [15, 14, '']);
  assert.equal(sync.getState().pending, 0);
  assert.equal(sync.getState().phase, 'idle');
});

test('запись в строку, которой нет в таблице, попадает в список ошибок', async () => {
  const { sync, clock, world } = await connected();
  sync.queue({ date: '2026-11-08', exercise: 'Гакк-жим' }, { weight: 40 });
  sync.queue(row(sync.getState().journal, WED, 'Гакк-жим'), { weight: 30 });
  await clock.advance(FLUSH_DELAY);
  const state = sync.getState();
  assert.equal(state.pending, 0);
  assert.equal(state.phase, 'idle');
  assert.equal(state.failed.length, 1);
  assert.equal(state.failed[0].status, 'not_found');
  assert.equal(findRow(world.spreadsheet, WED, 'Гакк-жим').weight, 30, 'остальные записи дошли');
  sync.dropFailed(0);
  assert.equal(sync.getState().failed.length, 0);
});

test('неверный ключ останавливает отправку и не теряет записи', async () => {
  const { sync, world, clock } = await connected();
  world.script.resetKey(); // владелец сменил ключ в таблице
  sync.queue(row(sync.getState().journal, WED, 'Гакк-жим'), { weight: 40 });
  await clock.advance(FLUSH_DELAY);
  let state = sync.getState();
  assert.equal(state.phase, 'error');
  assert.equal(state.error.code, 'unauthorized');
  assert.equal(state.pending, 1);
  assert.deepEqual(clock.scheduled(), [], 'повторы бессмысленны, пока ключ не поправят');

  const key = world.script.resetKey();
  assert.deepEqual(await sync.connect({ url: URL, key }), { ok: true });
  await clock.advance(0);
  state = sync.getState();
  assert.equal(state.pending, 0);
  assert.equal(findRow(world.spreadsheet, WED, 'Гакк-жим').weight, 40);
});

test('страница вместо данных и занятая таблица лечатся повтором', async () => {
  const { sync, world, control, clock } = await connected();
  control.html = true;
  sync.queue(row(sync.getState().journal, WED, 'Гакк-жим'), { weight: 40 });
  await clock.advance(FLUSH_DELAY);
  assert.equal(sync.getState().phase, 'waiting');
  assert.equal(sync.getState().error.code, 'not_json');
  control.html = false;
  world.state.lock.available = false; // идёт другая запись
  await clock.advance(5000);
  assert.equal(sync.getState().error.code, 'busy');
  assert.deepEqual(clock.scheduled(), [5000]);
  world.state.lock.available = true;
  await clock.advance(5000);
  assert.equal(sync.getState().phase, 'idle');
  assert.equal(findRow(world.spreadsheet, WED, 'Гакк-жим').weight, 40);
});

test('правка руками в таблице появляется после обновления', async () => {
  const { sync, world, clock } = await connected();
  const target = findRow(world.spreadsheet, WED, 'Гакк-жим');
  world.journal.manualEdit(target.row, 5, 37.5);
  world.journal.manualEdit(target.row, 12, 'поправил в таблице');
  assert.equal(row(sync.getState().journal, WED, 'Гакк-жим').weight, null);
  assert.deepEqual(await sync.sync(), { ok: true });
  const fresh = row(sync.getState().journal, WED, 'Гакк-жим');
  assert.equal(fresh.weight, 37.5);
  assert.equal(fresh.note, 'поправил в таблице');

  // возврат в приложение через пару минут сам перечитывает журнал
  world.journal.manualEdit(target.row, 5, 42.5);
  await clock.advance(30_000);
  sync.wake();
  await clock.settle();
  assert.equal(row(sync.getState().journal, WED, 'Гакк-жим').weight, 37.5, 'свежий снимок не перечитывается');
  await clock.advance(60_000);
  sync.wake();
  await clock.settle();
  assert.equal(row(sync.getState().journal, WED, 'Гакк-жим').weight, 42.5);
});

test('большая очередь уходит несколькими запросами', async () => {
  const { sync, world, bridge, clock } = await connected();
  const rows = sync.getState().journal.filter((r) => r.workout !== 'Ходьба').slice(0, 150);
  rows.forEach((r, i) => sync.queue(r, { weight: 20 + (i % 10) }));
  const calls = bridge.calls.length;
  await clock.advance(FLUSH_DELAY);
  assert.equal(bridge.calls.length, calls + 2);
  assert.equal(sync.getState().pending, 0);
  assert.equal(world.journal.writes.length, 150);
  assert.deepEqual(onlyInputCells(world.spreadsheet), []);
});

test('смена подключения отбрасывает ответ старого запроса', async () => {
  const { sync, control, clock } = await connected();
  let release;
  control.gate = new Promise((resolve) => {
    release = resolve;
  });
  sync.queue(row(sync.getState().journal, WED, 'Гакк-жим'), { weight: 40 });
  await clock.advance(FLUSH_DELAY);
  assert.equal(sync.getState().phase, 'syncing');
  sync.reset();
  assert.equal(sync.getState().phase, 'unconfigured');
  release();
  await clock.settle();
  const state = sync.getState();
  assert.equal(state.phase, 'unconfigured');
  assert.equal(state.snapshot, null, 'ответ старого подключения не вернул журнал');
  assert.equal(state.journal.length, 0);
});

test('после смены ключа очередь уходит по новому подключению, даже если старый запрос ещё в пути', async () => {
  const { sync, world, control, clock, bridge } = await connected();
  let release;
  control.gate = new Promise((resolve) => {
    release = resolve;
  });
  sync.queue(row(sync.getState().journal, WED, 'Гакк-жим'), { weight: 40 });
  await clock.advance(FLUSH_DELAY);
  assert.equal(sync.getState().phase, 'syncing', 'первый запрос завис в пути');
  control.gate = null;
  assert.deepEqual(await sync.connect({ url: URL, key: KEY }), { ok: true }); // ключ вставили заново
  await clock.advance(0);
  assert.equal(sync.getState().pending, 1, 'пока старый запрос не вернулся, запись ждёт');
  const before = bridge.calls.length;
  release();
  await clock.settle();
  await clock.advance(0);
  assert.equal(bridge.calls.length, before + 1, 'очередь отправлена ещё раз, уже по новому подключению');
  assert.equal(sync.getState().pending, 0);
  assert.equal(sync.getState().phase, 'idle');
  assert.deepEqual(clock.scheduled(), []);
  assert.equal(findRow(world.spreadsheet, WED, 'Гакк-жим').weight, 40);
  assert.equal(row(sync.getState().journal, WED, 'Гакк-жим').weight, 40);
});

test('сброс забывает подключение, журнал и очередь, но не трогает чужие ключи', async () => {
  const backend = memoryBackend();
  backend.setItem('other-app:setting', 'x');
  const { sync } = await connected({ backend });
  sync.queue({ date: WED, exercise: 'Гакк-жим' }, { weight: 40 });
  sync.reset();
  const state = sync.getState();
  assert.equal(state.configured, false);
  assert.equal(state.pending, 0);
  assert.equal(state.snapshot, null);
  assert.deepEqual([...backend.map.keys()], ['other-app:setting']);
});

test('хранилище: приставка, запасной вариант в памяти и очистка только своих ключей', () => {
  const backend = memoryBackend();
  const storage = createStorage(backend);
  assert.equal(storage.persistent, true);
  assert.equal(storage.set('settings', { rest: 90 }), true);
  assert.deepEqual(storage.get('settings'), { rest: 90 });
  assert.equal(backend.getItem(`${PREFIX}settings`), '{"rest":90}');
  assert.equal(storage.get('missing', 'запасное'), 'запасное');
  backend.setItem(`${PREFIX}broken`, '{не json');
  assert.equal(storage.get('broken', 1), 1);
  backend.setItem('foreign', 'x');
  storage.clear();
  assert.deepEqual([...backend.map.keys()], ['foreign']);

  const blocked = { setItem() { throw new Error('QuotaExceededError'); }, getItem: () => null, removeItem() {}, key: () => null, length: 0 };
  const memory = createStorage(blocked);
  assert.equal(memory.persistent, false);
  assert.equal(memory.set('a', 1), true);
  assert.equal(memory.get('a'), 1);
  assert.equal(createStorage().persistent, false);
});

test('если телефон не дал сохранить очередь, приложение об этом знает', async () => {
  const backend = memoryBackend();
  const { sync } = await connected({ backend });
  const original = backend.setItem;
  backend.setItem = (key, value) => {
    if (key.endsWith('outbox')) throw new Error('QuotaExceededError');
    original(key, value);
  };
  sync.queue({ date: WED, exercise: 'Гакк-жим' }, { weight: 40 });
  assert.equal(sync.getState().outboxSaved, false);
  assert.equal(sync.getState().pending, 1, 'запись всё равно в памяти и уйдёт при первой возможности');
  sync.stop();
});
