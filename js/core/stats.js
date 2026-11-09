// Недельная статистика. Повторяет формулы листа «Прогресс»:
// лучший рабочий вес за неделю по упражнению и сумма километров и минут ходьбы за неделю.

import { isWalk, weekOf, hasData, groupDays } from './journal.js';
import { addDays } from './dates.js';

/** Понедельник недели программы с номером week. */
export function weekStart(start, week) {
  return start && typeof week === 'number' ? addDays(start, (week - 1) * 7) : null;
}

/** Силовые упражнения в устойчивом порядке: по тренировке (A, B, C), затем по месту в дне. */
export function exerciseList(journal) {
  const seen = new Map();
  for (const day of groupDays(journal)) {
    let pos = 0;
    for (const row of day.rows) {
      if (isWalk(row)) continue;
      const rank = { workout: String(row.workout ?? ''), pos };
      const known = seen.get(row.exercise);
      if (!known || compareRank(rank, known) < 0) seen.set(row.exercise, rank);
      pos += 1;
    }
  }
  return [...seen.entries()].sort((a, b) => compareRank(a[1], b[1])).map(([name]) => name);
}

function compareRank(a, b) {
  return a.workout.localeCompare(b.workout, 'ru') || a.pos - b.pos;
}

/**
 * Лучший рабочий вес за неделю, как MAXIFS в таблице. Нулевой вес таблица считает пустым.
 * @returns {{week:number, best:number}[]}
 */
export function weeklyBest(journal, exercise, start) {
  const best = new Map();
  for (const row of journal) {
    if (row.exercise !== exercise || isWalk(row)) continue;
    if (!(row.weight > 0)) continue;
    const week = weekOf(row, start);
    if (week == null) continue;
    best.set(week, Math.max(best.get(week) ?? 0, row.weight));
  }
  return [...best.entries()].sort((a, b) => a[0] - b[0]).map(([week, value]) => ({ week, best: value }));
}

/**
 * Ходьба по неделям: сумма километров и минут. В список попадают недели,
 * где записан хотя бы один вес или километраж — как в столбце A сводной таблицы.
 * @returns {{week:number, km:number, min:number}[]}
 */
export function weeklyWalk(journal, start) {
  const weeks = new Map();
  for (const row of journal) {
    const week = weekOf(row, start);
    if (week == null) continue;
    const active = row.weight != null || row.km != null;
    if (!weeks.has(week)) weeks.set(week, { week, km: 0, min: 0, active: false });
    const item = weeks.get(week);
    if (active) item.active = true;
    if (typeof row.km === 'number') item.km += row.km;
    if (typeof row.min === 'number') item.min += row.min;
  }
  return [...weeks.values()]
    .filter((w) => w.active)
    .sort((a, b) => a.week - b.week)
    .map(({ week, km, min }) => ({ week, km: Math.round(km * 100) / 100, min: Math.round(min * 100) / 100 }));
}

/** Записи по упражнению, новые сверху. */
export function exerciseHistory(journal, exercise) {
  return journal
    .filter((row) => row.exercise === exercise && hasData(row))
    .sort((a, b) => (a.date < b.date ? 1 : a.date > b.date ? -1 : 0));
}

/** Недели журнала: номер, даты и дни. */
export function weeksOf(journal, start) {
  const weeks = new Map();
  for (const day of groupDays(journal)) {
    const week = day.week ?? weekOf(day.rows[0], start);
    const id = week ?? 0;
    if (!weeks.has(id)) weeks.set(id, { week, days: [] });
    weeks.get(id).days.push(day);
  }
  return [...weeks.values()].sort((a, b) => (a.week ?? 0) - (b.week ?? 0));
}
