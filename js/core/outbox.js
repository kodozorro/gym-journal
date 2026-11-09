// Очередь неотправленных записей. Чистые функции: состояние приходит и возвращается значением,
// хранение и сеть — снаружи.
//
// Запись в очереди — это состояние полей строки, а не изменение: «вес 30, подходы 15 и 14».
// Повторная отправка ничего не портит, поэтому очередь можно слать сколько угодно раз.
// По одной строке журнала в очереди лежит одна запись: новые правки вливаются в неё.

import { rowKey } from './journal.js';
import { MAX_SETS } from './plan.js';

export const FIELDS = ['weight', 'sets', 'km', 'min', 'note'];

export function emptyOutbox() {
  return { seq: 0, items: {}, failed: [] };
}

/** Приводит то, что лежало в хранилище, к ожидаемому виду; мусор отбрасывает. */
export function normalizeOutbox(value) {
  const out = emptyOutbox();
  if (!value || typeof value !== 'object') return out;
  const valid = (item) =>
    item && typeof item === 'object' && typeof item.date === 'string' && typeof item.exercise === 'string' &&
    item.fields && typeof item.fields === 'object';
  if (value.items && typeof value.items === 'object') {
    for (const item of Object.values(value.items)) {
      if (!valid(item)) continue;
      const clean = cleanItem(item);
      out.items[rowKey(clean)] = clean;
      out.seq = Math.max(out.seq, clean.rev);
    }
  }
  if (Array.isArray(value.failed)) {
    for (const item of value.failed) {
      if (!valid(item)) continue;
      out.failed.push({
        ...cleanItem(item),
        status: typeof item.status === 'string' ? item.status : 'rejected',
        reason: typeof item.reason === 'string' ? item.reason : '',
        failedAt: Number.isFinite(item.failedAt) ? item.failedAt : 0,
      });
    }
  }
  if (Number.isFinite(value.seq)) out.seq = Math.max(out.seq, value.seq);
  return out;
}

function cleanItem(item) {
  return {
    date: item.date,
    exercise: item.exercise,
    occ: Number.isInteger(item.occ) && item.occ > 0 ? item.occ : 0,
    fields: cleanFields(item.fields),
    rev: Number.isFinite(item.rev) ? item.rev : 0,
    at: Number.isFinite(item.at) ? item.at : 0,
  };
}

function numberOrNull(value) {
  return typeof value === 'number' && Number.isFinite(value) ? value : null;
}

function cleanFields(fields) {
  const out = {};
  if ('weight' in fields) out.weight = numberOrNull(fields.weight);
  if ('sets' in fields) {
    const sets = Array.isArray(fields.sets) ? fields.sets : [];
    out.sets = Array.from({ length: MAX_SETS }, (_, i) => numberOrNull(sets[i]));
  }
  if ('km' in fields) out.km = numberOrNull(fields.km);
  if ('min' in fields) out.min = numberOrNull(fields.min);
  if ('note' in fields) out.note = typeof fields.note === 'string' ? fields.note : '';
  return out;
}

/**
 * Кладёт правку строки в очередь. Поля, которых в правке нет, остаются как были.
 * @param {object} row строка журнала (нужны date, exercise, occ)
 * @param {object} fields { weight?, sets?, km?, min?, note? } — новое состояние этих полей
 */
export function queuePatch(outbox, row, fields, now = Date.now()) {
  const patch = cleanFields(fields);
  if (!Object.keys(patch).length) return outbox;
  const key = rowKey(row);
  const previous = outbox.items[key];
  const seq = outbox.seq + 1;
  const item = {
    date: row.date,
    exercise: row.exercise,
    occ: row.occ || 0,
    fields: { ...(previous ? previous.fields : {}), ...patch },
    rev: seq,
    at: now,
  };
  return {
    seq,
    items: { ...outbox.items, [key]: item },
    // новая правка той же строки заменяет прежнюю отклонённую
    failed: outbox.failed.filter((f) => rowKey(f) !== key),
  };
}

/**
 * Готовит запрос push: записи в порядке появления и отметку, какая версия каждой ушла.
 * @returns {{entries: object[], sent: {key:string, rev:number}[]}}
 */
export function buildPush(outbox, limit = 100) {
  const list = Object.entries(outbox.items).sort((a, b) => a[1].rev - b[1].rev).slice(0, limit);
  return {
    entries: list.map(([, item]) => {
      const entry = { date: item.date, exercise: item.exercise, ...item.fields };
      if (item.occ) entry.occ = item.occ;
      return entry;
    }),
    sent: list.map(([key, item]) => ({ key, rev: item.rev })),
  };
}

/**
 * Разбирает ответ скрипта. Принятые записи уходят из очереди; отклонённые и ненайденные
 * переезжают в список ошибок, чтобы их увидел пользователь. Запись, которую успели поправить,
 * пока запрос был в пути, остаётся в очереди и уйдёт в следующий раз.
 */
export function ackPush(outbox, sent, results, now = Date.now()) {
  if (!Array.isArray(results) || results.length !== sent.length) {
    throw new Error('Ответ скрипта не совпал с запросом по числу записей');
  }
  const items = { ...outbox.items };
  const failed = [...outbox.failed];
  sent.forEach((mark, i) => {
    const item = items[mark.key];
    if (!item || item.rev !== mark.rev) return;
    const status = results[i] && results[i].status;
    delete items[mark.key];
    if (status === 'written' || status === 'unchanged') return;
    failed.push({
      ...item,
      status: status === 'not_found' ? 'not_found' : 'rejected',
      reason: results[i] && typeof results[i].reason === 'string' ? results[i].reason : '',
      failedAt: now,
    });
  });
  return { seq: outbox.seq, items, failed };
}

/** Журнал с наложенными неотправленными правками: то, что пользователь видит на экране. */
export function applyOutbox(journal, outbox) {
  if (!Object.keys(outbox.items).length) return journal;
  return journal.map((row) => {
    const item = outbox.items[rowKey(row)];
    if (!item) return row;
    const next = { ...row, ...item.fields, pending: true };
    if (item.fields.sets) next.sets = [...item.fields.sets];
    return next;
  });
}

export function pendingCount(outbox) {
  return Object.keys(outbox.items).length;
}

/** Возвращает отклонённую запись в очередь: например, после того как строку вернули в таблицу. */
export function retryFailed(outbox, index, now = Date.now()) {
  const item = outbox.failed[index];
  if (!item) return outbox;
  const rest = { ...outbox, failed: outbox.failed.filter((_, i) => i !== index) };
  const pending = rest.items[rowKey(item)];
  // если по строке уже есть более свежая правка, она важнее
  return queuePatch(rest, item, { ...item.fields, ...(pending ? pending.fields : {}) }, now);
}

export function dropFailed(outbox, index) {
  return { ...outbox, failed: outbox.failed.filter((_, i) => i !== index) };
}
