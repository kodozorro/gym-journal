// Тестовая таблица в памяти с той же раскладкой, что у настоящей:
// листы «Журнал», «Прогресс», «Программа», первая неделя без понедельника,
// строки-подсказки перед 6-й и 10-й неделями, формулы в столбцах A, D, K, M.
// Числа, программа и названия тренажёров здесь учебные: настоящий план приложение берёт
// из таблицы.

import { FakeSheet, FakeSpreadsheet, zonedMidnight, formatInZone } from './gas-fake.mjs';
import { parsePlan } from '../js/core/plan.js';

export const HEADERS = [
  'Дата', 'Тренировка', 'Упражнение', 'План', 'Вес, кг', 'Подход 1', 'Подход 2',
  'Подход 3', 'Км', 'Мин', 'Тренажёр', 'Заметка', 'Неделя',
];

// Этап начинается с недели: 1, 3, 5, 9 — как в строке 2 листа «Программа».
export const STAGES = [1, 3, 5, 9];

export const PROGRAM = [
  ['Силовая A', 'Жим ногами сидя', 'Seated Leg Press Machine', '2 × 12–15', '3 × 10–12', '3 × 10–12', '3 × 8–10'],
  ['Силовая A', 'Жим от груди', 'Rotary Chest Press Machine', '2 × 12–15', '3 × 10–12', '3 × 10–12', '3 × 8–10'],
  ['Силовая A', 'Сгибание ног', 'Kneeling Leg Curl Machine', '2 × 12–15 на ногу', '2 × 10–12 на ногу', '2 × 10–12 на ногу', '2 × 10–12 на ногу'],
  ['Силовая A', 'Тяга сидя узким хватом', 'Seated Cable Row Station', '2 × 12–15', '3 × 10–12', '3 × 10–12', '3 × 8–10'],
  ['Силовая A', 'Жим вверх', 'Shoulder Press Machine', '2 × 12–15', '2 × 10–12', '2 × 10–12', '2 × 8–10'],
  ['Силовая A', 'Обратные разведения', 'Pec Deck and Rear Delt Machine', '2 × 12–15', '2 × 12–15', '2 × 12–15', '2 × 12–15'],
  ['Силовая B', 'Сгибание ног', 'Kneeling Leg Curl Machine', '2 × 12–15 на ногу', '2 × 10–12 на ногу', '2 × 10–12 на ногу', '2 × 10–12 на ногу'],
  ['Силовая B', 'Тяга сидя широким хватом', 'Seated Cable Row Station', '2 × 12–15', '3 × 10–12', '3 × 10–12', '3 × 8–10'],
  ['Силовая B', 'Гакк-жим', 'Hack Press Machine', '2 × 12–15', '3 × 10–12', '3 × 10–12', '3 × 8–10'],
  ['Силовая B', 'Сведение рук', 'Pec Deck and Rear Delt Machine', '2 × 12–15', '3 × 12–15', '3 × 12–15', '3 × 12–15'],
  ['Силовая B', 'Обратные разведения', 'Pec Deck and Rear Delt Machine', '2 × 12–15', '2 × 12–15', '2 × 12–15', '2 × 12–15'],
  ['Силовая B', 'Разведение рук в стороны', 'Standing Lateral Raise Machine', '2 × 12–15', '2 × 12–15', '2 × 12–15', '2 × 12–15'],
  ['Силовая C', 'Жим ногами', 'Plate-Loaded Leg Press Machine', '2 × 12–15', '3 × 10–12', '3 × 10–12', '3 × 8–10'],
  ['Силовая C', 'Тяга сидя узким хватом', 'Seated Cable Row Station', '2 × 12–15', '3 × 10–12', '3 × 10–12', '3 × 8–10'],
  ['Силовая C', 'Сгибание ног', 'Kneeling Leg Curl Machine', '2 × 12–15 на ногу', '2 × 10–12 на ногу', '2 × 10–12 на ногу', '2 × 10–12 на ногу'],
  ['Силовая C', 'Жим от груди', 'Rotary Chest Press Machine', '2 × 12–15', '3 × 10–12', '3 × 10–12', '3 × 8–10'],
  ['Силовая C', 'Сведение рук', 'Pec Deck and Rear Delt Machine', '2 × 12–15', '2 × 12–15', '2 × 12–15', '2 × 12–15'],
  ['Силовая C', 'Жим вверх', 'Shoulder Press Machine', '2 × 12–15', '2 × 10–12', '2 × 10–12', '2 × 8–10'],
  ['Ходьба', 'Ходьба до и после силовой', 'Беговая дорожка', '3 км, наклон 1–3 %', '3 км, наклон 3–4 %', '3 км, наклон 4–5 %', '3–3,5 км, наклон 5–6 %'],
  ['Ходьба', 'Ходьба ровным темпом', 'Беговая дорожка', '4 км, наклон 3–6 %', '4–4,5 км, наклон 3–6 %', '5 км, наклон 3–6 %', '5 км, наклон 3–6 %'],
  ['Ходьба', 'Ходьба или интервалы', 'Беговая дорожка', '4 км ровно', '4–4,5 км ровно', 'Интервалы 4 × 3 мин или 5 км ровно', 'Интервалы 6 × 3 мин или 5 км ровно'],
];

const WEEK = [
  { offset: 0, workout: 'Силовая A', walk: 'Ходьба до и после силовой' },
  { offset: 1, workout: null, walk: 'Ходьба ровным темпом' },
  { offset: 2, workout: 'Силовая B', walk: 'Ходьба до и после силовой' },
  { offset: 3, workout: null, walk: 'Ходьба или интервалы' },
  { offset: 4, workout: 'Силовая C', walk: 'Ходьба до и после силовой' },
];

const COL = { A: 1, B: 2, C: 3, D: 4, E: 5, F: 6, G: 7, H: 8, I: 9, J: 10, K: 11, L: 12, M: 13 };

function addDays(iso, n) {
  const [y, m, d] = iso.split('-').map(Number);
  return new Date(Date.UTC(y, m - 1, d + n)).toISOString().slice(0, 10);
}

function stageIndex(week) {
  let index = 0;
  STAGES.forEach((from, i) => {
    if (week >= from) index = i;
  });
  return index;
}

function programRow(workout, exercise) {
  const row = PROGRAM.find((p) => p[0] === workout && p[1] === exercise);
  if (!row) throw new Error(`В учебной программе нет «${workout} / ${exercise}»`);
  return row;
}

/**
 * @param {object} [options]
 * @param {string} [options.start] понедельник первой недели
 * @param {string} [options.timeZone] часовой пояс таблицы
 * @param {number} [options.weeks] число недель
 * @param {boolean} [options.realLayout] первая неделя без понедельника и строки-подсказки, как в настоящей таблице
 */
export function buildSpreadsheet({ start = '2026-11-09', timeZone = 'Etc/GMT', weeks = 12, realLayout = true } = {}) {
  const journal = new FakeSheet('Журнал');
  journal.seed(1, 1, 'Заполняйте жёлтые ячейки: в силовых вес и повторы по подходам, в ходьбе километры и минуты.', { protect: true });
  HEADERS.forEach((title, i) => journal.seed(2, i + 1, title, { protect: true }));

  let rowNumber = 3;
  const hint = (text) => {
    for (let col = 1; col <= HEADERS.length; col += 1) journal.protect(rowNumber, col);
    journal.seed(rowNumber, COL.C, text, { protect: true });
    rowNumber += 1;
  };
  const dataRow = (date, week, workout, exercise) => {
    const program = programRow(workout, exercise);
    journal.seed(rowNumber, COL.A, zonedMidnight(date, timeZone), { protect: true });
    journal.seed(rowNumber, COL.B, workout, { protect: true });
    journal.seed(rowNumber, COL.C, exercise, { protect: true });
    journal.seed(rowNumber, COL.D, program[3 + stageIndex(week)], { protect: true });
    journal.seed(rowNumber, COL.K, program[2], { protect: true });
    journal.seed(rowNumber, COL.M, week, { protect: true });
    rowNumber += 1;
  };

  for (let week = 1; week <= weeks; week += 1) {
    if (realLayout && week === 6) hint('Недели 6–9: раскройте группу кнопкой «+» слева, когда закончите 5-ю неделю.');
    if (realLayout && week === 10) hint('Недели 10–12: раскройте группу кнопкой «+» слева, когда закончите 9-ю неделю.');
    for (const day of WEEK) {
      if (realLayout && week === 1 && day.offset === 0) continue; // журнал начат во вторник
      const date = addDays(start, (week - 1) * 7 + day.offset);
      if (day.workout) {
        for (const p of PROGRAM.filter((item) => item[0] === day.workout)) dataRow(date, week, day.workout, p[1]);
      }
      dataRow(date, week, 'Ходьба', day.walk);
    }
  }

  const progress = new FakeSheet('Прогресс');
  progress.seed(1, 1, 'Понедельник первой недели', { protect: true });
  progress.seed(1, 2, zonedMidnight(start, timeZone), { protect: true });
  progress.seed(2, 1, 'Цель по ходьбе, км в неделю (3 × 3 + 2 × 4)', { protect: true });
  progress.seed(2, 2, 17, { protect: true });
  progress.seed(42, 1, 'Неделя', { protect: true });
  progress.seed(42, 2, 'Начало недели', { protect: true });
  strengthExercises().forEach((name, i) => progress.seed(42, 3 + i, name, { protect: true }));

  const program = new FakeSheet('Программа');
  program.seed(1, 1, 'План в журнале берётся отсюда.', { protect: true });
  program.seed(2, 3, 'Этап начинается с недели', { protect: true });
  STAGES.forEach((from, i) => program.seed(2, 4 + i, from, { protect: true }));
  ['Тренировка', 'Упражнение', 'Тренажёр', 'Недели 1–2', 'Недели 3–4', 'Недели 5–8', 'Недели 9–12 и дальше']
    .forEach((title, i) => program.seed(3, i + 1, title, { protect: true }));
  PROGRAM.forEach((line, r) => line.forEach((value, c) => program.seed(4 + r, c + 1, value, { protect: true })));

  return new FakeSpreadsheet({ name: 'Журнал тренировок (учебный)', timeZone, sheets: [journal, progress, program] });
}

export function strengthExercises() {
  return [...new Set(PROGRAM.filter((p) => p[0] !== 'Ходьба').map((p) => p[1]))];
}

/** Строки журнала с номерами строк листа: для проверок в тестах. */
export function journalRows(spreadsheet) {
  const sheet = spreadsheet.getSheetByName('Журнал');
  const tz = spreadsheet.getSpreadsheetTimeZone();
  const rows = [];
  for (let row = 3; row <= sheet.getLastRow(); row += 1) {
    const date = sheet.peek(row, COL.A);
    rows.push({
      row,
      date: date instanceof Date ? formatInZone(date, tz) : '',
      workout: sheet.peek(row, COL.B),
      exercise: sheet.peek(row, COL.C),
      plan: sheet.peek(row, COL.D),
      weight: sheet.peek(row, COL.E),
      sets: [sheet.peek(row, COL.F), sheet.peek(row, COL.G), sheet.peek(row, COL.H)],
      km: sheet.peek(row, COL.I),
      min: sheet.peek(row, COL.J),
      machine: sheet.peek(row, COL.K),
      note: sheet.peek(row, COL.L),
      week: sheet.peek(row, COL.M),
    });
  }
  return rows;
}

export function findRow(spreadsheet, date, exercise) {
  return journalRows(spreadsheet).find((r) => r.date === date && r.exercise === exercise);
}

/** Слепок всех защищённых ячеек: формулы, заголовки, подсказки. Сравнивается до и после работы скрипта. */
export function protectedSnapshot(spreadsheet) {
  const out = {};
  for (const sheet of spreadsheet.sheets) {
    for (const key of [...sheet.protected].sort()) {
      const [row, col] = key.split(',').map(Number);
      const value = sheet.peek(row, col);
      out[`${sheet.name}!${key}`] = value instanceof Date ? value.toISOString() : value;
    }
  }
  return JSON.stringify(out);
}

/**
 * Сводная таблица листа «Прогресс», посчитанная теми же правилами, что и формулы:
 * недели с хотя бы одним весом или километражем, MAXIFS по упражнению, SUMIFS по ходьбе.
 */
export function progressTable(spreadsheet) {
  const rows = journalRows(spreadsheet).filter((r) => typeof r.week === 'number');
  const weeks = [...new Set(rows.filter((r) => r.weight !== '' || r.km !== '').map((r) => r.week))].sort((a, b) => a - b);
  return weeks.map((week) => {
    const inWeek = rows.filter((r) => r.week === week);
    const best = {};
    for (const name of strengthExercises()) {
      const max = Math.max(0, ...inWeek.filter((r) => r.exercise === name && typeof r.weight === 'number').map((r) => r.weight));
      if (max > 0) best[name] = max; // формула 1/(1/MAXIFS) превращает ноль в пустую ячейку
    }
    const sum = (field) => inWeek.reduce((acc, r) => acc + (typeof r[field] === 'number' ? r[field] : 0), 0);
    return { week, best, km: sum('km'), min: sum('min') };
  });
}

// Выдуманные стартовые веса для учебной истории, кг.
const DEMO_WEIGHTS = {
  'Жим ногами сидя': 40, 'Жим от груди': 20, 'Сгибание ног': 15, 'Тяга сидя узким хватом': 25,
  'Жим вверх': 10, 'Обратные разведения': 10, 'Тяга сидя широким хватом': 25, 'Гакк-жим': 20,
  'Сведение рук': 15, 'Разведение рук в стороны': 5, 'Жим ногами': 60,
};

/**
 * Заполняет дни до даты before выдуманными числами, будто по программе уже занимались.
 * Нужна для снимков экрана и ручной проверки; к настоящим данным отношения не имеет.
 * @param {object} options
 * @param {string} options.before заполняются дни раньше этой даты
 * @param {string[]} [options.skip] даты, которые остаются пустыми («пропущенные» дни)
 */
export function fillHistory(spreadsheet, { before, skip = [] }) {
  const sheet = spreadsheet.getSheetByName('Журнал');
  let seed = 7;
  const rand = () => {
    seed = (seed * 1103515245 + 12345) % 2147483648;
    return seed / 2147483648;
  };
  for (const row of journalRows(spreadsheet)) {
    if (!row.date || !row.exercise || row.date >= before || skip.includes(row.date)) continue;
    const plan = parsePlan(row.plan);
    if (row.workout === 'Ходьба') {
      const km = plan.kind === 'cardio' && plan.km ? plan.km : 4;
      sheet.manualEdit(row.row, COL.I, km);
      sheet.manualEdit(row.row, COL.J, Math.round(km * (11.5 + rand() * 1.5)));
      continue;
    }
    if (plan.kind !== 'strength') continue;
    const base = DEMO_WEIGHTS[row.exercise] ?? 20;
    const week = typeof row.week === 'number' ? row.week : 1;
    sheet.manualEdit(row.row, COL.E, base + 2.5 * Math.floor((week - 1) / 2));
    for (let i = 0; i < plan.sets; i += 1) {
      sheet.manualEdit(row.row, COL.F + i, Math.max(plan.low, plan.high - Math.floor(rand() * 3) - (i ? 1 : 0)));
    }
  }
}
