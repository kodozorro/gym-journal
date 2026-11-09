// Разбор и вывод чисел. Дробную часть пользователь вводит через запятую или точку.

/**
 * Разбирает число из поля ввода.
 * @returns {number|null|undefined} число; null — поле пустое; undefined — это не число.
 */
export function parseDecimal(input) {
  if (typeof input === 'number') return Number.isFinite(input) ? input : undefined;
  const text = String(input ?? '').replace(/[\s  ]/g, '');
  if (text === '') return null;
  if (!/^\d+(?:[.,]\d+)?$/.test(text) && !/^[.,]\d+$/.test(text)) return undefined;
  const value = Number(text.replace(',', '.'));
  return Number.isFinite(value) ? value : undefined;
}

/** Целое неотрицательное число (повторы). */
export function parseCount(input) {
  const value = parseDecimal(input);
  if (value === null || value === undefined) return value;
  return Number.isInteger(value) ? value : undefined;
}

export function roundTo(value, digits = 2) {
  const k = 10 ** digits;
  return Math.round((value + Number.EPSILON) * k) / k;
}

/** «42,5», «40», «3,25» — без лишних нулей, с запятой. */
export function formatNumber(value, digits = 2) {
  if (value === null || value === undefined || !Number.isFinite(value)) return '';
  return String(roundTo(value, digits)).replace('.', ',');
}

/** Склонение: plural(3, 'подход', 'подхода', 'подходов') → 'подхода'. */
export function plural(n, one, few, many) {
  const abs = Math.abs(n);
  const mod10 = abs % 10;
  const mod100 = abs % 100;
  if (!Number.isInteger(abs)) return few;
  if (mod10 === 1 && mod100 !== 11) return one;
  if (mod10 >= 2 && mod10 <= 4 && (mod100 < 12 || mod100 > 14)) return few;
  return many;
}
