// Разбор текста плана из столбца «План». План живёт в таблице, а не в коде:
// здесь только чтение формата «N × A–B» (силовые) и «X км …» (ходьба).

import { parseDecimal } from './numbers.js';

// «3 × 10–12», «2 × 12–15 на ногу», «3x10», «2 х 8-10» (латинская x, кириллическая х, знак ×)
const STRENGTH_RE = /^\s*(\d{1,2})\s*[×xXхХ*]\s*(\d{1,3})(?:\s*[–—-]\s*(\d{1,3}))?\s*(.*)$/u;
// «3 км», «4–4,5 км», «3–3,5 км, наклон 5–6 %»
const KM_RE = /(\d+(?:[.,]\d+)?)(?:\s*[–—-]\s*(\d+(?:[.,]\d+)?))?\s*км/iu;

export const MAX_SETS = 3;

/**
 * @returns {{kind:'strength', sets:number, low:number, high:number, tail:string, perSide:boolean, text:string}
 *          |{kind:'cardio', km:number|null, kmHigh:number|null, text:string}}
 */
export function parsePlan(value) {
  const text = String(value ?? '').trim();
  const m = STRENGTH_RE.exec(text);
  if (m) {
    const sets = Math.min(Math.max(Number(m[1]), 1), MAX_SETS);
    let low = Number(m[2]);
    let high = m[3] ? Number(m[3]) : low;
    if (high < low) [low, high] = [high, low];
    const tail = m[4].trim();
    return { kind: 'strength', sets, low, high, tail, perSide: /на\s+(ногу|руку|сторону)/iu.test(tail), text };
  }
  const km = KM_RE.exec(text);
  if (km) {
    const low = parseDecimal(km[1]);
    const high = km[2] ? parseDecimal(km[2]) : low;
    return { kind: 'cardio', km: low ?? null, kmHigh: high ?? null, text };
  }
  return { kind: 'cardio', km: null, kmHigh: null, text };
}

/** Число подходов и диапазон повторов; если план не разобрать — три подхода без диапазона. */
export function strengthPlan(value) {
  const plan = parsePlan(value);
  if (plan.kind === 'strength') return plan;
  return { kind: 'strength', sets: MAX_SETS, low: null, high: null, tail: '', perSide: false, text: plan.text, unknown: true };
}
