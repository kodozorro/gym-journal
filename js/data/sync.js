// Синхронизация с таблицей: снимок журнала, очередь записей, повторы.
//
// На iOS нет фоновой синхронизации, поэтому очередь уходит в трёх случаях:
// сразу после правки, при возврате в приложение и при появлении сети. Пока приложение
// открыто, неудачные попытки повторяются сами, с растущей паузой.

import {
  ackPush, applyOutbox, buildPush, dropFailed, emptyOutbox, normalizeOutbox, pendingCount, queuePatch, retryFailed,
} from '../core/outbox.js';
import { normalizeJournal } from '../core/journal.js';
import { isISODate } from '../core/dates.js';
import { BridgeError, callBridge } from './api.js';

/** Паузы между повторами, секунды. */
export const RETRY_STEPS = [5, 15, 30, 60, 120, 300];
/** Пауза перед отправкой, мс: соседние правки (вес и подход) уходят одним запросом. */
export const FLUSH_DELAY = 1200;
const PUSH_LIMIT = 100;
const MAX_ROUNDS = 4;

// Ошибки, которые повтор не вылечит: нужен человек (ключ, развёртывание, структура таблицы).
const NEEDS_USER = new Set([
  'unauthorized', 'no_key', 'layout_changed', 'no_journal', 'no_spreadsheet', 'api_mismatch',
  'bad_request', 'bad_json', 'unknown_action', 'too_large', 'too_many',
]);

function validConn(value) {
  return value && typeof value.url === 'string' && value.url && typeof value.key === 'string' && value.key
    ? { url: value.url, key: value.key }
    : null;
}

function normalizeSnapshot(value) {
  if (!value || typeof value !== 'object' || !Array.isArray(value.journal)) return null;
  return {
    journal: normalizeJournal(value.journal),
    start: isISODate(value.start) ? value.start : null,
    walkGoalKm: typeof value.walkGoalKm === 'number' && Number.isFinite(value.walkGoalKm) ? value.walkGoalKm : null,
    tz: typeof value.tz === 'string' ? value.tz : '',
    script: typeof value.script === 'number' ? value.script : null,
    fetchedAt: Number.isFinite(value.fetchedAt) ? value.fetchedAt : 0,
  };
}

/**
 * @param {object} deps
 * @param {ReturnType<import('./storage.js').createStorage>} deps.storage
 * @param {typeof fetch} [deps.fetch]
 * @param {() => number} [deps.now]
 * @param {(fn: Function, ms: number) => any} [deps.setTimer]
 * @param {(id: any) => void} [deps.clearTimer]
 * @param {() => boolean} [deps.isOnline]
 * @param {() => void} [deps.onChange] вызывается после любого изменения состояния
 */
export function createSync({
  storage,
  fetch: fetchFn,
  now = () => Date.now(),
  setTimer = (fn, ms) => setTimeout(fn, ms),
  clearTimer = (id) => clearTimeout(id),
  isOnline = () => true,
  onChange = () => {},
}) {
  let conn = validConn(storage.get('conn'));
  let snapshot = normalizeSnapshot(storage.get('snapshot'));
  let outbox = normalizeOutbox(storage.get('outbox'));

  /** 'unconfigured' | 'idle' | 'syncing' | 'waiting' | 'error' */
  let phase = conn ? 'idle' : 'unconfigured';
  let error = null; // { code, message, at }
  let retryAt = null;
  let attempt = 0;
  let generation = 0; // растёт при смене подключения: ответы старого подключения не принимаются
  let inFlight = null;
  let again = false;
  let flushTimer = null;
  let retryTimer = null;
  let outboxSaved = true;
  let view = null;

  function emit() {
    view = null;
    onChange();
  }

  function saveOutbox() {
    outboxSaved = storage.set('outbox', outbox);
  }

  function clearTimers() {
    if (flushTimer !== null) clearTimer(flushTimer);
    if (retryTimer !== null) clearTimer(retryTimer);
    flushTimer = null;
    retryTimer = null;
    retryAt = null;
  }

  function acceptSnapshot(data) {
    if (!Array.isArray(data.journal)) return;
    snapshot = normalizeSnapshot({ ...data, fetchedAt: now() });
    storage.set('snapshot', snapshot);
  }

  function scheduleRetry(seconds) {
    const delay = seconds ?? RETRY_STEPS[Math.min(attempt, RETRY_STEPS.length - 1)];
    attempt += 1;
    if (retryTimer !== null) clearTimer(retryTimer);
    retryAt = now() + delay * 1000;
    retryTimer = setTimer(() => {
      retryTimer = null;
      retryAt = null;
      sync();
    }, delay * 1000);
  }

  function scheduleFlush(delay = FLUSH_DELAY) {
    if (flushTimer !== null) clearTimer(flushTimer);
    flushTimer = setTimer(() => {
      flushTimer = null;
      sync();
    }, delay);
  }

  async function exchange(current, mine) {
    for (let round = 0; round < MAX_ROUNDS; round += 1) {
      again = false;
      const { entries, sent } = buildPush(outbox, PUSH_LIMIT);
      const data = entries.length
        ? await callBridge(current, 'push', { entries, pull: true }, { fetch: fetchFn })
        : await callBridge(current, 'pull', {}, { fetch: fetchFn });
      if (mine !== generation) return false; // подключение сменили, пока запрос был в пути
      if (entries.length) {
        outbox = ackPush(outbox, sent, data.results, now());
        saveOutbox();
      }
      acceptSnapshot(data);
      if (!pendingCount(outbox) && !again) break;
      emit();
    }
    return true;
  }

  /**
   * Отправляет очередь и перечитывает журнал. Одновременно идёт только один обмен:
   * повторный вызов во время обмена просит ещё один круг после него.
   * @returns {Promise<{ok: boolean, error?: {code: string, message: string}}>}
   */
  function sync() {
    if (!conn) {
      phase = 'unconfigured';
      emit();
      return Promise.resolve({ ok: false, error: { code: 'unconfigured', message: 'Таблица не подключена.' } });
    }
    if (inFlight) {
      again = true;
      return inFlight;
    }
    clearTimers();
    if (!isOnline()) {
      phase = 'waiting';
      error = { code: 'offline', message: 'Нет сети.', at: now() };
      scheduleRetry(30);
      emit();
      return Promise.resolve({ ok: false, error });
    }
    const mine = generation;
    const current = conn;
    phase = 'syncing';
    emit();
    inFlight = exchange(current, mine)
      .then((accepted) => {
        if (!accepted) return { ok: false, error: { code: 'superseded', message: 'Подключение изменилось.' } };
        phase = 'idle';
        error = null;
        attempt = 0;
        if (pendingCount(outbox)) scheduleFlush();
        return { ok: true };
      })
      .catch((err) => {
        if (mine !== generation) return { ok: false, error: { code: 'superseded', message: 'Подключение изменилось.' } };
        const code = err instanceof BridgeError ? err.code : 'internal';
        error = { code, message: err && err.message ? String(err.message) : 'Неизвестная ошибка.', at: now() };
        if (NEEDS_USER.has(code)) {
          phase = 'error';
        } else {
          phase = 'waiting';
          scheduleRetry(code === 'busy' ? 5 : undefined);
        }
        return { ok: false, error };
      })
      .finally(() => {
        inFlight = null;
        // Подключение сменили, пока запрос был в пути: очередь уходит уже по новому подключению.
        if (mine !== generation && conn && pendingCount(outbox)) scheduleFlush(0);
        emit();
      });
    return inFlight;
  }

  return {
    getState() {
      if (!view) view = snapshot ? applyOutbox(snapshot.journal, outbox) : [];
      return {
        configured: Boolean(conn),
        conn,
        snapshot,
        /** журнал с наложенными неотправленными правками */
        journal: view,
        pending: pendingCount(outbox),
        failed: outbox.failed,
        phase,
        error,
        retryAt,
        online: isOnline(),
        /** false — телефон не дал сохранить очередь: записи пропадут, если закрыть приложение */
        outboxSaved,
      };
    },

    /** Правка строки журнала: сразу видна на экране, сохранена на телефоне и поставлена в очередь. */
    queue(row, fields) {
      const next = queuePatch(outbox, row, fields, now());
      if (next === outbox) return;
      outbox = next;
      saveOutbox();
      if (inFlight) again = true;
      else if (conn) scheduleFlush();
      emit();
    },

    sync,

    /** Возврат в приложение или появление сети: отправить очередь сейчас, не дожидаясь паузы. */
    wake({ staleAfterMs = 60000 } = {}) {
      if (!conn || inFlight) return;
      const stale = !snapshot || now() - snapshot.fetchedAt > staleAfterMs;
      if (phase === 'error' && !pendingCount(outbox) && !stale) return;
      if (pendingCount(outbox) || stale || phase === 'waiting') {
        attempt = 0;
        sync();
      }
    },

    /**
     * Проверяет адрес и ключ чтением журнала. Подключение сохраняется, только если чтение удалось.
     * @returns {Promise<{ok: boolean, error?: {code: string, message: string}}>}
     */
    async connect(candidate) {
      const next = validConn(candidate);
      if (!next) return { ok: false, error: { code: 'bad_request', message: 'Нужны адрес и ключ.' } };
      let data;
      try {
        data = await callBridge(next, 'pull', {}, { fetch: fetchFn });
      } catch (err) {
        const code = err instanceof BridgeError ? err.code : 'internal';
        return { ok: false, error: { code, message: err && err.message ? String(err.message) : 'Неизвестная ошибка.' } };
      }
      generation += 1;
      clearTimers();
      conn = next;
      storage.set('conn', conn);
      acceptSnapshot(data);
      phase = 'idle';
      error = null;
      attempt = 0;
      if (pendingCount(outbox)) scheduleFlush(0);
      emit();
      return { ok: true };
    },

    retryFailed(index) {
      outbox = retryFailed(outbox, index, now());
      saveOutbox();
      if (conn) scheduleFlush(0);
      emit();
    },

    dropFailed(index) {
      outbox = dropFailed(outbox, index);
      saveOutbox();
      emit();
    },

    /** Забывает подключение, снимок и очередь на этом телефоне. Таблицу не трогает. */
    reset() {
      generation += 1;
      clearTimers();
      conn = null;
      snapshot = null;
      outbox = emptyOutbox();
      storage.remove('conn');
      storage.remove('snapshot');
      storage.remove('outbox');
      phase = 'unconfigured';
      error = null;
      attempt = 0;
      outboxSaved = true;
      emit();
    },

    /** Останавливает таймеры: для тестов и закрытия страницы. */
    stop() {
      clearTimers();
    },
  };
}
