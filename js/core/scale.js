// Шкалы для графиков: «круглые» деления оси и перевод значения в пиксели.

/** Шаг деления из ряда 1, 2, 2.5, 5, 10 × 10ⁿ. */
export function niceStep(span, count = 4) {
  if (!(span > 0) || !(count > 0)) return 1;
  const raw = span / count;
  const pow = 10 ** Math.floor(Math.log10(raw));
  const n = raw / pow;
  const nice = n <= 1 ? 1 : n <= 2 ? 2 : n <= 2.5 ? 2.5 : n <= 5 ? 5 : 10;
  return nice * pow;
}

const clean = (value) => Math.round(value * 1e6) / 1e6;

/**
 * Ось, которая охватывает значения от min до max.
 * @param {number} min
 * @param {number} max
 * @param {{count?: number, fromZero?: boolean}} [options] fromZero — ось начинается с нуля (столбцы)
 * @returns {{lo: number, hi: number, step: number, ticks: number[]}}
 */
export function niceScale(min, max, { count = 4, fromZero = false } = {}) {
  let lo = fromZero ? 0 : Math.min(min, max);
  let hi = Math.max(min, max);
  if (!Number.isFinite(lo) || !Number.isFinite(hi)) {
    lo = 0;
    hi = 1;
  }
  if (hi === lo) {
    // одна точка: ось вокруг неё, но не ниже нуля
    const pad = hi === 0 ? 1 : Math.abs(hi) * 0.1;
    lo = fromZero ? 0 : Math.max(0, lo - pad);
    hi += pad;
  }
  const step = niceStep(hi - lo, count);
  const first = Math.floor(lo / step + 1e-9) * step;
  let last = Math.ceil(hi / step - 1e-9) * step;
  if (last === first) last = first + step;
  const ticks = [];
  for (let value = first; value <= last + step * 1e-6; value += step) ticks.push(clean(value));
  return { lo: clean(first), hi: clean(last), step: clean(step), ticks };
}

/** Линейный перевод значения из отрезка [d0, d1] в отрезок [r0, r1]. */
export function linear(d0, d1, r0, r1) {
  const span = d1 - d0;
  return (value) => (span === 0 ? (r0 + r1) / 2 : r0 + ((value - d0) / span) * (r1 - r0));
}
