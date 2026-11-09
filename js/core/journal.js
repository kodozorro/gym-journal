// Модель журнала: строки таблицы → дни, пары упражнений, «прошлый раз», готовность.
// Строка журнала: { date, workout, exercise, plan, machine, week, weight, sets[3], km, min, note, occ? }

import { roundTo } from './numbers.js';
import { strengthPlan, parsePlan, MAX_SETS } from './plan.js';
import { diffDays, isISODate } from './dates.js';

// Таблица считает строку ходьбой по тому же правилу: столбец «Тренировка» равен «Ходьба».
export const WALK_WORKOUT = 'ходьба';

export function rowKey(row) {
  return `${row.date}|${row.exercise}|${row.occ || 0}`;
}

const numberOrNull = (value) => (typeof value === 'number' && Number.isFinite(value) ? value : null);
const textOf = (value) => (typeof value === 'string' ? value : '');

/**
 * Приводит журнал из ответа скрипта к виду, на который рассчитывает приложение.
 * Строки без даты или названия отбрасываются, лишние поля не переносятся.
 */
export function normalizeJournal(list) {
  if (!Array.isArray(list)) return [];
  const out = [];
  for (const raw of list) {
    if (!raw || typeof raw !== 'object' || !isISODate(raw.date)) continue;
    const exercise = textOf(raw.exercise).trim();
    if (!exercise) continue;
    const sets = Array.isArray(raw.sets) ? raw.sets : [];
    const row = {
      date: raw.date,
      workout: textOf(raw.workout),
      exercise,
      plan: textOf(raw.plan),
      machine: textOf(raw.machine),
      week: numberOrNull(raw.week),
      weight: numberOrNull(raw.weight),
      sets: Array.from({ length: MAX_SETS }, (_, i) => numberOrNull(sets[i])),
      km: numberOrNull(raw.km),
      min: numberOrNull(raw.min),
      note: textOf(raw.note),
    };
    if (Number.isInteger(raw.occ) && raw.occ > 0) row.occ = raw.occ;
    out.push(row);
  }
  return out;
}

export function isWalk(row) {
  return String(row.workout ?? '').trim().toLowerCase() === WALK_WORKOUT;
}

export function setsOf(row) {
  const sets = Array.isArray(row.sets) ? row.sets : [];
  return Array.from({ length: MAX_SETS }, (_, i) => (typeof sets[i] === 'number' ? sets[i] : null));
}

/** Сколько ячеек подходов показывать: по плану, но не меньше уже заполненных. */
export function slotCount(row) {
  const plan = strengthPlan(row.plan);
  const sets = setsOf(row);
  let lastFilled = -1;
  sets.forEach((v, i) => {
    if (v !== null) lastFilled = i;
  });
  return Math.min(MAX_SETS, Math.max(plan.sets, lastFilled + 1));
}

/** Первый незаполненный подход плана или -1, если все записаны. */
export function nextSetIndex(row) {
  const plan = strengthPlan(row.plan);
  const sets = setsOf(row);
  for (let i = 0; i < plan.sets; i += 1) if (sets[i] === null) return i;
  return -1;
}

export function hasData(row) {
  if (isWalk(row)) return row.km != null || row.min != null;
  return row.weight != null || setsOf(row).some((v) => v !== null);
}

/**
 * Отметки «сделано» в таблице нет. Силовая строка готова, когда заполнены вес
 * и все подходы плана; ходьба — когда заполнены километры.
 */
export function isDone(row) {
  if (isWalk(row)) return row.km != null;
  if (row.weight == null) return false;
  const plan = strengthPlan(row.plan);
  const sets = setsOf(row);
  if (plan.unknown) return sets.some((v) => v !== null);
  return sets.slice(0, plan.sets).every((v) => v !== null);
}

/** Дни журнала по порядку дат; строки внутри дня идут как в таблице. */
export function groupDays(journal) {
  const byDate = new Map();
  for (const row of journal) {
    if (!byDate.has(row.date)) byDate.set(row.date, { date: row.date, week: row.week ?? null, rows: [] });
    const day = byDate.get(row.date);
    day.rows.push(row);
    if (day.week == null && row.week != null) day.week = row.week;
  }
  return [...byDate.values()].sort((a, b) => (a.date < b.date ? -1 : a.date > b.date ? 1 : 0));
}

/** Номер недели программы: из таблицы, а если его нет — от даты старта. */
export function weekOf(row, start) {
  if (typeof row.week === 'number') return row.week;
  if (!start) return null;
  return Math.floor(diffDays(row.date, start) / 7) + 1;
}

export function dayProgress(rows) {
  let done = 0;
  let touched = 0;
  for (const row of rows) {
    if (isDone(row)) done += 1;
    if (hasData(row)) touched += 1;
  }
  return { done, touched, total: rows.length };
}

/** 'done' | 'partial' | 'missed' | 'today' | 'planned' */
export function dayStatus(rows, date, today) {
  const { done, touched, total } = dayProgress(rows);
  if (total > 0 && done === total) return 'done';
  if (touched > 0) return 'partial';
  if (date < today) return 'missed';
  if (date === today) return 'today';
  return 'planned';
}

/**
 * Силовые упражнения дня идут парами в порядке строк: 1–2, 3–4, 5–6.
 * Ходьба — отдельными карточками.
 */
export function splitDay(rows) {
  const strength = rows.filter((r) => !isWalk(r));
  const walks = rows.filter(isWalk);
  const pairs = [];
  for (let i = 0; i < strength.length; i += 2) pairs.push(strength.slice(i, i + 2));
  return { pairs, walks };
}

/** Круг пары закончен, когда этот же по счёту подход записан у соседа или соседу он не положен. */
export function roundComplete(pair, key, setIndex) {
  return pair
    .filter((r) => rowKey(r) !== key)
    .every((other) => setIndex >= strengthPlan(other.plan).sets || setsOf(other)[setIndex] !== null);
}

/**
 * «Прошлый раз» ищется по названию упражнения во всём журнале: одно упражнение
 * встречается в двух тренировках недели на одном тренажёре.
 */
export function lastTime(journal, row) {
  let best = null;
  for (const r of journal) {
    if (r.exercise !== row.exercise || r.date >= row.date || !hasData(r)) continue;
    if (!best || r.date >= best.date) best = r;
  }
  return best;
}

/**
 * Правило программы: когда во всех подходах получилась верхняя граница повторов,
 * добавляется минимальный шаг веса. Возвращает подсказку или null.
 */
export function progression(last, step) {
  if (!last || last.weight == null || !(step > 0)) return null;
  const plan = strengthPlan(last.plan);
  if (plan.unknown || plan.high == null) return null;
  const sets = setsOf(last).slice(0, plan.sets);
  if (sets.some((v) => v === null) || !sets.every((v) => v >= plan.high)) return null;
  return { from: last.weight, weight: roundTo(last.weight + step, 2), reps: plan.high, date: last.date };
}

/** «Силовая B и ходьба», «Ходьба ровным темпом» */
export function workoutTitle(rows) {
  const strength = [...new Set(rows.filter((r) => !isWalk(r)).map((r) => String(r.workout ?? '').trim()).filter(Boolean))];
  const walks = rows.filter(isWalk);
  if (strength.length && walks.length) return `${strength.join(', ')} и ходьба`;
  if (strength.length) return strength.join(', ');
  if (walks.length) return [...new Set(walks.map((r) => r.exercise))].join(', ');
  return '';
}

/** Короткая метка дня для списка недель: «A», «B», «Ходьба». */
export function workoutBadge(rows) {
  const strength = rows.find((r) => !isWalk(r));
  if (!strength) return rows.length ? 'Ходьба' : '';
  const name = String(strength.workout ?? '').trim();
  const lastWord = name.split(/\s+/).pop() || name;
  return lastWord.length <= 3 ? lastWord : name;
}

/** Километры из плана ходьбы: «3 км, наклон 1–3 %» → 3. */
export function plannedKm(row) {
  const plan = parsePlan(row.plan);
  return plan.kind === 'cardio' ? plan.km : null;
}

/** Темп и скорость ходьбы для подписи под итогом. */
export function paceOf(km, min) {
  if (!(km > 0) || !(min > 0)) return null;
  const perKm = min / km;
  let whole = Math.floor(perKm);
  let sec = Math.round((perKm - whole) * 60);
  if (sec === 60) {
    whole += 1;
    sec = 0;
  }
  return { pace: `${whole}:${String(sec).padStart(2, '0')}`, speed: roundTo(km / (min / 60), 1) };
}

/** Краткая запись сделанного: «60 кг · 15, 14». */
export function summarize(row, fmt) {
  if (isWalk(row)) {
    const parts = [];
    if (row.km != null) parts.push(`${fmt(row.km)} км`);
    if (row.min != null) parts.push(`${fmt(row.min)} мин`);
    return parts.join(' · ');
  }
  const sets = setsOf(row).filter((v) => v !== null);
  const parts = [];
  if (row.weight != null) parts.push(`${fmt(row.weight)} кг`);
  if (sets.length) parts.push(sets.join(', '));
  return parts.join(' · ');
}
