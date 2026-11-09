// Тесты чистой логики приложения: даты, числа, план, модель журнала, недельная статистика.

import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
  addDays, diffDays, isISODate, todayISO, isoWeekday, mondayOf,
  formatSheetDay, formatLongDay, formatShortDay, formatNumericDay, formatRange,
} from '../js/core/dates.js';
import { parseDecimal, parseCount, roundTo, formatNumber, plural } from '../js/core/numbers.js';
import { parsePlan, strengthPlan } from '../js/core/plan.js';
import {
  rowKey, isWalk, setsOf, slotCount, nextSetIndex, hasData, isDone, groupDays, weekOf, dayProgress, dayStatus,
  splitDay, roundComplete, lastTime, progression, workoutTitle, workoutBadge, plannedKm, paceOf, summarize,
} from '../js/core/journal.js';
import { weekStart, exerciseList, weeklyBest, weeklyWalk, exerciseHistory, weeksOf } from '../js/core/stats.js';

const strength = (over = {}) => ({
  date: '2026-11-11', workout: 'Силовая B', exercise: 'Гакк-жим', plan: '2 × 12–15', machine: 'Hack Press Machine',
  week: 1, weight: null, sets: [null, null, null], km: null, min: null, note: '', ...over,
});
const walk = (over = {}) => ({
  date: '2026-11-11', workout: 'Ходьба', exercise: 'Ходьба до и после силовой', plan: '3 км, наклон 1–3 %',
  machine: 'Беговая дорожка', week: 1, weight: null, sets: [null, null, null], km: null, min: null, note: '', ...over,
});

test('даты: арифметика не зависит от часового пояса и перехода на летнее время', () => {
  assert.equal(addDays('2026-11-09', 1), '2026-11-10');
  assert.equal(addDays('2026-12-28', 7), '2027-01-04');
  assert.equal(addDays('2027-03-28', 1), '2027-03-29');
  assert.equal(addDays('2028-02-28', 1), '2028-02-29');
  assert.equal(diffDays('2027-01-29', '2026-11-09'), 81);
  assert.equal(diffDays('2026-11-09', '2026-11-11'), -2);
  assert.equal(isoWeekday('2026-11-09'), 1);
  assert.equal(isoWeekday('2026-11-15'), 7);
  assert.equal(mondayOf('2026-11-13'), '2026-11-09');
  assert.equal(mondayOf('2026-11-15'), '2026-11-09');
  assert.equal(mondayOf('2026-11-16'), '2026-11-16');
});

test('даты: проверка формата', () => {
  assert.equal(isISODate('2026-11-09'), true);
  assert.equal(isISODate('2026-02-30'), false);
  assert.equal(isISODate('2026-13-01'), false);
  assert.equal(isISODate('09.11.2026'), false);
  assert.equal(isISODate(20261109), false);
  assert.equal(isISODate(null), false);
});

test('даты: «сегодня» берётся по часам устройства', () => {
  assert.equal(todayISO(new Date(2026, 10, 11, 0, 5)), '2026-11-11');
  assert.equal(todayISO(new Date(2026, 10, 11, 23, 55)), '2026-11-11');
  assert.equal(todayISO(new Date(2027, 0, 1, 7, 0)), '2027-01-01');
});

test('даты: подписи как в таблице и в интерфейсе', () => {
  assert.equal(formatSheetDay('2026-11-10'), 'вт 10.11');
  assert.equal(formatSheetDay('2027-01-01'), 'пт 01.01');
  assert.equal(formatLongDay('2026-11-11'), 'среда, 11 ноября');
  assert.equal(formatShortDay('2026-11-11'), '11 ноя');
  assert.equal(formatShortDay('2026-12-04'), '4 дек');
  assert.equal(formatShortDay('2027-05-03'), '3 мая');
  assert.equal(formatNumericDay('2026-12-04'), '04.12');
  assert.equal(formatRange('2026-11-09', '2026-11-13'), '9–13 ноя');
  assert.equal(formatRange('2026-11-30', '2026-12-04'), '30 ноя – 4 дек');
  assert.equal(formatRange('2026-11-10', '2026-11-10'), '10 ноя');
});

test('числа: запятая и точка, пусто и мусор', () => {
  assert.equal(parseDecimal('42,5'), 42.5);
  assert.equal(parseDecimal('42.5'), 42.5);
  assert.equal(parseDecimal(' 40 '), 40);
  assert.equal(parseDecimal('1 250,5'), 1250.5);
  assert.equal(parseDecimal(',5'), 0.5);
  assert.equal(parseDecimal('0'), 0);
  assert.equal(parseDecimal(''), null);
  assert.equal(parseDecimal('   '), null);
  assert.equal(parseDecimal(null), null);
  assert.equal(parseDecimal('сорок'), undefined);
  assert.equal(parseDecimal('4,2,1'), undefined);
  assert.equal(parseDecimal('-5'), undefined);
  assert.equal(parseDecimal('1e3'), undefined);
  assert.equal(parseDecimal(12.5), 12.5);
  assert.equal(parseDecimal(NaN), undefined);
  assert.equal(parseCount('12'), 12);
  assert.equal(parseCount('12,5'), undefined);
  assert.equal(parseCount(''), null);
});

test('числа: вывод и склонения', () => {
  assert.equal(formatNumber(42.5), '42,5');
  assert.equal(formatNumber(40), '40');
  assert.equal(formatNumber(3.14159), '3,14');
  assert.equal(formatNumber(0), '0');
  assert.equal(formatNumber(null), '');
  assert.equal(formatNumber(17.25, 1), '17,3');
  assert.equal(roundTo(0.1 + 0.2), 0.3);
  assert.equal(roundTo(42.5 + 2.5), 45);
  assert.equal(roundTo(1.005, 2), 1.01);
  assert.equal(plural(1, 'подход', 'подхода', 'подходов'), 'подход');
  assert.equal(plural(2, 'подход', 'подхода', 'подходов'), 'подхода');
  assert.equal(plural(5, 'подход', 'подхода', 'подходов'), 'подходов');
  assert.equal(plural(11, 'подход', 'подхода', 'подходов'), 'подходов');
  assert.equal(plural(21, 'подход', 'подхода', 'подходов'), 'подход');
  assert.equal(plural(112, 'подход', 'подхода', 'подходов'), 'подходов');
});

test('план: силовые в формате N × A–B', () => {
  assert.deepEqual(parsePlan('3 × 10–12'), { kind: 'strength', sets: 3, low: 10, high: 12, tail: '', perSide: false, text: '3 × 10–12' });
  const perLeg = parsePlan('2 × 12–15 на ногу');
  assert.equal(perLeg.sets, 2);
  assert.equal(perLeg.low, 12);
  assert.equal(perLeg.high, 15);
  assert.equal(perLeg.perSide, true);
  assert.equal(perLeg.tail, 'на ногу');
  for (const text of ['3x10', '3 х 10', '3 Х 10', '3*10', '3 X 10']) {
    const plan = parsePlan(text);
    assert.equal(plan.kind, 'strength', text);
    assert.equal(plan.sets, 3);
    assert.equal(plan.low, 10);
    assert.equal(plan.high, 10);
  }
  assert.equal(parsePlan('2 × 8-10').high, 10);
  assert.equal(parsePlan('2 × 15–12').low, 12, 'перепутанные границы упорядочиваются');
  assert.equal(parsePlan('5 × 5').sets, 3, 'в таблице только три ячейки подходов');
});

test('план: ходьба и неразборчивый текст', () => {
  assert.deepEqual(parsePlan('3 км, наклон 1–3 %'), { kind: 'cardio', km: 3, kmHigh: 3, text: '3 км, наклон 1–3 %' });
  assert.equal(parsePlan('4–4,5 км, наклон 3–6 %').km, 4);
  assert.equal(parsePlan('4–4,5 км, наклон 3–6 %').kmHigh, 4.5);
  assert.equal(parsePlan('3–3,5 км, наклон 5–6 %').kmHigh, 3.5);
  assert.equal(parsePlan('Интервалы 4 × 3 мин или 5 км ровно').km, 5);
  assert.equal(parsePlan('4 км ровно').km, 4);
  assert.deepEqual(parsePlan(''), { kind: 'cardio', km: null, kmHigh: null, text: '' });
  assert.equal(parsePlan(null).km, null);
  const unknown = strengthPlan('как получится');
  assert.equal(unknown.sets, 3);
  assert.equal(unknown.unknown, true);
  assert.equal(unknown.high, null);
  assert.equal(strengthPlan('2 × 12–15').unknown, undefined);
});

test('журнал: ключ строки и вид строки', () => {
  assert.equal(rowKey(strength()), '2026-11-11|Гакк-жим|0');
  assert.equal(rowKey(strength({ occ: 1 })), '2026-11-11|Гакк-жим|1');
  assert.equal(isWalk(walk()), true);
  assert.equal(isWalk(walk({ workout: ' ходьба ' })), true);
  assert.equal(isWalk(strength()), false);
  assert.equal(isWalk({ workout: null }), false);
});

test('журнал: подходы, ячейки и следующий подход', () => {
  assert.deepEqual(setsOf(strength({ sets: [15, 14] })), [15, 14, null]);
  assert.deepEqual(setsOf(strength({ sets: undefined })), [null, null, null]);
  assert.deepEqual(setsOf(strength({ sets: ['12', 11, null] })), [null, 11, null]);
  assert.equal(slotCount(strength()), 2);
  assert.equal(slotCount(strength({ plan: '3 × 10–12' })), 3);
  assert.equal(slotCount(strength({ sets: [15, 14, 12] })), 3, 'лишний записанный подход всё равно виден');
  assert.equal(nextSetIndex(strength()), 0);
  assert.equal(nextSetIndex(strength({ sets: [15, null, null] })), 1);
  assert.equal(nextSetIndex(strength({ sets: [15, 15, null] })), -1);
  assert.equal(nextSetIndex(strength({ sets: [null, 15, null] })), 0);
});

test('журнал: готовность строки', () => {
  assert.equal(hasData(strength()), false);
  assert.equal(hasData(strength({ weight: 40 })), true);
  assert.equal(hasData(strength({ sets: [12, null, null] })), true);
  assert.equal(hasData(strength({ note: 'болело колено' })), false, 'заметка — ещё не тренировка');
  assert.equal(isDone(strength({ weight: 40, sets: [15, 14, null] })), true);
  assert.equal(isDone(strength({ weight: 40, sets: [15, null, null] })), false);
  assert.equal(isDone(strength({ sets: [15, 14, null] })), false, 'без веса строка не готова');
  assert.equal(isDone(strength({ plan: '3 × 10–12', weight: 40, sets: [12, 12, null] })), false);
  assert.equal(isDone(strength({ plan: '', weight: 40, sets: [12, null, null] })), true, 'план не разобран: хватает одного подхода');
  assert.equal(isDone(strength({ weight: 0, sets: [15, 15, null] })), true, 'нулевой вес — тоже вес');
  assert.equal(hasData(walk({ min: 30 })), true);
  assert.equal(isDone(walk({ min: 30 })), false);
  assert.equal(isDone(walk({ km: 3 })), true);
});

test('журнал: дни, статусы и прогресс дня', () => {
  const journal = [
    walk({ date: '2026-11-10', exercise: 'Ходьба ровным темпом', km: 4 }),
    strength({ weight: 40, sets: [15, 15, null] }),
    strength({ exercise: 'Сведение рук' }),
    walk(),
    walk({ date: '2026-11-12', exercise: 'Ходьба или интервалы' }),
  ];
  const days = groupDays([journal[4], ...journal.slice(0, 4)]);
  assert.deepEqual(days.map((d) => d.date), ['2026-11-10', '2026-11-11', '2026-11-12']);
  assert.equal(days[1].rows.length, 3);
  assert.equal(days[1].week, 1);
  assert.deepEqual(dayProgress(days[1].rows), { done: 1, touched: 1, total: 3 });
  assert.equal(dayStatus(days[0].rows, '2026-11-10', '2026-11-11'), 'done');
  assert.equal(dayStatus(days[1].rows, '2026-11-11', '2026-11-11'), 'partial');
  assert.equal(dayStatus(days[2].rows, '2026-11-12', '2026-11-11'), 'planned');
  assert.equal(dayStatus(days[2].rows, '2026-11-12', '2026-11-12'), 'today');
  assert.equal(dayStatus(days[2].rows, '2026-11-12', '2026-11-13'), 'missed');
  assert.equal(dayStatus([], '2026-11-12', '2026-11-13'), 'missed');
});

test('журнал: номер недели из таблицы или от даты старта', () => {
  assert.equal(weekOf(strength({ week: 4 }), '2026-11-09'), 4);
  assert.equal(weekOf(strength({ week: null }), '2026-11-09'), 1);
  assert.equal(weekOf(strength({ week: null, date: '2026-11-16' }), '2026-11-09'), 2);
  assert.equal(weekOf(strength({ week: null, date: '2026-11-15' }), '2026-11-09'), 1);
  assert.equal(weekOf(strength({ week: null }), null), null);
});

test('журнал: пары идут в порядке строк, ходьба отдельно', () => {
  const names = ['Сгибание ног', 'Тяга сидя широким хватом', 'Гакк-жим', 'Сведение рук', 'Обратные разведения'];
  const rows = [...names.map((exercise) => strength({ exercise })), walk()];
  const { pairs, walks } = splitDay(rows);
  assert.deepEqual(pairs.map((p) => p.map((r) => r.exercise)), [
    ['Сгибание ног', 'Тяга сидя широким хватом'], ['Гакк-жим', 'Сведение рук'], ['Обратные разведения'],
  ]);
  assert.equal(walks.length, 1);
  assert.deepEqual(splitDay([walk()]).pairs, []);
});

test('журнал: круг пары закончен, когда сосед записал тот же подход', () => {
  const a = strength({ exercise: 'Гакк-жим', plan: '3 × 10–12', sets: [12, null, null] });
  const b = strength({ exercise: 'Сведение рук', plan: '2 × 12–15', sets: [null, null, null] });
  assert.equal(roundComplete([a, b], rowKey(a), 0), false, 'сосед ещё не сделал первый подход');
  b.sets = [15, null, null];
  assert.equal(roundComplete([a, b], rowKey(a), 0), true);
  assert.equal(roundComplete([a, b], rowKey(b), 0), true);
  assert.equal(roundComplete([a, b], rowKey(a), 2), true, 'третий подход соседу не положен');
  assert.equal(roundComplete([a], rowKey(a), 0), true, 'упражнение без пары');
});

test('журнал: «прошлый раз» ищется по названию во всём журнале', () => {
  const journal = [
    strength({ date: '2026-11-09', workout: 'Силовая A', exercise: 'Сгибание ног', weight: 20, sets: [15, 15, null] }),
    strength({ date: '2026-11-11', workout: 'Силовая B', exercise: 'Сгибание ног', weight: 22.5, sets: [15, 14, null] }),
    strength({ date: '2026-11-13', workout: 'Силовая C', exercise: 'Сгибание ног' }),
    strength({ date: '2026-11-16', workout: 'Силовая A', exercise: 'Сгибание ног', weight: 25, sets: [12, null, null] }),
  ];
  assert.equal(lastTime(journal, journal[2]).date, '2026-11-11', 'тренировка другая, тренажёр тот же');
  assert.equal(lastTime(journal, journal[1]).weight, 20);
  assert.equal(lastTime(journal, journal[0]), null);
  assert.equal(lastTime(journal, journal[3]).date, '2026-11-11', 'пустая строка пятницы пропущена');
  assert.equal(lastTime(journal, strength({ date: '2026-12-01', exercise: 'Жим ногами' })), null);
});

test('журнал: подсказка прогрессии по правилу программы', () => {
  const full = strength({ weight: 40, sets: [15, 15, null] });
  assert.deepEqual(progression(full, 2.5), { from: 40, weight: 42.5, reps: 15, date: '2026-11-11' });
  assert.equal(progression(strength({ weight: 40, sets: [15, 14, null] }), 2.5), null);
  assert.equal(progression(strength({ weight: 40, sets: [15, null, null] }), 2.5), null);
  assert.equal(progression(strength({ sets: [15, 15, null] }), 2.5), null, 'без веса подсказки нет');
  assert.equal(progression(strength({ plan: '', weight: 40, sets: [20, 20, 20] }), 2.5), null);
  assert.equal(progression(full, 0), null);
  assert.equal(progression(null, 2.5), null);
  assert.equal(progression(strength({ plan: '3 × 10–12', weight: 40, sets: [12, 13, 12] }), 5).weight, 45);
  assert.equal(progression(strength({ weight: 7.5, sets: [16, 15, null] }), 1.25).weight, 8.75);
});

test('журнал: заголовок и метка дня', () => {
  const day = [strength(), strength({ exercise: 'Сведение рук' }), walk()];
  assert.equal(workoutTitle(day), 'Силовая B и ходьба');
  assert.equal(workoutBadge(day), 'B');
  assert.equal(workoutTitle([walk({ exercise: 'Ходьба ровным темпом' })]), 'Ходьба ровным темпом');
  assert.equal(workoutBadge([walk()]), 'Ходьба');
  assert.equal(workoutTitle([strength()]), 'Силовая B');
  assert.equal(workoutBadge([strength({ workout: 'Круговая' })]), 'Круговая');
  assert.equal(workoutTitle([]), '');
  assert.equal(workoutBadge([]), '');
});

test('журнал: ходьба — план, темп и краткая запись', () => {
  assert.equal(plannedKm(walk()), 3);
  assert.equal(plannedKm(walk({ plan: 'Интервалы 4 × 3 мин или 5 км ровно' })), 5);
  assert.equal(plannedKm(strength()), null);
  assert.deepEqual(paceOf(3, 36), { pace: '12:00', speed: 5 });
  assert.deepEqual(paceOf(4.2, 52), { pace: '12:23', speed: 4.8 });
  assert.equal(paceOf(1, 11.999).pace, '12:00', 'секунды не превращаются в :60');
  assert.equal(paceOf(0, 30), null);
  assert.equal(paceOf(3, null), null);
  const fmt = (n) => formatNumber(n);
  assert.equal(summarize(strength({ weight: 42.5, sets: [15, 14, null] }), fmt), '42,5 кг · 15, 14');
  assert.equal(summarize(strength({ sets: [15, null, null] }), fmt), '15');
  assert.equal(summarize(strength(), fmt), '');
  assert.equal(summarize(walk({ km: 3, min: 36.5 }), fmt), '3 км · 36,5 мин');
  assert.equal(summarize(walk({ km: 3 }), fmt), '3 км');
});

test('статистика: лучший вес за неделю, как MAXIFS', () => {
  const journal = [
    strength({ date: '2026-11-09', week: 1, exercise: 'Сгибание ног', weight: 20 }),
    strength({ date: '2026-11-11', week: 1, exercise: 'Сгибание ног', weight: 22.5 }),
    strength({ date: '2026-11-13', week: 1, exercise: 'Сгибание ног', weight: 0 }),
    strength({ date: '2026-11-16', week: 2, exercise: 'Сгибание ног', sets: [12, 12, null] }),
    strength({ date: '2026-11-23', week: 3, exercise: 'Сгибание ног', weight: 25 }),
    strength({ date: '2026-11-23', week: 3, exercise: 'Гакк-жим', weight: 60 }),
  ];
  assert.deepEqual(weeklyBest(journal, 'Сгибание ног', '2026-11-09'), [{ week: 1, best: 22.5 }, { week: 3, best: 25 }]);
  assert.deepEqual(weeklyBest(journal, 'Гакк-жим', '2026-11-09'), [{ week: 3, best: 60 }]);
  assert.deepEqual(weeklyBest(journal, 'Жим ногами', '2026-11-09'), []);
});

test('статистика: ходьба по неделям, как SUMIFS', () => {
  const journal = [
    walk({ date: '2026-11-10', week: 1, km: 4, min: 50 }),
    walk({ date: '2026-11-11', week: 1, km: 3.1, min: 37.5 }),
    walk({ date: '2026-11-12', week: 1, min: 20 }),
    strength({ date: '2026-11-16', week: 2, weight: 40 }),
    walk({ date: '2026-11-24', week: 3, min: 45 }),
    walk({ date: '2026-12-01', week: 4, km: 0.1 }),
    walk({ date: '2026-12-02', week: 4, km: 0.2 }),
  ];
  assert.deepEqual(weeklyWalk(journal, '2026-11-09'), [
    { week: 1, km: 7.1, min: 107.5 },
    { week: 2, km: 0, min: 0 }, // на неделе есть вес, поэтому она в сводке
    { week: 4, km: 0.3, min: 0 },
  ]);
});

test('статистика: список упражнений, история и недели', () => {
  const journal = [
    walk({ date: '2026-11-10', exercise: 'Ходьба ровным темпом', km: 4 }),
    strength({ date: '2026-11-11', workout: 'Силовая B', exercise: 'Сгибание ног', weight: 20 }),
    strength({ date: '2026-11-11', workout: 'Силовая B', exercise: 'Гакк-жим' }),
    strength({ date: '2026-11-16', week: 2, workout: 'Силовая A', exercise: 'Жим ногами сидя', weight: 60 }),
    strength({ date: '2026-11-16', week: 2, workout: 'Силовая A', exercise: 'Сгибание ног', weight: 22.5 }),
  ];
  assert.deepEqual(exerciseList(journal), ['Жим ногами сидя', 'Сгибание ног', 'Гакк-жим']);
  assert.deepEqual(exerciseHistory(journal, 'Сгибание ног').map((r) => r.date), ['2026-11-16', '2026-11-11']);
  assert.deepEqual(exerciseHistory(journal, 'Гакк-жим'), []);
  const weeks = weeksOf(journal, '2026-11-09');
  assert.deepEqual(weeks.map((w) => w.week), [1, 2]);
  assert.deepEqual(weeks[0].days.map((d) => d.date), ['2026-11-10', '2026-11-11']);
  assert.equal(weekStart('2026-11-09', 3), '2026-11-23');
  assert.equal(weekStart(null, 3), null);
});
