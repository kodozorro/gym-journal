// Общие помощники тестов: настоящий apps-script/Code.gs, запущенный поверх таблицы в памяти.

import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { createGasEnvironment, loadAppsScript, post } from '../tools/gas-fake.mjs';
import { buildSpreadsheet } from '../tools/fixture.mjs';

export const ROOT = path.join(path.dirname(fileURLToPath(import.meta.url)), '..');
export const CODE_GS = path.join(ROOT, 'apps-script', 'Code.gs');
export const KEY = 'test-key-0123456789abcdef0123456789abcdef';

// Столбцы, в которые скрипту разрешено писать: E–J и L.
export const INPUT_COLUMNS = new Set([5, 6, 7, 8, 9, 10, 12]);

/**
 * Поднимает скрипт мостика поверх учебной таблицы.
 * @param {object} [options]
 * @param {object|null} [options.spreadsheet] готовая таблица; null — скрипт без таблицы
 * @param {object} [options.sheet] параметры buildSpreadsheet
 * @param {boolean} [options.noKey] не создавать ключ в свойствах скрипта
 */
export function boot(options = {}) {
  const spreadsheet = options.spreadsheet === null ? null : options.spreadsheet ?? buildSpreadsheet(options.sheet);
  const logs = [];
  const environment = createGasEnvironment({
    spreadsheet,
    properties: options.noKey ? {} : { GJ_KEY: KEY },
    logs,
  });
  const script = loadAppsScript(CODE_GS, environment);
  const call = (body) => post(script, typeof body === 'string' ? body : { key: KEY, ...body }).json;
  const journal = spreadsheet ? spreadsheet.getSheetByName('Журнал') : null;
  return { spreadsheet, journal, environment, state: environment.state, script, call, logs };
}

/** Все записи скрипта попали только в ячейки ввода и ничего не задели. */
export function onlyInputCells(spreadsheet) {
  const problems = [...spreadsheet.violations];
  for (const sheet of spreadsheet.sheets) {
    for (const write of sheet.writes) {
      if (sheet.name !== 'Журнал') problems.push({ kind: 'foreign-sheet', sheet: sheet.name, ...write });
      else if (!INPUT_COLUMNS.has(write.col) || write.row < 3) problems.push({ kind: 'outside-input', ...write });
    }
  }
  return problems;
}

/** localStorage в памяти: один и тот же объект можно отдать двум «запускам» приложения. */
export function memoryBackend() {
  const map = new Map();
  return {
    map,
    getItem: (key) => (map.has(key) ? map.get(key) : null),
    setItem: (key, value) => {
      map.set(key, String(value));
    },
    removeItem: (key) => {
      map.delete(key);
    },
    key: (i) => [...map.keys()][i] ?? null,
    get length() {
      return map.size;
    },
  };
}

const settle = () => new Promise((resolve) => setImmediate(resolve));

/** Ручные часы и таймеры для движка синхронизации. */
export function fakeClock(start = 1_800_000_000_000) {
  let time = start;
  let seq = 0;
  const timers = new Map();
  return {
    now: () => time,
    setTimer: (fn, ms) => {
      seq += 1;
      timers.set(seq, { at: time + ms, fn });
      return seq;
    },
    clearTimer: (id) => {
      timers.delete(id);
    },
    /** Через сколько миллисекунд сработают заведённые таймеры. */
    scheduled: () => [...timers.values()].map((t) => t.at - time).sort((a, b) => a - b),
    settle,
    /** Проматывает время, по очереди запуская созревшие таймеры и дожидаясь их последствий. */
    async advance(ms) {
      const target = time + ms;
      await settle();
      for (;;) {
        const due = [...timers.entries()].filter(([, t]) => t.at <= target).sort((a, b) => a[1].at - b[1].at)[0];
        if (!due) break;
        timers.delete(due[0]);
        time = due[1].at;
        due[1].fn();
        await settle();
      }
      time = target;
      await settle();
    },
  };
}

/**
 * fetch, который вместо сети вызывает doPost настоящего скрипта.
 * control.offline — «нет сети»; control.html — страница входа Google вместо JSON;
 * control.gate — обещание, которого ждёт каждый запрос (чтобы поймать «запрос в пути»).
 */
export function bridgeFetch(script, control = {}) {
  const calls = [];
  const fetchFn = async (url, init) => {
    const call = { url, init, body: JSON.parse(init.body) };
    calls.push(call);
    if (control.gate) await control.gate;
    if (control.offline) throw new TypeError('Failed to fetch');
    if (control.html) return new Response('<!doctype html><title>Вход</title>', { status: 200 });
    const out = script.doPost({ postData: { contents: init.body, type: 'text/plain' } });
    call.response = JSON.parse(out.getContent());
    return new Response(out.getContent(), { status: 200, headers: { 'Content-Type': 'application/json' } });
  };
  return { fetch: fetchFn, calls, control };
}
