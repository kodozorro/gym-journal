// Подмена среды Google Apps Script для Node: таблица в памяти и глобальные сервисы.
// Нужна тестам и локальной заглушке мостика, чтобы гонять настоящий apps-script/Code.gs
// без доступа к Google. Ведёт журнал записей и ловит попытки писать в защищённые ячейки.

import vm from 'node:vm';
import fs from 'node:fs';
import crypto from 'node:crypto';

/** Момент полуночи указанной даты в часовом поясе tz (так Apps Script отдаёт даты из ячеек). */
export function zonedMidnight(iso, tz) {
  const [y, m, d] = iso.split('-').map(Number);
  const guess = Date.UTC(y, m - 1, d);
  const first = guess - zoneOffset(guess, tz);
  return new Date(guess - zoneOffset(first, tz));
}

function zoneOffset(ms, tz) {
  const parts = new Intl.DateTimeFormat('en-US', {
    timeZone: tz, hourCycle: 'h23', year: 'numeric', month: 'numeric', day: 'numeric',
    hour: 'numeric', minute: 'numeric', second: 'numeric',
  }).formatToParts(new Date(ms));
  const get = (type) => Number(parts.find((p) => p.type === type).value);
  const asUTC = Date.UTC(get('year'), get('month') - 1, get('day'), get('hour'), get('minute'), get('second'));
  return asUTC - Math.floor(ms / 1000) * 1000;
}

export function formatInZone(date, tz) {
  return new Intl.DateTimeFormat('en-CA', { timeZone: tz, year: 'numeric', month: '2-digit', day: '2-digit' }).format(date);
}

/**
 * Имитация того, как таблица разбирает строку, записанную через setValue:
 * апостроф в начале означает текст, «=…» — формула, а похожее на число или дату
 * превращается в число или дату. Скрипт обязан с этим считаться.
 */
function userEntered(value) {
  if (value === null || value === undefined || value === '') return { v: '' };
  if (typeof value !== 'string') return { v: value };
  if (value.startsWith("'")) return { v: value.slice(1), text: true };
  if (value.startsWith('=')) return { v: value, formula: true };
  if (/^\d{1,2}\.\d{1,2}$/.test(value)) {
    const [d, m] = value.split('.').map(Number);
    return { v: new Date(Date.UTC(2026, m - 1, d)), coerced: true };
  }
  if (/^[+-]?\d+(?:,\d+)?$/.test(value)) return { v: Number(value.replace(',', '.')), coerced: true };
  if (/^(true|false|истина|ложь)$/i.test(value)) return { v: /^(true|истина)$/i.test(value), coerced: true };
  return { v: value };
}

export class FakeSheet {
  constructor(name) {
    this.name = name;
    this.cells = new Map(); // "row,col" → значение
    this.protected = new Set(); // "row,col" ячеек с формулами, заголовками и подсказками
    this.writes = []; // журнал записей { row, col, value, previous }
    this.violations = []; // записи в защищённые ячейки и опасные строки
    this.reads = 0;
  }

  static key(row, col) {
    return `${row},${col}`;
  }

  /** Заполнение при построении фикстуры, мимо журнала записей. */
  seed(row, col, value, { protect = false } = {}) {
    if (value === '' || value === null || value === undefined) this.cells.delete(FakeSheet.key(row, col));
    else this.cells.set(FakeSheet.key(row, col), value);
    if (protect) this.protected.add(FakeSheet.key(row, col));
  }

  protect(row, col) {
    this.protected.add(FakeSheet.key(row, col));
  }

  peek(row, col) {
    const value = this.cells.get(FakeSheet.key(row, col));
    return value === undefined ? '' : value;
  }

  /** Ручная правка пользователем в таблице: мимо журнала записей скрипта. */
  manualEdit(row, col, value) {
    this.seed(row, col, value);
  }

  write(row, col, value) {
    const key = FakeSheet.key(row, col);
    const parsed = userEntered(value);
    const previous = this.peek(row, col);
    this.writes.push({ row, col, value: parsed.v, previous });
    if (this.protected.has(key)) this.violations.push({ kind: 'protected', row, col, value });
    if (parsed.formula) this.violations.push({ kind: 'formula', row, col, value });
    if (parsed.coerced) this.violations.push({ kind: 'coerced', row, col, value });
    if (parsed.v === '') this.cells.delete(key);
    else this.cells.set(key, parsed.v);
  }

  getName() {
    return this.name;
  }

  getLastRow() {
    let last = 0;
    for (const key of this.cells.keys()) last = Math.max(last, Number(key.split(',')[0]));
    return last;
  }

  getRange(row, col, numRows = 1, numCols = 1) {
    if (![row, col, numRows, numCols].every((n) => Number.isInteger(n) && n >= 1)) {
      throw new Error(`getRange: неверные координаты (${row}, ${col}, ${numRows}, ${numCols})`);
    }
    return new FakeRange(this, row, col, numRows, numCols);
  }
}

class FakeRange {
  constructor(sheet, row, col, numRows, numCols) {
    Object.assign(this, { sheet, row, col, numRows, numCols });
  }

  getValues() {
    this.sheet.reads += 1;
    const out = [];
    for (let r = 0; r < this.numRows; r += 1) {
      const line = [];
      for (let c = 0; c < this.numCols; c += 1) {
        const value = this.sheet.peek(this.row + r, this.col + c);
        line.push(value instanceof Date ? new Date(value.getTime()) : value);
      }
      out.push(line);
    }
    return out;
  }

  getValue() {
    return this.getValues()[0][0];
  }

  setValue(value) {
    for (let r = 0; r < this.numRows; r += 1) {
      for (let c = 0; c < this.numCols; c += 1) this.sheet.write(this.row + r, this.col + c, value);
    }
    return this;
  }

  setValues(values) {
    if (!Array.isArray(values) || values.length !== this.numRows || values.some((line) => line.length !== this.numCols)) {
      throw new Error('setValues: размер данных не совпадает с размером диапазона');
    }
    values.forEach((line, r) => line.forEach((value, c) => this.sheet.write(this.row + r, this.col + c, value)));
    return this;
  }
}

export class FakeSpreadsheet {
  constructor({ name = 'Тестовая таблица', timeZone = 'Etc/GMT', sheets = [] } = {}) {
    this.name = name;
    this.timeZone = timeZone;
    this.sheets = sheets;
  }

  getName() {
    return this.name;
  }

  getSpreadsheetTimeZone() {
    return this.timeZone;
  }

  getSheetByName(name) {
    return this.sheets.find((sheet) => sheet.name === name) || null;
  }

  get violations() {
    return this.sheets.flatMap((sheet) => sheet.violations.map((v) => ({ sheet: sheet.name, ...v })));
  }
}

/** Глобальные сервисы Apps Script поверх таблицы в памяти. */
export function createGasEnvironment({ spreadsheet, properties = {}, logs = [] } = {}) {
  const props = new Map(Object.entries(properties));
  const lock = { available: true, held: false, acquired: 0, released: 0 };
  const state = { spreadsheet, props, lock, logs, flushes: 0 };
  const globals = {
    SpreadsheetApp: {
      getActiveSpreadsheet: () => state.spreadsheet,
      flush: () => {
        state.flushes += 1;
      },
      // Скрипт помечен @OnlyCurrentDoc: открывать таблицу по ID ему нельзя.
      openById: () => {
        throw new Error('openById недоступен при @OnlyCurrentDoc');
      },
    },
    PropertiesService: {
      getScriptProperties: () => ({
        getProperty: (key) => (props.has(key) ? props.get(key) : null),
        setProperty: (key, value) => {
          props.set(key, String(value));
        },
        deleteProperty: (key) => {
          props.delete(key);
        },
      }),
    },
    LockService: {
      getScriptLock: () => ({
        tryLock: () => {
          if (!lock.available || lock.held) return false;
          lock.held = true;
          lock.acquired += 1;
          return true;
        },
        releaseLock: () => {
          if (lock.held) lock.released += 1;
          lock.held = false;
        },
      }),
    },
    ContentService: {
      MimeType: { JSON: 'application/json', TEXT: 'text/plain' },
      createTextOutput: (text) => ({
        content: String(text),
        mimeType: 'text/plain',
        getContent() {
          return this.content;
        },
        setMimeType(mime) {
          this.mimeType = mime;
          return this;
        },
      }),
    },
    Utilities: {
      formatDate: (date, tz, format) => {
        if (format !== 'yyyy-MM-dd') throw new Error(`formatDate: формат ${format} в подмене не поддержан`);
        return formatInZone(date, tz);
      },
      getUuid: () => crypto.randomUUID(),
    },
    console: {
      log: (...args) => logs.push(args.join(' ')),
      warn: (...args) => logs.push(args.join(' ')),
      error: (...args) => logs.push(args.join(' ')),
    },
    Logger: { log: (...args) => logs.push(args.join(' ')) },
  };
  return { globals, state };
}

/** Загружает Code.gs в отдельный контекст и возвращает его глобальные функции. */
export function loadAppsScript(file, environment) {
  const context = vm.createContext({ ...environment.globals });
  vm.runInContext(fs.readFileSync(file, 'utf8'), context, { filename: file });
  return context;
}

/** Вызов веб-приложения так, как это делает Google: тело запроса — строка в e.postData.contents. */
export function post(script, body) {
  const raw = typeof body === 'string' ? body : JSON.stringify(body);
  const output = script.doPost({ postData: { contents: raw, type: 'text/plain' } });
  return { mimeType: output.mimeType, text: output.getContent(), json: JSON.parse(output.getContent()) };
}
