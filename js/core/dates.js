// Даты в приложении — строки вида 'YYYY-MM-DD'. Арифметика идёт через UTC,
// чтобы переход на летнее время и часовой пояс телефона не сдвигали календарь.

const DAY_MS = 86400000;

export function toUTC(iso) {
  const [y, m, d] = iso.split('-').map(Number);
  return Date.UTC(y, m - 1, d);
}

export function fromUTC(ms) {
  return new Date(ms).toISOString().slice(0, 10);
}

export function isISODate(value) {
  if (typeof value !== 'string' || !/^\d{4}-\d{2}-\d{2}$/.test(value)) return false;
  const ms = toUTC(value);
  return Number.isFinite(ms) && fromUTC(ms) === value;
}

export function addDays(iso, n) {
  return fromUTC(toUTC(iso) + n * DAY_MS);
}

export function diffDays(a, b) {
  return Math.round((toUTC(a) - toUTC(b)) / DAY_MS);
}

/** Сегодняшняя дата по часам устройства. */
export function todayISO(now = new Date()) {
  const y = now.getFullYear();
  const m = String(now.getMonth() + 1).padStart(2, '0');
  const d = String(now.getDate()).padStart(2, '0');
  return `${y}-${m}-${d}`;
}

/** День недели: 1 — понедельник, 7 — воскресенье. */
export function isoWeekday(iso) {
  return ((new Date(toUTC(iso)).getUTCDay() + 6) % 7) + 1;
}

export function mondayOf(iso) {
  return addDays(iso, 1 - isoWeekday(iso));
}

const FORMATS = {
  // «ср 11.11» — как в таблице
  sheet: new Intl.DateTimeFormat('ru-RU', { weekday: 'short', timeZone: 'UTC' }),
  weekdayLong: new Intl.DateTimeFormat('ru-RU', { weekday: 'long', timeZone: 'UTC' }),
  dayMonth: new Intl.DateTimeFormat('ru-RU', { day: 'numeric', month: 'long', timeZone: 'UTC' }),
  dayMonthShort: new Intl.DateTimeFormat('ru-RU', { day: 'numeric', month: 'short', timeZone: 'UTC' }),
};

function pad2(n) {
  return String(n).padStart(2, '0');
}

/** «ср 11.11» */
export function formatSheetDay(iso) {
  const date = new Date(toUTC(iso));
  const wd = FORMATS.sheet.format(date).replace('.', '');
  return `${wd} ${pad2(date.getUTCDate())}.${pad2(date.getUTCMonth() + 1)}`;
}

/** «среда, 11 ноября» */
export function formatLongDay(iso) {
  const date = new Date(toUTC(iso));
  return `${FORMATS.weekdayLong.format(date)}, ${FORMATS.dayMonth.format(date)}`;
}

/** «11 нояб.» → «11 ноя» */
export function formatShortDay(iso) {
  return FORMATS.dayMonthShort.format(new Date(toUTC(iso))).replace('.', '').replace(/(\d+\s\S{3})\S*/, '$1');
}

/** «11.11» */
export function formatNumericDay(iso) {
  const date = new Date(toUTC(iso));
  return `${pad2(date.getUTCDate())}.${pad2(date.getUTCMonth() + 1)}`;
}

/** «10–13 ноя» или «30 ноя – 4 дек» */
export function formatRange(fromISO, toISO) {
  if (fromISO === toISO) return formatShortDay(fromISO);
  const a = new Date(toUTC(fromISO));
  const b = new Date(toUTC(toISO));
  if (a.getUTCMonth() === b.getUTCMonth() && a.getUTCFullYear() === b.getUTCFullYear()) {
    return `${a.getUTCDate()}–${formatShortDay(toISO)}`;
  }
  return `${formatShortDay(fromISO)} – ${formatShortDay(toISO)}`;
}
