/**
 * Журнал тренировок: мостик между приложением и этой таблицей.
 *
 * Скрипт привязан к таблице и развёрнут как веб-приложение. Приложение на телефоне
 * присылает ему записи, а он кладёт их в ячейки ввода листа «Журнал»: столбцы E–J и L.
 * Формулы, план, даты и остальные листы скрипт только читает.
 *
 * Каждое обращение несёт секретный ключ. Ключ хранится в свойствах скрипта, а не в коде,
 * поэтому сам код можно держать в открытом репозитории.
 *
 * Как поставить: docs/setup.md в репозитории приложения.
 *
 * @OnlyCurrentDoc
 */

var API_VERSION = 1;
var SCRIPT_VERSION = 1;

var SHEET_JOURNAL = 'Журнал';
var SHEET_PROGRESS = 'Прогресс';
var KEY_PROPERTY = 'GJ_KEY';

// Таблица считает строку ходьбой, когда в столбце «Тренировка» стоит «Ходьба».
var WALK_WORKOUT = 'ходьба';

var HEADER_ROW = 2;
var FIRST_ROW = 3;
var COLUMNS = 13;
var HEADERS = [
  'Дата', 'Тренировка', 'Упражнение', 'План', 'Вес, кг', 'Подход 1', 'Подход 2',
  'Подход 3', 'Км', 'Мин', 'Тренажёр', 'Заметка', 'Неделя'
];

// Номера столбцов листа «Журнал», считая с единицы.
var COL_DATE = 1;
var COL_WORKOUT = 2;
var COL_EXERCISE = 3;
var COL_PLAN = 4;
var COL_WEIGHT = 5; // E — ввод
var COL_SET1 = 6; // F, G, H — ввод
var COL_KM = 9; // I — ввод
var COL_MIN = 10; // J — ввод
var COL_MACHINE = 11;
var COL_NOTE = 12; // L — ввод
var COL_WEEK = 13;

var LIMITS = {
  body: 200000, // символов в запросе
  entries: 400, // записей в одном запросе
  weight: 1000, // кг
  reps: 500,
  km: 200,
  min: 1440,
  note: 500, // символов
  name: 200,
  occ: 50
};

/* ------------------------------------------------------------------ */
/* Точки входа веб-приложения                                          */
/* ------------------------------------------------------------------ */

/** Все обращения приложения: POST с JSON в теле и заголовком Content-Type: text/plain. */
function doPost(e) {
  var out;
  try {
    out = handle_(e && e.postData ? e.postData.contents : '');
  } catch (err) {
    // Если скрипт упадёт с исключением, Google отдаст HTML без заголовков CORS,
    // и приложение увидит только «ошибку сети». Поэтому ответ всегда JSON.
    out = fail_(err && err.code ? err.code : 'internal', err && err.message ? String(err.message) : String(err));
  }
  return json_(out);
}

/** Открытие адреса в браузере: короткая проверка, что развёртывание работает. Данных не отдаёт. */
function doGet() {
  return json_({
    ok: true,
    service: 'gym-journal',
    api: API_VERSION,
    script: SCRIPT_VERSION,
    hint: 'Мостик работает. Данные отдаются только приложению: POST-запросом с ключом.'
  });
}

/* ------------------------------------------------------------------ */
/* Функции для запуска из редактора                                    */
/* ------------------------------------------------------------------ */

/**
 * Запустите один раз из редактора: создаёт секретный ключ, проверяет листы
 * и печатает ключ в журнал выполнения. Повторный запуск ключ не меняет.
 */
function setup() {
  var props = PropertiesService.getScriptProperties();
  var key = props.getProperty(KEY_PROPERTY);
  var created = false;
  if (!key) {
    key = newKey_();
    props.setProperty(KEY_PROPERTY, key);
    created = true;
  }
  var ss = spreadsheet_();
  var sheet = journalSheet_(ss);
  var data = readRows_(sheet, ss.getSpreadsheetTimeZone());
  console.log('Лист «Журнал» найден, строк с упражнениями: ' + data.rows.length + '.');
  if (data.rows.length) {
    console.log('Даты журнала: с ' + data.rows[0].date + ' по ' + data.rows[data.rows.length - 1].date + '.');
  }
  console.log(created ? 'Секретный ключ создан.' : 'Секретный ключ уже был создан раньше, он не менялся.');
  console.log('Ключ для приложения: ' + key);
  console.log('Дальше: «Начать развёртывание» → «Новое развёртывание» → тип «Веб-приложение».');
  return key;
}

/** Меняет ключ на новый. Старый перестаёт работать: новый нужно вставить в настройки приложения. */
function resetKey() {
  var key = newKey_();
  PropertiesService.getScriptProperties().setProperty(KEY_PROPERTY, key);
  console.log('Ключ заменён. Новый ключ для приложения: ' + key);
  return key;
}

/* ------------------------------------------------------------------ */
/* Разбор запроса                                                      */
/* ------------------------------------------------------------------ */

function handle_(raw) {
  if (typeof raw !== 'string' || raw === '') return fail_('bad_request', 'Пустой запрос.');
  if (raw.length > LIMITS.body) return fail_('too_large', 'Слишком большой запрос.');
  var req;
  try {
    req = JSON.parse(raw);
  } catch (err) {
    return fail_('bad_json', 'Запрос не разобран как JSON.');
  }
  if (!isObject_(req)) return fail_('bad_request', 'Ожидается объект JSON.');

  var denied = checkKey_(req.key);
  if (denied) return denied;

  if (req.action === 'ping') return ok_({});
  if (req.action === 'pull') return pull_();
  if (req.action === 'push') return push_(req);
  return fail_('unknown_action', 'Неизвестное действие.');
}

function checkKey_(key) {
  var stored = PropertiesService.getScriptProperties().getProperty(KEY_PROPERTY);
  if (!stored) {
    return fail_('no_key', 'Ключ ещё не создан: запустите функцию setup в редакторе скрипта.');
  }
  if (typeof key !== 'string' || !safeEqual_(key, stored)) {
    return fail_('unauthorized', 'Неверный ключ.');
  }
  return null;
}

/** Сравнение строк без раннего выхода, чтобы время ответа не подсказывало ключ. */
function safeEqual_(a, b) {
  var diff = a.length ^ b.length;
  for (var i = 0; i < b.length; i++) {
    diff |= (i < a.length ? a.charCodeAt(i) : 0) ^ b.charCodeAt(i);
  }
  return diff === 0;
}

/* ------------------------------------------------------------------ */
/* Чтение                                                              */
/* ------------------------------------------------------------------ */

function pull_() {
  var ss = spreadsheet_();
  var sheet = journalSheet_(ss);
  return ok_(snapshot_(ss, sheet));
}

function snapshot_(ss, sheet) {
  var tz = ss.getSpreadsheetTimeZone();
  var data = readRows_(sheet, tz);
  var start = null;
  var goal = null;
  var progress = ss.getSheetByName(SHEET_PROGRESS);
  if (progress) {
    var cells = progress.getRange(1, 2, 2, 1).getValues(); // B1 — старт, B2 — цель по ходьбе
    if (isDate_(cells[0][0])) start = formatDate_(cells[0][0], tz);
    if (isNumber_(cells[1][0])) goal = cells[1][0];
  }
  return { tz: tz, start: start, walkGoalKm: goal, journal: data.rows };
}

/**
 * Читает лист «Журнал». Строка данных — та, где в столбце A дата, а в столбце C название.
 * Строки-подсказки и пустые строки пропускаются.
 * Строка ищется по паре «дата + упражнение», а не по номеру: номера сдвигаются,
 * когда журнал продлевают или вставляют строки.
 */
function readRows_(sheet, tz) {
  var out = { rows: [], index: {}, raw: {} };
  var last = sheet.getLastRow();
  if (last < FIRST_ROW) return out;
  var values = sheet.getRange(FIRST_ROW, 1, last - FIRST_ROW + 1, COLUMNS).getValues();
  var seen = {};
  for (var i = 0; i < values.length; i++) {
    var v = values[i];
    if (!isDate_(v[COL_DATE - 1])) continue;
    var exercise = text_(v[COL_EXERCISE - 1]);
    if (!exercise) continue;
    var date = formatDate_(v[COL_DATE - 1], tz);
    var base = date + '|' + exercise;
    var occ = seen[base] || 0;
    seen[base] = occ + 1;
    var row = {
      date: date,
      workout: text_(v[COL_WORKOUT - 1]),
      exercise: exercise,
      plan: text_(v[COL_PLAN - 1]),
      machine: text_(v[COL_MACHINE - 1]),
      week: isNumber_(v[COL_WEEK - 1]) ? v[COL_WEEK - 1] : null,
      weight: number_(v[COL_WEIGHT - 1]),
      sets: [number_(v[COL_SET1 - 1]), number_(v[COL_SET1]), number_(v[COL_SET1 + 1])],
      km: number_(v[COL_KM - 1]),
      min: number_(v[COL_MIN - 1]),
      note: text_(v[COL_NOTE - 1])
    };
    if (occ) row.occ = occ; // вторая и следующие строки с той же датой и названием
    out.rows.push(row);
    out.index[base + '|' + occ] = FIRST_ROW + i;
    out.raw[FIRST_ROW + i] = v;
  }
  return out;
}

/* ------------------------------------------------------------------ */
/* Запись                                                              */
/* ------------------------------------------------------------------ */

function push_(req) {
  var entries = req.entries;
  if (!Array.isArray(entries)) return fail_('bad_request', 'Поле entries должно быть списком.');
  if (entries.length > LIMITS.entries) return fail_('too_many', 'Слишком много записей в одном запросе.');

  var lock = LockService.getScriptLock();
  if (!lock.tryLock(25000)) return fail_('busy', 'Таблица занята другой записью. Повторите позже.');
  try {
    var ss = spreadsheet_();
    var sheet = journalSheet_(ss);
    var data = readRows_(sheet, ss.getSpreadsheetTimeZone());
    var results = [];
    for (var i = 0; i < entries.length; i++) {
      results.push(writeEntry_(sheet, data, entries[i]));
    }
    SpreadsheetApp.flush();
    var out = ok_({ results: results });
    if (req.pull === true) {
      var snap = snapshot_(ss, sheet);
      out.tz = snap.tz;
      out.start = snap.start;
      out.walkGoalKm = snap.walkGoalKm;
      out.journal = snap.journal;
    }
    return out;
  } finally {
    lock.releaseLock();
  }
}

/**
 * Записывает одну запись. Запись несёт состояние ячеек, а не изменение:
 * «в этой строке вес 30, подходы 15 и 14». Повторная отправка ничего не портит.
 * Пишутся только те поля, которые есть в записи, и только в столбцы E–J и L.
 */
function writeEntry_(sheet, data, entry) {
  var parsed = parseEntry_(entry);
  if (parsed.error) return result_(entry, 'rejected', parsed.error);

  var rowNumber = data.index[parsed.date + '|' + parsed.exercise + '|' + parsed.occ];
  if (!rowNumber) return result_(parsed, 'not_found', 'В журнале нет строки с такой датой и упражнением.');

  var raw = data.raw[rowNumber];
  var patch = parsed.patch;
  var walk = norm_(raw[COL_WORKOUT - 1]) === WALK_WORKOUT;
  if (walk && (has_(patch, 'weight') || has_(patch, 'sets'))) {
    return result_(parsed, 'rejected', 'Это строка ходьбы: вес и подходы в неё не пишутся.');
  }
  if (!walk && (has_(patch, 'km') || has_(patch, 'min'))) {
    return result_(parsed, 'rejected', 'Это силовая строка: километры и минуты в неё не пишутся.');
  }

  var changed = false;
  if (has_(patch, 'weight') && !sameCell_(raw[COL_WEIGHT - 1], patch.weight)) {
    sheet.getRange(rowNumber, COL_WEIGHT).setValue(cell_(patch.weight));
    raw[COL_WEIGHT - 1] = cell_(patch.weight);
    changed = true;
  }
  if (has_(patch, 'sets')) {
    var differs = false;
    for (var s = 0; s < 3; s++) {
      if (!sameCell_(raw[COL_SET1 - 1 + s], patch.sets[s])) differs = true;
    }
    if (differs) {
      var cells = [cell_(patch.sets[0]), cell_(patch.sets[1]), cell_(patch.sets[2])];
      sheet.getRange(rowNumber, COL_SET1, 1, 3).setValues([cells]);
      for (var k = 0; k < 3; k++) raw[COL_SET1 - 1 + k] = cells[k];
      changed = true;
    }
  }
  if (has_(patch, 'km') && !sameCell_(raw[COL_KM - 1], patch.km)) {
    sheet.getRange(rowNumber, COL_KM).setValue(cell_(patch.km));
    raw[COL_KM - 1] = cell_(patch.km);
    changed = true;
  }
  if (has_(patch, 'min') && !sameCell_(raw[COL_MIN - 1], patch.min)) {
    sheet.getRange(rowNumber, COL_MIN).setValue(cell_(patch.min));
    raw[COL_MIN - 1] = cell_(patch.min);
    changed = true;
  }
  if (has_(patch, 'note') && text_(raw[COL_NOTE - 1]) !== patch.note) {
    sheet.getRange(rowNumber, COL_NOTE).setValue(noteCell_(patch.note));
    raw[COL_NOTE - 1] = patch.note;
    changed = true;
  }
  return result_(parsed, changed ? 'written' : 'unchanged');
}

/** Проверяет типы и разумные границы чисел. Возвращает { date, exercise, occ, patch } или { error }. */
function parseEntry_(entry) {
  if (!isObject_(entry)) return { error: 'Запись должна быть объектом.' };
  if (!isIsoDate_(entry.date)) return { error: 'Неверная дата записи.' };
  if (typeof entry.exercise !== 'string' || !entry.exercise || entry.exercise.length > LIMITS.name) {
    return { error: 'Не указано упражнение.' };
  }
  var occ = entry.occ === undefined || entry.occ === null ? 0 : entry.occ;
  if (!isInt_(occ) || occ < 0 || occ > LIMITS.occ) return { error: 'Неверный номер строки-повтора.' };

  var patch = {};
  if (has_(entry, 'weight')) {
    var weight = bounded_(entry.weight, LIMITS.weight, 2);
    if (weight === undefined) return { error: 'Вес должен быть числом от 0 до ' + LIMITS.weight + '.' };
    patch.weight = weight;
  }
  if (has_(entry, 'sets')) {
    if (!Array.isArray(entry.sets) || entry.sets.length > 3) return { error: 'Подходы должны быть списком до трёх чисел.' };
    var sets = [null, null, null];
    for (var i = 0; i < entry.sets.length; i++) {
      var reps = entry.sets[i];
      if (reps === null) continue;
      if (!isInt_(reps) || reps < 0 || reps > LIMITS.reps) {
        return { error: 'Повторы должны быть целым числом от 0 до ' + LIMITS.reps + '.' };
      }
      sets[i] = reps;
    }
    patch.sets = sets;
  }
  if (has_(entry, 'km')) {
    var km = bounded_(entry.km, LIMITS.km, 2);
    if (km === undefined) return { error: 'Километры должны быть числом от 0 до ' + LIMITS.km + '.' };
    patch.km = km;
  }
  if (has_(entry, 'min')) {
    var min = bounded_(entry.min, LIMITS.min, 1);
    if (min === undefined) return { error: 'Минуты должны быть числом от 0 до ' + LIMITS.min + '.' };
    patch.min = min;
  }
  if (has_(entry, 'note')) {
    if (typeof entry.note !== 'string') return { error: 'Заметка должна быть текстом.' };
    var note = entry.note.replace(/[\u0000-\u0008\u000B\u000C\u000E-\u001F\u007F]/g, '').trim();
    if (note.length > LIMITS.note) return { error: 'Заметка длиннее ' + LIMITS.note + ' символов.' };
    patch.note = note;
  }
  return { date: entry.date, exercise: entry.exercise, occ: occ, patch: patch };
}

/* ------------------------------------------------------------------ */
/* Таблица                                                             */
/* ------------------------------------------------------------------ */

function spreadsheet_() {
  var ss = SpreadsheetApp.getActiveSpreadsheet();
  if (!ss) {
    throw coded_('no_spreadsheet', 'Скрипт не привязан к таблице. Создайте его из таблицы: «Расширения» → «Apps Script».');
  }
  return ss;
}

/**
 * Возвращает лист «Журнал», предварительно сверив заголовки. Если столбцы переставлены
 * или переименованы, скрипт останавливается и ничего не пишет: иначе числа попадут не туда.
 */
function journalSheet_(ss) {
  var sheet = ss.getSheetByName(SHEET_JOURNAL);
  if (!sheet) throw coded_('no_journal', 'В таблице нет листа «Журнал».');
  var header = sheet.getRange(HEADER_ROW, 1, 1, COLUMNS).getValues()[0];
  for (var i = 0; i < HEADERS.length; i++) {
    if (norm_(header[i]) !== norm_(HEADERS[i])) {
      throw coded_(
        'layout_changed',
        'Заголовки листа «Журнал» изменились: в столбце ' + String.fromCharCode(65 + i) +
          ' ожидается «' + HEADERS[i] + '». Запись остановлена, чтобы не испортить таблицу.'
      );
    }
  }
  return sheet;
}

/* ------------------------------------------------------------------ */
/* Мелкие помощники                                                    */
/* ------------------------------------------------------------------ */

function ok_(extra) {
  var out = { ok: true, api: API_VERSION, script: SCRIPT_VERSION };
  for (var key in extra) {
    if (has_(extra, key)) out[key] = extra[key];
  }
  return out;
}

function fail_(code, message) {
  return { ok: false, api: API_VERSION, script: SCRIPT_VERSION, error: code, message: message };
}

function coded_(code, message) {
  var err = new Error(message);
  err.code = code;
  return err;
}

function result_(source, status, reason) {
  var out = {
    date: source && typeof source.date === 'string' ? source.date : null,
    exercise: source && typeof source.exercise === 'string' ? source.exercise : null,
    status: status
  };
  if (source && isInt_(source.occ) && source.occ > 0) out.occ = source.occ;
  if (reason) out.reason = reason;
  return out;
}

function json_(obj) {
  return ContentService.createTextOutput(JSON.stringify(obj)).setMimeType(ContentService.MimeType.JSON);
}

function newKey_() {
  return (Utilities.getUuid() + Utilities.getUuid()).replace(/-/g, '').slice(0, 40);
}

function has_(obj, key) {
  return Object.prototype.hasOwnProperty.call(obj, key);
}

function isObject_(value) {
  return value !== null && typeof value === 'object' && !Array.isArray(value);
}

function isDate_(value) {
  return Object.prototype.toString.call(value) === '[object Date]' && !isNaN(value.getTime());
}

function isNumber_(value) {
  return typeof value === 'number' && isFinite(value);
}

function isInt_(value) {
  return isNumber_(value) && Math.floor(value) === value;
}

function isIsoDate_(value) {
  if (typeof value !== 'string' || !/^\d{4}-\d{2}-\d{2}$/.test(value)) return false;
  var parts = value.split('-');
  var date = new Date(Date.UTC(Number(parts[0]), Number(parts[1]) - 1, Number(parts[2])));
  return date.getUTCFullYear() === Number(parts[0]) && date.getUTCMonth() === Number(parts[1]) - 1 &&
    date.getUTCDate() === Number(parts[2]);
}

/** Число из ячейки или null: текст в числовой ячейке приложению не передаётся. */
function number_(value) {
  return isNumber_(value) ? value : null;
}

function text_(value) {
  if (value === null || value === undefined) return '';
  if (isDate_(value)) return '';
  return String(value).trim();
}

function norm_(value) {
  return text_(value).toLowerCase().replace(/\s+/g, ' ');
}

/** null — очистить ячейку; число в границах, округлённое до digits знаков; иначе undefined. */
function bounded_(value, max, digits) {
  if (value === null) return null;
  if (!isNumber_(value) || value < 0 || value > max) return undefined;
  var k = Math.pow(10, digits);
  return Math.round(value * k) / k;
}

/** Числа отправляются числами: строку вида «3.5» таблица в русской локали может принять за дату. */
function cell_(value) {
  return value === null ? '' : value;
}

function sameCell_(current, wanted) {
  if (wanted === null) return current === '' || current === null;
  return isNumber_(current) && current === wanted;
}

/**
 * Заметка всегда хранится как текст. Апостроф в начале — стандартная пометка
 * «это текст»: в ячейке он не виден, зато «=…», «10.11» и «+5» не превратятся в формулу или дату.
 */
function noteCell_(note) {
  return note === '' ? '' : "'" + note;
}

/** Дата из ячейки в виде yyyy-MM-dd по часовому поясу таблицы, а не скрипта. */
function formatDate_(date, tz) {
  return Utilities.formatDate(date, tz, 'yyyy-MM-dd');
}
