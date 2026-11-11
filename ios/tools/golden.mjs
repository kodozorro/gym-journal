// Эталоны для тестов на Swift: что на тех же данных выдаёт логика веб-приложения и настоящий
// скрипт таблицы. Тесты пакета ios/Core сверяют с ними свой перенос этой логики.
//
// Все числа учебные: таблица в памяти из tools/fixture.mjs.

import { createGasEnvironment, loadAppsScript, post } from '../../tools/gas-fake.mjs';
import { buildSpreadsheet, fillHistory, PROGRAM } from '../../tools/fixture.mjs';
import * as dates from '../../js/core/dates.js';
import * as numbers from '../../js/core/numbers.js';
import * as plan from '../../js/core/plan.js';
import * as journal from '../../js/core/journal.js';
import * as stats from '../../js/core/stats.js';
import * as scale from '../../js/core/scale.js';
import * as keypad from '../../js/core/keypad.js';
import * as guide from '../../js/core/guide.js';
import * as timer from '../../js/core/timer.js';
import * as outbox from '../../js/core/outbox.js';
import { normalizeBridgeUrl, extractConnection } from '../../js/data/api.js';
import { daySummary, errorText, fmt } from '../../js/ui/parts.js';
import { describeFields, syncText } from '../../js/ui/settings.js';
import { weekOfDate } from '../../js/ui/plan.js';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = path.join(path.dirname(fileURLToPath(import.meta.url)), '..', '..');
const CODE_GS = path.join(ROOT, 'apps-script', 'Code.gs');

/** Учебные ключ и адрес: те же, что в тестах веб-приложения. */
export const KEY = '0123456789abcdef0123456789abcdef01234567';
export const URL = 'https://script.google.com/macros/s/TESTDEPLOYMENTID_0123456789/exec';
export const TODAY = '2026-11-25';
export const START = '2026-11-09';
export const SKIPPED = '2026-11-19';

function bootScript({ history = true } = {}) {
  const spreadsheet = buildSpreadsheet({ start: START });
  if (history) fillHistory(spreadsheet, { before: TODAY, skip: [SKIPPED] });
  const environment = createGasEnvironment({ spreadsheet, properties: { GJ_KEY: KEY } });
  const script = loadAppsScript(CODE_GS, environment);
  return { spreadsheet, environment, script };
}

/** Ответ настоящего скрипта на запрос pull: из него приложение берёт учебный журнал. */
export function buildPull() {
  const { script } = bootScript();
  return post(script, { key: KEY, action: 'pull' }).json;
}

const parsed = (value) => (value === undefined ? { kind: 'invalid' } : value === null ? { kind: 'empty' } : { kind: 'value', value });

function goldenDates() {
  const list = ['2026-11-09', '2026-11-25', '2026-12-31', '2027-01-01', '2024-02-29', '2026-03-29', '2025-12-28', '2026-01-04', '2030-06-15', '2026-05-07', '2026-08-01', '2026-09-30', '2026-02-01', '2026-07-12', '2026-10-05', '2026-04-18'];
  return {
    days: list.map((iso) => ({
      iso,
      weekday: dates.isoWeekday(iso),
      monday: dates.mondayOf(iso),
      sheet: dates.formatSheetDay(iso),
      long: dates.formatLongDay(iso),
      short: dates.formatShortDay(iso),
      numeric: dates.formatNumericDay(iso),
      plus1: dates.addDays(iso, 1),
      minus14: dates.addDays(iso, -14),
      plus45: dates.addDays(iso, 45),
    })),
    valid: ['2026-11-09', '2024-02-29', '2026-02-30', '2025-02-29', '2026-13-01', '26-11-09', '', '2026-11-9', 'abcd-ef-gh', '2026-00-10', '2026-11-00', '2026-11-31', '2026-04-31', '2026-12-31', ' 2026-11-09']
      .map((text) => ({ text, ok: dates.isISODate(text) })),
    ranges: [['2026-11-10', '2026-11-13'], ['2026-11-30', '2026-12-04'], ['2026-11-25', '2026-11-25'], ['2026-12-28', '2027-01-01'], ['2026-11-09', '2027-01-29']]
      .map(([from, to]) => ({ from, to, text: dates.formatRange(from, to) })),
    diffs: [['2026-11-25', '2026-11-09'], ['2026-11-09', '2026-11-25'], ['2027-01-01', '2026-12-31'], ['2026-03-30', '2026-03-28'], ['2024-03-01', '2024-02-28']]
      .map(([a, b]) => ({ a, b, days: dates.diffDays(a, b) })),
  };
}

function goldenNumbers() {
  const inputs = ['42,5', '42.5', ',5', '.5', '5,', '', ' ', '1 000', 'abc', '1,2,3', '12a', '-5', '+5', '007', '0', '1e3', '12', '3.', '.', ',', '0,0', '15 ', ' 7,25'];
  return {
    decimal: inputs.map((text) => ({ text, out: parsed(numbers.parseDecimal(text)) })),
    count: inputs.map((text) => ({ text, out: parsed(numbers.parseCount(text)) })),
    format: [[42.5], [40], [3.25], [3.256], [3.254], [0.1 + 0.2], [1000], [2.5, 1], [2.45, 1], [2.55, 1], [12.345, 0], [12.5, 0], [0], [17.5], [1.005], [100.999]]
      .map(([value, digits]) => ({ value, digits: digits ?? 2, text: numbers.formatNumber(value, digits) })),
    round: [[1.005, 2], [2.675, 2], [1.45, 1], [0.125, 2], [20, 2], [0.1 + 0.2, 2], [1.255, 2], [17.5 + 2.5, 2], [3 + 1.5 + 1.5, 2], [36.6, 0], [18 + 18.5, 1]]
      .map(([value, digits]) => ({ value, digits, out: numbers.roundTo(value, digits) })),
    plural: [0, 1, 2, 3, 4, 5, 6, 11, 12, 13, 14, 21, 22, 25, 101, 111, 112, 1000]
      .map((n) => ({ n, text: numbers.plural(n, 'упражнение', 'упражнения', 'упражнений') })),
  };
}

function goldenPlans() {
  const texts = [...new Set([
    ...PROGRAM.flatMap((line) => line.slice(3)),
    '3x10', '2 х 8-10', '3*12', '10 × 5', '0 × 5', '3 × 12–10', '3 × 10 на руку', '2 × 15 на сторону',
    '5 KM', '', 'отдых', '  2 × 12–15 на ногу  ', '12 × 3', '3 X 8 — 10', '4,5 км', '3.5 км в гору', '10–12',
  ])];
  return texts.map((text) => ({ text, plan: plan.parsePlan(text), strength: plan.strengthPlan(text) }));
}

function goldenJournal(rows) {
  const days = journal.groupDays(rows);
  const start = START;
  const weeks = stats.weeksOf(rows, start);
  const exercises = stats.exerciseList(rows);
  return {
    rows: rows.map((row) => {
      const last = journal.lastTime(rows, row);
      return {
        key: journal.rowKey(row),
        walk: journal.isWalk(row),
        done: journal.isDone(row),
        data: journal.hasData(row),
        next: journal.nextSetIndex(row),
        slots: journal.slotCount(row),
        summary: journal.summarize(row, fmt),
        plannedKm: journal.plannedKm(row),
        week: journal.weekOf({ ...row, week: null }, start),
        last: last ? journal.rowKey(last) : null,
        progression: journal.progression(last, 2.5),
        pace: journal.paceOf(row.km, row.min),
      };
    }),
    days: days.map((day) => ({
      date: day.date,
      week: day.week,
      count: day.rows.length,
      title: journal.workoutTitle(day.rows),
      badge: journal.workoutBadge(day.rows),
      status: journal.dayStatus(day.rows, day.date, TODAY),
      progress: journal.dayProgress(day.rows),
      summary: daySummary(day.rows),
      pairs: journal.splitDay(day.rows).pairs.map((pair) => pair.map(journal.rowKey)),
      walks: journal.splitDay(day.rows).walks.map(journal.rowKey),
    })),
    stats: {
      exercises,
      best: exercises.map((name) => ({ name, weeks: stats.weeklyBest(rows, name, start) })),
      walk: stats.weeklyWalk(rows, start),
      weeks: weeks.map((week) => ({ week: week.week, dates: week.days.map((day) => day.date) })),
      history: exercises.map((name) => ({ name, keys: stats.exerciseHistory(rows, name).map(journal.rowKey) })),
      weekOfToday: weekOfDate(weeks, TODAY),
      weekStart3: stats.weekStart(start, 3),
    },
  };
}

function goldenScale() {
  const cases = [
    [15, 17.5, {}], [0, 13, { fromZero: true }], [40, 40, {}], [0, 0, {}], [0, 0, { fromZero: true }],
    [2.5, 62.5, {}], [8.5, 17, { fromZero: true }], [100, 250, {}], [0.4, 0.9, {}], [5, 5, { fromZero: true }],
    [17, 3, { fromZero: true }], [20, 22.5, { count: 5 }],
  ];
  return cases.map(([min, max, options]) => ({
    min, max, fromZero: Boolean(options.fromZero), count: options.count ?? 4, out: scale.niceScale(min, max, options),
  }));
}

function goldenKeypad() {
  const run = (spec, keys) => {
    let field = keypad.makeField(spec);
    const steps = [];
    for (const key of keys) {
      field = keypad.pressKey(field, key);
      steps.push({ key, text: field.text, fresh: field.fresh });
    }
    return {
      spec: { ...spec, value: spec.value ?? null, max: spec.max ?? null },
      initial: keypad.makeField(spec).text,
      steps,
      value: parsed(keypad.fieldValue(field)),
      error: keypad.fieldError(field),
    };
  };
  return [
    run({ name: 'weight', value: 25, max: 1000, digits: 2, whole: 4 }, ['2', '7', ',', '5']),
    run({ name: 'weight', value: 27.5, max: 1000, digits: 2, whole: 4 }, ['back', '3', '0']),
    run({ name: 'weight', value: null, max: 1000, digits: 2, whole: 4 }, [',', '5', '5', '5']),
    run({ name: 'weight', value: null, max: 1000, digits: 2, whole: 4 }, ['1', '2', '3', '4', '5']),
    run({ name: 'weight', value: null, max: 1000, digits: 2, whole: 4 }, ['9', '9', '9', '9']),
    run({ name: 'reps', value: 12, integer: true, max: 500, whole: 3 }, [',', '1', '5']),
    run({ name: 'reps', value: null, integer: true, max: 500, whole: 3 }, ['0', '0', '7']),
    run({ name: 'reps', value: null, integer: true, max: 500, whole: 3 }, ['9', '9', '9']),
    run({ name: 'km', value: 1.5, max: 200, digits: 2, whole: 3 }, [',']),
    run({ name: 'km', value: 1.5, max: 200, digits: 2, whole: 3 }, ['back', 'back']),
    run({ name: 'km', value: null, max: 200, digits: 2, whole: 3 }, ['3', ',']),
    run({ name: 'min', value: 18, max: 1440, digits: 1, whole: 4 }, ['1', '8', ',', '5', '5']),
    run({ name: 'min', value: null, max: 1440, digits: 1, whole: 4 }, []),
  ];
}

function goldenGuide() {
  const pairs = [
    ...PROGRAM.map((line) => ({ exercise: line[1], machine: line[2] })),
    ...PROGRAM.map((line) => ({ exercise: line[1], machine: '' })),
    { exercise: 'Сведение рук', machine: 'Pec Deck Machine' },
    { exercise: 'Жим ногами', machine: 'Неизвестный тренажёр № 5' },
    { exercise: 'Приседания', machine: '' },
    { exercise: 'Тяга сидя', machine: 'Low Pulley Row' },
    { exercise: 'Ходьба в гору', machine: 'Treadmill' },
    { exercise: 'ЖИМ  ВВЕРХ', machine: '  Shoulder Press  ' },
    { exercise: 'Что-то ещё', machine: 'Hack Squat & Co (v2)' },
  ];
  return {
    rule: guide.STRENGTH_RULE,
    legend: guide.LEGEND,
    photos: guide.guidePhotos().map((src) => src.replace(guide.PHOTO_DIR, '').replace(/\.webp$/, '')),
    art: guide.guideArt().slice().sort(),
    cases: pairs.map((row) => {
      const out = guide.guideFor(row);
      const machine = guide.machineOf(row.machine);
      return {
        ...row,
        out: {
          ...out,
          photo: out.photo ? out.photo.src.replace(guide.PHOTO_DIR, '').replace(/\.webp$/, '') : null,
          machineType: machine ? machine.id : '',
        },
      };
    }),
  };
}

function goldenTimer() {
  const t0 = 1_800_000_000_000;
  const rest = timer.startRest(t0, 90);
  const at = [0, 1, 999, 1000, 45_000, 89_001, 90_000, 90_999, 91_000, 150_000];
  const extendedEarly = timer.extendRest(rest, t0 + 60_000, 30);
  const extendedLate = timer.extendRest(rest, t0 + 100_000, 30);
  const shape = (value) => ({ startedAt: value.startedAt - t0, endsAt: value.endsAt - t0, total: value.total });
  return {
    clock: [0, 5, 59, 60, 90, 90.4, 90.5, 600, 3599, -3].map((seconds) => ({ seconds, text: timer.formatClock(seconds) })),
    rest: at.map((ms) => ({
      ms,
      left: timer.restLeft(rest, t0 + ms),
      over: timer.restOver(rest, t0 + ms),
      overtime: timer.restOvertime(rest, t0 + ms),
      progress: timer.restProgress(rest, t0 + ms),
    })),
    extendedEarly: shape(extendedEarly),
    extendedLate: shape(extendedLate),
  };
}

function goldenBridge() {
  const urls = [
    URL,
    `  ${URL}  `,
    `<${URL}>`,
    `«${URL}»`,
    `${URL}?authuser=1`,
    `${URL}#top`,
    URL.replace('/exec', '/dev'),
    'https://script.google.com/a/macros/example.org/s/TESTDEPLOYMENTID_0123456789/exec',
    'https://script.google.com/a/example.org/macros/s/TESTDEPLOYMENTID_0123456789/exec',
    'http://script.google.com/macros/s/TESTDEPLOYMENTID_0123456789/exec',
    'https://script.google.com.evil.example/macros/s/TESTDEPLOYMENTID_0123456789/exec',
    'https://example.org/macros/s/TESTDEPLOYMENTID_0123456789/exec',
    // слишком короткий ID развёртывания проверяет тест на Swift: такой адрес в файлах репозитория
    // остановил бы tests/repo.test.mjs
    'http://127.0.0.1:8080/bridge',
    'http://localhost/bridge',
    '',
    '   ',
    'просто текст',
  ];
  const texts = [
    `Адрес: ${URL}\nКлюч: ${KEY}`,
    `${KEY} ${URL}`,
    `${URL}`,
    `${KEY}`,
    `ключ ${KEY}0`,
    `"${URL}", '${KEY.toUpperCase()}'`,
    'http://127.0.0.1:8080/bridge и ключ ' + KEY,
    'ничего похожего',
    '',
  ];
  return {
    urls: urls.flatMap((text) => [false, true].map((allowLocal) => ({ text, allowLocal, out: normalizeBridgeUrl(text, { allowLocal }) }))),
    extract: texts.map((text) => {
      const out = extractConnection(text);
      return { text, url: out.url ?? null, key: out.key ?? null };
    }),
  };
}

function goldenOutbox(rows) {
  const find = (date, exercise) => rows.find((row) => row.date === date && row.exercise === exercise);
  const curl = find(TODAY, 'Сгибание ног');
  const row = find(TODAY, 'Тяга сидя широким хватом');
  const walk = find(TODAY, 'Ходьба до и после силовой');
  const steps = [
    { row: journal.rowKey(curl), fields: { sets: [12, null, null], weight: 17.5 } },
    { row: journal.rowKey(row), fields: { sets: [12, null, null] } },
    { row: journal.rowKey(row), fields: { weight: 27.5 } },
    { row: journal.rowKey(walk), fields: { km: 1.5, min: 18 } },
    { row: journal.rowKey(curl), fields: { note: 'сиденье на 4' } },
    { row: journal.rowKey(walk), fields: { km: null } },
    { row: journal.rowKey(row), fields: { sets: [12, 11, null] } },
  ];
  const byKey = new Map(rows.map((item) => [journal.rowKey(item), item]));
  let box = outbox.emptyOutbox();
  const states = [];
  steps.forEach((step, index) => {
    box = outbox.queuePatch(box, byKey.get(step.row), step.fields, 1000 + index);
    const push = outbox.buildPush(box);
    states.push({ ...step, seq: box.seq, pending: outbox.pendingCount(box), entries: push.entries, sent: push.sent });
  });
  const push = outbox.buildPush(box);
  const results = push.entries.map((entry, index) => {
    if (index === 0) return { date: entry.date, exercise: entry.exercise, status: 'written' };
    if (index === 1) return { date: entry.date, exercise: entry.exercise, status: 'rejected', reason: 'Учебный отказ.' };
    return { date: entry.date, exercise: entry.exercise, status: 'not_found', reason: 'В журнале нет строки с такой датой и упражнением.' };
  });
  // пока запрос был в пути, одну строку успели поправить
  const racing = outbox.queuePatch(box, byKey.get(push.sent[0].key), { note: 'поправили в пути' }, 2000);
  const acked = outbox.ackPush(racing, push.sent, results, 3000);
  const applied = outbox.applyOutbox(rows, box).filter((item) => item.pending).map((item) => ({
    key: journal.rowKey(item), weight: item.weight, sets: item.sets, km: item.km, min: item.min, note: item.note,
  }));
  const retried = outbox.retryFailed(acked, 0, 4000);
  return {
    steps: states,
    applied,
    ack: {
      sent: push.sent,
      results,
      racingKey: push.sent[0].key,
      pendingKeys: Object.keys(acked.items).sort(),
      failed: acked.failed.map((item) => ({ key: journal.rowKey(item), status: item.status, reason: item.reason, describe: describeFields(item.fields) })),
    },
    retry: {
      pendingKeys: Object.keys(retried.items).sort(),
      failed: retried.failed.map((item) => journal.rowKey(item)),
      entries: outbox.buildPush(retried).entries,
    },
  };
}

function goldenTexts() {
  const now = 1_800_000_000_000;
  const errors = [
    { code: 'unauthorized', message: 'Неверный ключ.' },
    { code: 'no_key', message: 'Ключ ещё не создан: запустите функцию setup в редакторе скрипта.' },
    { code: 'layout_changed', message: 'Лист «Журнал» изменился: столбец 5 называется «Вес», а должен «Вес, кг».' },
    { code: 'no_journal', message: 'В таблице нет листа «Журнал».' },
    { code: 'no_spreadsheet', message: 'Скрипт не привязан к таблице.' },
    { code: 'api_mismatch', message: 'Скрипт в таблице другой версии. Обновите код скрипта по инструкции и выпустите новую версию развёртывания.' },
    { code: 'too_many', message: 'Слишком много записей в одном запросе.' },
    { code: 'bridge', message: '' },
  ];
  const base = { configured: true, phase: 'idle', error: null, pending: 0, online: true, retryAt: null, failed: [] };
  const states = [
    { ...base, configured: false },
    { ...base, phase: 'syncing' },
    { ...base, phase: 'error', error: errors[0] },
    { ...base, phase: 'error', error: errors[2] },
    { ...base, phase: 'error', error: null },
    { ...base, pending: 2, online: false },
    { ...base, pending: 2, phase: 'waiting', error: { code: 'network', message: 'Нет связи со скриптом таблицы.' }, retryAt: now + 14_200 },
    { ...base, pending: 2, phase: 'waiting', error: null, retryAt: null },
    { ...base, pending: 1 },
    { ...base, phase: 'waiting', error: { code: 'timeout', message: 'Скрипт таблицы не ответил вовремя.' } },
    { ...base, phase: 'waiting', error: null },
    { ...base, online: false },
    { ...base, failed: [{}, {}] },
    { ...base },
  ];
  const fieldSets = [
    { weight: 27.5 },
    { weight: null },
    { sets: [12, 11, null] },
    { sets: [null, null, null] },
    { km: 1.5, min: 18 },
    { km: null, min: null },
    { note: 'сиденье на 4' },
    { note: '' },
    { weight: 30, sets: [10, null, 9], note: 'тяжело' },
  ];
  return {
    now,
    errors: errors.map((error) => ({ ...error, out: errorText(error) })),
    sync: states.map((state) => ({
      configured: state.configured,
      phase: state.phase,
      error: state.error,
      pending: state.pending,
      online: state.online,
      retryIn: state.retryAt === null ? null : (state.retryAt - now) / 1000,
      failed: state.failed.length,
      text: syncText(state, now),
    })),
    fields: fieldSets.map((fields) => ({ fields, text: describeFields(fields) })),
  };
}

/** Все эталоны одним объектом. */
export function buildGolden() {
  const pull = buildPull();
  const rows = journal.normalizeJournal(pull.journal);
  return {
    today: TODAY,
    start: START,
    dates: goldenDates(),
    numbers: goldenNumbers(),
    plans: goldenPlans(),
    journal: goldenJournal(rows),
    scale: goldenScale(),
    keypad: goldenKeypad(),
    guide: goldenGuide(),
    timer: goldenTimer(),
    bridge: goldenBridge(),
    outbox: goldenOutbox(rows),
    texts: goldenTexts(),
  };
}

/**
 * Запросы к настоящему скрипту и его ответы, по порядку. Учебная таблица в приложении на Swift
 * обязана отвечать на те же запросы так же.
 */
export function buildBridgeCases() {
  const { script } = bootScript();
  const good = { key: KEY };
  const entry = (fields) => ({ date: TODAY, exercise: 'Гакк-жим', ...fields });
  const walk = (fields) => ({ date: TODAY, exercise: 'Ходьба до и после силовой', ...fields });
  const requests = [
    { name: 'пустой запрос', raw: '' },
    { name: 'не JSON', raw: 'привет' },
    { name: 'не объект', raw: '[1, 2]' },
    { name: 'строка вместо объекта', raw: '"ping"' },
    { name: 'нет ключа', body: { action: 'ping' } },
    { name: 'чужой ключ', body: { key: 'не тот', action: 'ping' } },
    { name: 'ключ не строка', body: { key: 5, action: 'ping' } },
    { name: 'ping', body: { ...good, action: 'ping' } },
    { name: 'неизвестное действие', body: { ...good, action: 'drop' } },
    { name: 'нет действия', body: { ...good } },
    { name: 'push без списка', body: { ...good, action: 'push' } },
    { name: 'push со строкой вместо списка', body: { ...good, action: 'push', entries: 'x' } },
    { name: 'пустой push', body: { ...good, action: 'push', entries: [] } },
    { name: 'вес и подходы', body: { ...good, action: 'push', entries: [entry({ weight: 22.5, sets: [12, 11, null] })] } },
    { name: 'то же ещё раз', body: { ...good, action: 'push', entries: [entry({ weight: 22.5, sets: [12, 11, null] })] } },
    { name: 'округление веса', body: { ...good, action: 'push', entries: [entry({ weight: 22.456 })] } },
    { name: 'стереть вес', body: { ...good, action: 'push', entries: [entry({ weight: null })] } },
    { name: 'заметка с пробелами', body: { ...good, action: 'push', entries: [entry({ note: '  сиденье на 4 \n' })] } },
    { name: 'стереть заметку', body: { ...good, action: 'push', entries: [entry({ note: '' })] } },
    { name: 'подходы короче трёх', body: { ...good, action: 'push', entries: [entry({ sets: [10] })] } },
    { name: 'ходьба', body: { ...good, action: 'push', entries: [walk({ km: 1.5, min: 18 })] } },
    { name: 'ходьба с округлением', body: { ...good, action: 'push', entries: [walk({ km: 3.005, min: 36.25 })] } },
    {
      name: 'ошибки в записях',
      body: {
        ...good,
        action: 'push',
        entries: [
          'строка',
          null,
          { exercise: 'Гакк-жим', weight: 20 },
          { date: '2026-02-30', exercise: 'Гакк-жим', weight: 20 },
          { date: TODAY, weight: 20 },
          { date: TODAY, exercise: '', weight: 20 },
          entry({ occ: -1, weight: 20 }),
          entry({ occ: 1.5, weight: 20 }),
          entry({ occ: 51, weight: 20 }),
          entry({ occ: 'x', weight: 20 }),
          entry({ weight: -1 }),
          entry({ weight: 1000.5 }),
          entry({ weight: '20' }),
          entry({ sets: 12 }),
          entry({ sets: [1, 2, 3, 4] }),
          entry({ sets: [10.5, null, null] }),
          entry({ sets: [501] }),
          entry({ sets: ['10'] }),
          entry({ km: 1 }),
          entry({ min: 10 }),
          walk({ weight: 10 }),
          walk({ sets: [1] }),
          walk({ km: 201 }),
          walk({ min: 1441 }),
          walk({ km: '3' }),
          entry({ note: 5 }),
          entry({ note: 'я'.repeat(501) }),
          { date: '2031-01-01', exercise: 'Гакк-жим', weight: 20 },
          { date: TODAY, exercise: 'Такого нет', weight: 20 },
          entry({ occ: 2, weight: 20 }),
          entry({}),
          entry({ occ: null, weight: 21 }),
          entry({ occ: 0, sets: [null, null, null] }),
        ],
      },
    },
    { name: 'push с журналом в ответе', body: { ...good, action: 'push', pull: true, entries: [entry({ weight: 25, sets: [12, 12, 12] })] } },
    { name: 'pull', body: { ...good, action: 'pull' } },
  ];
  return requests.map((request) => {
    const raw = request.raw !== undefined ? request.raw : JSON.stringify(request.body);
    const output = script.doPost({ postData: { contents: raw, type: 'text/plain' } });
    return { name: request.name, request: raw, response: JSON.parse(output.getContent()) };
  });
}
