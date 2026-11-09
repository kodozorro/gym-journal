// Обращения к мостику — веб-приложению Apps Script, привязанному к таблице.
//
// Все обращения — POST с JSON в теле и заголовком Content-Type: text/plain. Такой запрос
// «простой»: браузер не шлёт перед ним OPTIONS, на который Apps Script не отвечает.
// Ключ едет в теле запроса: в адресе он попал бы в журналы, а заголовок вызвал бы OPTIONS.

export const API_VERSION = 1;
/** Версия кода скрипта, под которую написано приложение. */
export const EXPECTED_SCRIPT = 1;

export class BridgeError extends Error {
  /** @param {string} code короткий код: network, timeout, unauthorized… */
  constructor(code, message) {
    super(message);
    this.name = 'BridgeError';
    this.code = code;
  }
}

const SCRIPT_URL = /^https:\/\/script\.google\.com\/(?:a\/macros\/[^/\s]+\/s|a\/[^/\s]+\/macros\/s|macros\/s)\/[A-Za-z0-9_-]{8,}\/(exec|dev)$/;
const LOCAL_URL = /^http:\/\/(?:localhost|127\.0\.0\.1)(?::\d{1,5})?\/\S*$/;

/**
 * Проверяет адрес веб-приложения. Ключ отправляется только на script.google.com:
 * опечатка в адресе не должна унести его на чужой сервер.
 * @param {string} input
 * @param {{allowLocal?: boolean}} [options] allowLocal — разрешить локальную заглушку при разработке
 * @returns {{url: string}|{error: string}}
 */
export function normalizeBridgeUrl(input, { allowLocal = false } = {}) {
  let text = String(input ?? '').trim().replace(/^[<"'«]+|[>"'»]+$/g, '');
  if (!text) return { error: 'Вставьте адрес веб-приложения.' };
  if (allowLocal && LOCAL_URL.test(text)) return { url: text };
  text = text.replace(/[?#].*$/, '');
  const match = SCRIPT_URL.exec(text);
  if (!match) {
    return { error: 'Адрес должен начинаться с https://script.google.com/macros/s/ и заканчиваться на /exec.' };
  }
  if (match[1] === 'dev') {
    return { error: 'Это тестовый адрес, он заканчивается на /dev. Нужен адрес развёртывания: он заканчивается на /exec.' };
  }
  return { url: text };
}

/** Достаёт адрес и ключ из вставленного текста: их удобно переслать на телефон одним сообщением. */
export function extractConnection(text) {
  const source = String(text ?? '');
  const out = {};
  const url = /https:\/\/script\.google\.com\/[^\s"'<>«»]+?\/(?:exec|dev)\b/.exec(source) || /http:\/\/(?:localhost|127\.0\.0\.1)(?::\d{1,5})?\/[^\s"'<>«»]*/.exec(source);
  if (url) out.url = url[0];
  const key = /(?:^|[^0-9a-f])([0-9a-f]{40})(?![0-9a-f])/i.exec(source.replace(out.url || '', ' '));
  if (key) out.key = key[1];
  return out;
}

/**
 * Вызывает мостик и возвращает разобранный ответ.
 * @param {{url: string, key: string}} conn
 * @param {'ping'|'pull'|'push'} action
 * @param {object} [payload]
 * @param {{fetch?: typeof fetch, timeoutMs?: number}} [options]
 * @throws {BridgeError}
 */
export async function callBridge(conn, action, payload = {}, options = {}) {
  const fetchFn = options.fetch || globalThis.fetch;
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), options.timeoutMs ?? 40000);
  let status = 0;
  let text;
  try {
    const response = await fetchFn(conn.url, {
      method: 'POST',
      headers: { 'Content-Type': 'text/plain;charset=utf-8' },
      body: JSON.stringify({ ...payload, key: conn.key, action }),
      // Ответ приходит через перенаправление на script.googleusercontent.com.
      redirect: 'follow',
      credentials: 'omit',
      cache: 'no-store',
      referrerPolicy: 'no-referrer',
      signal: controller.signal,
    });
    status = response.status;
    text = await response.text();
  } catch {
    if (controller.signal.aborted) throw new BridgeError('timeout', 'Скрипт таблицы не ответил вовремя.');
    throw new BridgeError('network', 'Нет связи со скриптом таблицы.');
  } finally {
    clearTimeout(timer);
  }

  let data;
  try {
    data = JSON.parse(text);
  } catch {
    data = null;
  }
  if (!data || typeof data !== 'object' || Array.isArray(data)) {
    throw new BridgeError(
      'not_json',
      `Скрипт ответил страницей вместо данных${status && status !== 200 ? ` (код ${status})` : ''}. ` +
        'Проверьте, что в развёртывании доступ «Все» и что после правки кода выпущена новая версия.',
    );
  }
  if (data.ok !== true) {
    throw new BridgeError(
      typeof data.error === 'string' && data.error ? data.error : 'bridge',
      typeof data.message === 'string' && data.message ? data.message : 'Скрипт таблицы вернул ошибку.',
    );
  }
  if (data.api !== API_VERSION) {
    throw new BridgeError('api_mismatch', 'Скрипт в таблице другой версии. Обновите код скрипта по инструкции и выпустите новую версию развёртывания.');
  }
  return data;
}
