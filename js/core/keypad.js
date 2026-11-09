// Логика экранной цифровой клавиатуры. Системная клавиатура для чисел не вызывается:
// она закрывает пол-экрана, а в зале вводить нужно одной рукой и быстро.
//
// Поле: { name, text, fresh, integer, max, digits, whole }
//   text    — набранное, с запятой: «42,5»
//   fresh   — показано прежнее значение; первая цифра его заменит
//   integer — только целые (повторы)
//   max     — наибольшее допустимое число
//   digits  — знаков после запятой, whole — цифр до запятой

import { formatNumber, parseDecimal } from './numbers.js';

/** @returns {object} новое поле для клавиатуры */
export function makeField({ name, label = '', unit = '', value = null, integer = false, max, digits = 2, whole = 4 }) {
  return {
    name,
    label,
    unit,
    text: value === null || value === undefined ? '' : formatNumber(value, integer ? 0 : digits),
    fresh: value !== null && value !== undefined,
    integer,
    max,
    digits: integer ? 0 : digits,
    whole,
  };
}

/**
 * Нажатие клавиши: цифра '0'…'9', ',' или 'back'.
 * Нажатие, которое дало бы недопустимое число, ничего не меняет.
 */
export function pressKey(field, key) {
  if (key === 'back') {
    return { ...field, fresh: false, text: field.fresh ? '' : field.text.slice(0, -1) };
  }
  const base = field.fresh ? '' : field.text;
  let text;
  if (key === ',') {
    if (field.integer || base.includes(',')) return field.fresh ? { ...field, fresh: false, text: base } : field;
    text = base === '' ? '0,' : `${base},`;
  } else if (/^\d$/.test(key)) {
    text = base === '0' ? key : base + key;
  } else {
    return field;
  }
  const [whole, frac = ''] = text.split(',');
  if (whole.length > field.whole || frac.length > field.digits) return field.fresh ? { ...field, fresh: false, text: base } : field;
  return { ...field, fresh: false, text };
}

/**
 * Число из поля.
 * @returns {number|null|undefined} null — поле пустое; undefined — набрано не число
 */
export function fieldValue(field) {
  const value = parseDecimal(field.text.replace(/,$/, ''));
  if (value === null || value === undefined) return value;
  if (field.integer && !Number.isInteger(value)) return undefined;
  return value;
}

/** Текст ошибки или пустая строка. */
export function fieldError(field) {
  const value = fieldValue(field);
  if (value === undefined) return 'Это не число.';
  if (value !== null && typeof field.max === 'number' && value > field.max) return `Не больше ${formatNumber(field.max)}.`;
  return '';
}
