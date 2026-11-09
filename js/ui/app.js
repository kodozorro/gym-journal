// Каркас приложения: шапка, экраны, нижняя панель, таймер отдыха и все действия пользователя.
//
// Состояние живёт в трёх местах: журнал и очередь записей — в sync, настройки — в store,
// всё сиюминутное (открытые карточки, окно ввода, таймер) — в объекте ui ниже.
// После любого изменения экран описывается заново, а vdom приводит страницу к описанию.

import { h, render, cx } from './vdom.js';
import { icon } from './icons.js';
import { dayScreen, selectedSet, slotsOf, todayScreen } from './day.js';
import { planScreen, weekOfDate } from './plan.js';
import { progressScreen } from './progress.js';
import { settingsScreen } from './settings.js';
import { sheetView } from './sheets.js';
import {
  groupDays, isDone, isWalk, lastTime, nextSetIndex, roundComplete, rowKey, setsOf, splitDay, summarize,
} from '../core/journal.js';
import { MAX_SETS, strengthPlan } from '../core/plan.js';
import { formatLongDay, formatNumericDay, formatShortDay, isISODate, mondayOf, todayISO } from '../core/dates.js';
import { formatNumber, roundTo } from '../core/numbers.js';
import {
  extendRest, formatClock, restLeft, restOver, restOvertime, restProgress, startRest, validRest,
} from '../core/timer.js';
import { fieldError, fieldValue, makeField, pressKey } from '../core/keypad.js';
import { weeksOf } from '../core/stats.js';
import { normalizeBridgeUrl, extractConnection } from '../data/api.js';

/** Через сколько секунд после конца отдыха панель таймера убирается сама. */
const OVERTIME_HIDE_SEC = 600;
/** Сигнал подаётся, только если конец отдыха застали вовремя, а не вернулись в приложение позже. */
const SIGNAL_WINDOW_MS = 3000;
const NOTE_LIMIT = 500;

const TABS = [
  { name: 'today', href: '#/today', label: 'Сегодня', icon: 'today' },
  { name: 'plan', href: '#/plan', label: 'План', icon: 'plan' },
  { name: 'progress', href: '#/progress', label: 'Прогресс', icon: 'progress' },
  { name: 'settings', href: '#/settings', label: 'Настройки', icon: 'settings' },
];

const CONNECT_ERRORS = {
  unauthorized: 'Ключ не подошёл. Скопируйте его заново из журнала выполнения функции setup.',
  network: 'Нет связи со скриптом. Проверьте интернет и адрес.',
  timeout: 'Скрипт не ответил вовремя. Попробуйте ещё раз.',
};

export function parseRoute(hash) {
  const [name, arg] = String(hash || '').replace(/^#\/?/, '').split('/');
  if (name === 'day' && isISODate(arg)) return { name: 'day', date: arg };
  if (name === 'plan' || name === 'progress' || name === 'settings') return { name };
  return { name: 'today' };
}

const capitalize = (text) => (text ? text[0].toUpperCase() + text.slice(1) : text);

/**
 * @param {object} deps
 * @param {HTMLElement} deps.root
 * @param {ReturnType<import('../data/storage.js').createStorage>} deps.storage
 * @param {ReturnType<import('../data/store.js').createStore>} deps.store
 * @param {ReturnType<import('../data/sync.js').createSync>} deps.sync
 * @param {ReturnType<import('../platform/feedback.js').createFeedback>} deps.feedback
 * @param {ReturnType<import('../platform/pwa.js').createPwa>} deps.pwa
 * @param {{local: boolean}} deps.env local — приложение открыто с localhost, разрешён учебный мостик
 */
export function createApp({ root, storage, store, sync, feedback, pwa, env }) {
  const now = () => Date.now();
  const reducedMotion = window.matchMedia('(prefers-reduced-motion: reduce)');

  const ui = {
    route: parseRoute(window.location.hash),
    today: todayISO(new Date(now())),
    /** ручное раскрытие карточек: ключ строки → true/false */
    open: {},
    /** выбранный подход по ключу строки */
    setIndex: {},
    /** сколько ячеек подходов показать, если добавили кнопкой «+» */
    slots: {},
    /** пара, с которой работают: { date, pair } */
    focus: null,
    /** тренировка не своего дня, которую делают сегодня: { date, on } */
    live: null,
    sheet: null,
    form: { url: '', key: '', error: '', busy: false, editing: false },
    toast: null,
    timer: null,
    timerEnded: false,
    timerFlash: false,
    scrollTo: null,
    planScroll: null,
    restorePlan: false,
  };

  let sheetSeq = 0;
  let toastSeq = 0;
  let scheduled = false;
  let ticker = null;
  let memo = { journal: null, snapshot: null, days: [], start: null };

  const savedLive = storage.get('live');
  if (savedLive && isISODate(savedLive.date) && savedLive.on === ui.today) ui.live = { date: savedLive.date, on: savedLive.on };

  const savedTimer = storage.get('timer');
  if (validRest(savedTimer) && now() - savedTimer.endsAt < OVERTIME_HIDE_SEC * 1000) {
    ui.timer = { startedAt: savedTimer.startedAt, endsAt: savedTimer.endsAt, total: savedTimer.total };
    // отдых кончился, пока приложение было закрыто: показываем это, но уже не сигналим
    ui.timerEnded = restOver(ui.timer, now());
  }

  /* ---------------------------------------------------------------- */
  /* Отрисовка                                                         */
  /* ---------------------------------------------------------------- */

  function invalidate() {
    if (scheduled) return;
    scheduled = true;
    queueMicrotask(() => {
      scheduled = false;
      draw();
    });
  }

  function derive(state) {
    if (memo.journal !== state.journal || memo.snapshot !== state.snapshot) {
      const days = groupDays(state.journal);
      const start = state.snapshot && state.snapshot.start ? state.snapshot.start : days.length ? mondayOf(days[0].date) : null;
      memo = { journal: state.journal, snapshot: state.snapshot, days, start };
    }
    return memo;
  }

  const isLive = (date) => date === ui.today || Boolean(ui.live && ui.live.date === date && ui.live.on === ui.today);

  function context() {
    const state = sync.getState();
    const derived = derive(state);
    return {
      state,
      settings: store.get(),
      store,
      ui,
      act,
      pwa: pwa.state,
      env: {
        local: env.local,
        persistent: storage.persistent,
        standalone: pwa.isStandalone(),
        ios: pwa.isIOS(),
        canVibrate: feedback.canVibrate,
        canWakeLock: feedback.canWakeLock,
        canSound: feedback.canSound,
      },
      route: ui.route,
      today: ui.today,
      now: now(),
      journal: state.journal,
      days: derived.days,
      start: derived.start,
      isLive,
    };
  }

  function draw() {
    const ctx = context();
    render(root, view(ctx));
    paintTimer();
    applyTheme(ctx.settings.theme);
    updateWakeLock(ctx);
    if (ui.scrollTo) {
      const key = ui.scrollTo;
      ui.scrollTo = null;
      for (const el of root.querySelectorAll('[data-key]')) {
        if (el.getAttribute('data-key') === key) {
          el.scrollIntoView({ block: 'nearest', behavior: reducedMotion.matches ? 'auto' : 'smooth' });
          break;
        }
      }
    }
  }

  function applyTheme(theme) {
    const html = document.documentElement;
    if (theme === 'light' || theme === 'dark') {
      if (html.getAttribute('data-theme') !== theme) html.setAttribute('data-theme', theme);
    } else if (html.hasAttribute('data-theme')) {
      html.removeAttribute('data-theme');
    }
    // цвет системной полосы над приложением должен совпадать с фоном страницы
    const metas = document.querySelectorAll('meta[name="theme-color"]');
    metas.forEach((meta) => {
      const own = meta.getAttribute('data-scheme');
      const scheme = theme === 'auto' ? own : theme;
      const color = scheme === 'dark' ? '#0d0d0d' : '#f4f3ef';
      if (meta.getAttribute('content') !== color) meta.setAttribute('content', color);
    });
  }

  function updateWakeLock(ctx) {
    const mode = ctx.settings.wakeLock;
    const onWorkout = ctx.state.configured && (ui.route.name === 'today' || ui.route.name === 'day');
    const resting = Boolean(ui.timer) && !ui.timerEnded;
    feedback.keepAwake(mode === 'workout' ? onWorkout || resting : mode === 'rest' ? resting : false);
  }

  /* ---------------------------------------------------------------- */
  /* Разметка каркаса                                                  */
  /* ---------------------------------------------------------------- */

  function pillInfo(state) {
    if (!state.configured) return { tone: '', mark: 'info', text: 'Не подключено' };
    if (state.phase === 'error') return { tone: 'pill--bad', mark: 'alert', text: 'Нужна настройка' };
    if (state.failed.length) return { tone: 'pill--bad', mark: 'alert', text: `Не записано: ${state.failed.length}` };
    if (state.phase === 'syncing') return { tone: 'pill--busy', mark: 'sync', text: state.pending ? 'Отправка…' : 'Обновление…' };
    if (state.pending) {
      if (state.online && state.phase === 'idle') return { tone: 'pill--busy', mark: 'sync', text: 'Отправка…' };
      return { tone: 'pill--wait', mark: state.online ? 'cloudUp' : 'cloudOff', text: `В очереди: ${state.pending}` };
    }
    if (!state.online) return { tone: 'pill--wait', mark: 'cloudOff', text: 'Нет сети' };
    if (state.phase === 'waiting') return { tone: 'pill--wait', mark: 'cloudOff', text: 'Нет связи' };
    return { tone: '', mark: 'check', text: 'Сохранено' };
  }

  function header(ctx) {
    const { route, today, days, state } = ctx;
    let title = 'Сегодня';
    let sub = '';
    let back = null;
    const weekText = (date) => {
      const day = days.find((d) => d.date === date);
      return day && day.week != null ? ` · неделя ${day.week}` : '';
    };
    if (route.name === 'today') {
      sub = capitalize(formatLongDay(today)) + weekText(today);
    } else if (route.name === 'day') {
      const [weekday, dayMonth] = formatLongDay(route.date).split(', ');
      title = capitalize(dayMonth);
      sub = capitalize(weekday) + weekText(route.date);
      back = '#/plan';
    } else if (route.name === 'plan') {
      title = 'План';
      if (days.length) sub = `${formatShortDay(days[0].date)} – ${formatShortDay(days[days.length - 1].date)}`;
    } else if (route.name === 'progress') {
      title = 'Прогресс';
      const weeks = weeksOf(ctx.journal, ctx.start).filter((w) => typeof w.week === 'number');
      const current = weekOfDate(weeks, today);
      if (current != null && weeks.length) sub = `Неделя ${current} из ${weeks[weeks.length - 1].week}`;
    } else {
      title = 'Настройки';
    }
    const pill = pillInfo(state);
    return h('header', { class: 'top', key: 'top' },
      back ? h('a', { class: 'icon-btn', key: 'back', href: back, 'aria-label': 'К плану' }, icon('chevronLeft')) : null,
      h('div', { class: 'top__text', key: 'text' },
        h('h1', { class: 'top__title' }, title),
        sub ? h('p', { class: 'top__sub' }, sub) : null),
      h('button', {
        class: cx('pill', pill.tone), key: 'pill', type: 'button',
        'aria-label': `Синхронизация: ${pill.text}. Подробнее`, onClick: act.openSync,
      }, icon(pill.mark), h('span', null, pill.text)));
  }

  function tabs(ctx) {
    const active = ctx.route.name === 'day' ? 'plan' : ctx.route.name;
    return h('nav', { class: 'tabs', key: 'tabs', 'aria-label': 'Разделы' }, TABS.map((tab) => h('a', {
      class: 'tab', key: tab.name, href: tab.href, 'aria-current': tab.name === active ? 'page' : null,
      onClick: (event) => {
        event.preventDefault();
        act.go(tab.href, { replace: true });
      },
    }, icon(tab.icon), tab.label)));
  }

  function timerBar() {
    const over = restOver(ui.timer, now());
    return h('div', { class: cx('timer', over && 'timer--over', ui.timerFlash && 'timer--flash'), role: 'timer', 'aria-label': 'Отдых' },
      h('div', { class: 'timer__bar' }, h('div', { class: 'timer__fill' })),
      h('div', { class: 'timer__text' },
        h('span', { class: 'timer__label' }, over ? 'Отдых окончен' : 'Отдых'),
        h('span', { class: 'timer__clock' })),
      over ? null : h('button', { class: 'btn btn--small', key: 'more', type: 'button', onClick: () => act.extendRest(30) }, '+30 с'),
      h('button', { class: 'btn btn--small', key: 'stop', type: 'button', onClick: act.stopRest }, over ? 'Закрыть' : 'Стоп'));
  }

  function view(ctx) {
    const { route } = ctx;
    let content;
    if (route.name === 'day') content = dayScreen(ctx, route.date);
    else if (route.name === 'plan') content = planScreen(ctx);
    else if (route.name === 'progress') content = progressScreen(ctx);
    else if (route.name === 'settings') content = settingsScreen(ctx);
    else content = todayScreen(ctx);

    return [
      header(ctx),
      h('main', { class: 'screen', key: `screen:${route.name}:${route.date || ''}`, hook: { create: screenCreated } }, content),
      h('footer', { class: 'dock', key: 'dock' },
        h('div', { key: 'update-slot' },
          ctx.pwa.updateReady
            ? h('div', { class: 'update', role: 'status' },
              h('span', null, 'Вышла новая версия'),
              h('button', { class: 'btn btn--small', type: 'button', onClick: act.applyUpdate }, 'Обновить'))
            : null),
        h('div', { key: 'timer-slot' }, ui.timer ? timerBar() : null),
        tabs(ctx)),
      ui.toast ? h('div', { class: 'toast', key: 'toast', role: 'status' }, ui.toast.text) : null,
      sheetView(ctx),
    ];
  }

  function screenCreated(el) {
    if (ui.restorePlan && ui.planScroll != null) el.scrollTop = ui.planScroll;
    ui.restorePlan = false;
  }

  /* ---------------------------------------------------------------- */
  /* Таймер отдыха                                                     */
  /* ---------------------------------------------------------------- */

  function paintTimer() {
    if (!ui.timer) return;
    const clock = root.querySelector('.timer__clock');
    const fill = root.querySelector('.timer__fill');
    if (!clock || !fill) return;
    const t = now();
    const text = restOver(ui.timer, t) ? `+${formatClock(restOvertime(ui.timer, t))}` : formatClock(restLeft(ui.timer, t));
    if (clock.textContent !== text) clock.textContent = text;
    fill.style.width = `${(restProgress(ui.timer, t) * 100).toFixed(1)}%`;
  }

  function saveTimer() {
    if (ui.timer) storage.set('timer', ui.timer);
    else storage.remove('timer');
  }

  function runTicker() {
    if (ui.timer && ticker === null) ticker = setInterval(tick, 250);
    if (!ui.timer && ticker !== null) {
      clearInterval(ticker);
      ticker = null;
    }
  }

  function tick() {
    if (!ui.timer) {
      runTicker();
      return;
    }
    const t = now();
    if (restOver(ui.timer, t)) {
      if (!ui.timerEnded) {
        ui.timerEnded = true;
        signalRestEnd(t - ui.timer.endsAt < SIGNAL_WINDOW_MS);
        invalidate();
      } else if (restOvertime(ui.timer, t) > OVERTIME_HIDE_SEC) {
        act.stopRest();
        return;
      }
    }
    paintTimer();
  }

  function signalRestEnd(onTime) {
    const settings = store.get();
    if (onTime) {
      if (settings.sound) feedback.beep();
      if (settings.vibrate) feedback.vibrate();
    }
    ui.timerFlash = true;
    setTimeout(() => {
      ui.timerFlash = false;
      invalidate();
    }, 2200);
  }

  function beginRest(seconds) {
    ui.timer = startRest(now(), seconds);
    ui.timerEnded = false;
    ui.timerFlash = false;
    saveTimer();
    runTicker();
  }

  /* ---------------------------------------------------------------- */
  /* Помощники действий                                                */
  /* ---------------------------------------------------------------- */

  const findRow = (key) => sync.getState().journal.find((row) => rowKey(row) === key) || null;

  function toast(text) {
    toastSeq += 1;
    const id = toastSeq;
    ui.toast = { id, text };
    setTimeout(() => {
      if (ui.toast && ui.toast.id === id) {
        ui.toast = null;
        invalidate();
      }
    }, 3200);
    invalidate();
  }

  function openSheet(sheet) {
    sheetSeq += 1;
    ui.sheet = { ...sheet, id: sheetSeq };
    invalidate();
  }

  function closeSheet() {
    const dialog = root.querySelector('dialog.sheet');
    if (dialog && dialog.open) {
      dialog.close(); // событие close уберёт лист из состояния
    } else if (ui.sheet) {
      ui.sheet = null;
      invalidate();
    }
  }

  /** Куда перейти после записи подхода: к соседу по паре, к следующему подходу, к следующей паре. */
  function nextTarget(pairs, pair, key, index) {
    const partner = pair.find((r) => rowKey(r) !== key && index < strengthPlan(r.plan).sets && setsOf(r)[index] === null);
    if (partner) return rowKey(partner);
    const inPair = pair.find((r) => nextSetIndex(r) !== -1);
    if (inPair) return rowKey(inPair);
    for (const other of pairs) {
      const row = other.find((r) => !isDone(r));
      if (row) return rowKey(row);
    }
    return null;
  }

  function afterNewSet(key, index) {
    const journal = sync.getState().journal;
    const row = journal.find((r) => rowKey(r) === key);
    if (!row) return;
    const { pairs } = splitDay(journal.filter((r) => r.date === row.date));
    const pairIndex = pairs.findIndex((pair) => pair.some((r) => rowKey(r) === key));
    if (pairIndex < 0) return;
    const pair = pairs[pairIndex];
    ui.focus = { date: row.date, pair: pairIndex };
    if (isDone(row)) delete ui.open[key];
    const allDone = pairs.every((p) => p.every(isDone));
    if (store.get().autoTimer && isLive(row.date) && !allDone && roundComplete(pair, key, index)) {
      beginRest(store.get().restSec);
    }
    const target = nextTarget(pairs, pair, key, index);
    if (target && target !== key) ui.scrollTo = target;
  }

  function writeWalk(row, values, add) {
    const fields = {};
    if (add) {
      if (values.km != null && values.km > 0) fields.km = roundTo((row.km || 0) + values.km, 2);
      if (values.min != null && values.min > 0) fields.min = roundTo((row.min || 0) + values.min, 1);
    } else {
      if (values.km !== row.km) fields.km = values.km;
      if (values.min !== row.min) fields.min = values.min;
    }
    if (Object.keys(fields).length) sync.queue(row, fields);
  }

  /* ---------------------------------------------------------------- */
  /* Действия                                                          */
  /* ---------------------------------------------------------------- */

  const act = {
    go(hash, { replace = false } = {}) {
      if (window.location.hash === hash) {
        const screen = root.querySelector('.screen');
        if (screen) screen.scrollTop = 0;
        return;
      }
      if (replace) window.location.replace(hash);
      else window.location.hash = hash;
    },

    /* --- упражнения --- */

    toggleCard(row, pairIndex, open) {
      ui.open[rowKey(row)] = open;
      if (open) ui.focus = { date: row.date, pair: pairIndex };
      invalidate();
    },

    selectSet(row, index) {
      if (selectedSet(ui, row) === index) {
        act.openReps(row, index);
        return;
      }
      ui.setIndex[rowKey(row)] = index;
      invalidate();
    },

    addSet(row) {
      const key = rowKey(row);
      const slots = slotsOf(ui, row);
      if (slots >= MAX_SETS) return;
      ui.slots[key] = slots + 1;
      ui.setIndex[key] = slots;
      invalidate();
    },

    /** Записывает число повторов в подход; null стирает его. */
    recordSet(stale, index, reps) {
      feedback.prime();
      const key = rowKey(stale);
      const row = findRow(key);
      if (!row || isWalk(row)) return;
      const sets = setsOf(row);
      const was = sets[index];
      delete ui.setIndex[key];
      if (was !== reps) {
        sets[index] = reps;
        const fields = { sets };
        if (row.weight == null && reps !== null) {
          // первый подход закрепляет вес, подставленный с прошлого раза
          const last = lastTime(sync.getState().journal, row);
          if (last && last.weight != null) fields.weight = last.weight;
        }
        sync.queue(row, fields);
        if (was === null && reps !== null) afterNewSet(key, index);
      }
      invalidate();
    },

    stepWeight(stale, direction) {
      const row = findRow(rowKey(stale));
      if (!row) return;
      const last = row.weight == null ? lastTime(sync.getState().journal, row) : null;
      const base = row.weight != null ? row.weight : last && last.weight != null ? last.weight : 0;
      const next = Math.max(0, roundTo(base + direction * store.stepFor(row.exercise), 2));
      if (next !== row.weight) sync.queue(row, { weight: next });
    },

    setWeight(stale, weight) {
      const row = findRow(rowKey(stale));
      if (!row || row.weight === weight) return;
      sync.queue(row, { weight });
    },

    openWeight(stale) {
      const row = findRow(rowKey(stale));
      if (!row) return;
      const last = row.weight == null ? lastTime(sync.getState().journal, row) : null;
      const value = row.weight != null ? row.weight : last && last.weight != null ? last.weight : null;
      openSheet({
        type: 'keypad',
        title: row.exercise,
        sub: 'Вес, как он выставлен на тренажёре',
        fields: [makeField({ name: 'weight', label: 'Вес', unit: 'кг', value, max: 1000, digits: 2, whole: 4 })],
        active: 0,
        error: '',
        stepsFor: row.exercise,
        canClear: row.weight != null,
        onDone: (values) => act.setWeight(row, values.weight),
        onClear: () => act.setWeight(row, null),
      });
    },

    openReps(stale, index) {
      const row = findRow(rowKey(stale));
      if (!row) return;
      const value = setsOf(row)[index];
      openSheet({
        type: 'keypad',
        title: row.exercise,
        sub: `Повторы в подходе ${index + 1}`,
        fields: [makeField({ name: 'reps', label: `Подход ${index + 1}`, unit: 'повт.', value, integer: true, max: 500, whole: 3 })],
        active: 0,
        error: '',
        canClear: value !== null,
        onDone: (values) => act.recordSet(row, index, values.reps),
        onClear: () => act.recordSet(row, index, null),
      });
    },

    /** focus: 'km' | 'min' — поправить итог; 'add' — прибавить отрезок к уже записанному. */
    openWalk(stale, focus) {
      const row = findRow(rowKey(stale));
      if (!row) return;
      const add = focus === 'add';
      const done = summarize(row, formatNumber);
      openSheet({
        type: 'keypad',
        title: add ? 'Отрезок ходьбы' : row.exercise,
        sub: add ? (done ? `Прибавится к записанному: ${done}` : 'Километры и минуты этого отрезка') : 'Итог за тренировку',
        fields: [
          makeField({ name: 'km', label: 'Километры', unit: 'км', value: add ? null : row.km, max: 200, digits: 2, whole: 3 }),
          makeField({ name: 'min', label: 'Минуты', unit: 'мин', value: add ? null : row.min, max: 1440, digits: 1, whole: 4 }),
        ],
        active: focus === 'min' ? 1 : 0,
        error: '',
        canClear: !add && (row.km != null || row.min != null),
        onDone: (values) => {
          const fresh = findRow(rowKey(row));
          if (fresh) writeWalk(fresh, values, add);
        },
        onClear: () => {
          const fresh = findRow(rowKey(row));
          if (fresh) writeWalk(fresh, { km: null, min: null }, false);
        },
      });
    },

    openNote(stale) {
      const row = findRow(rowKey(stale));
      if (!row) return;
      const mark = `сделано ${formatNumericDay(ui.today)}`;
      openSheet({
        type: 'note',
        top: true,
        title: 'Заметка',
        sub: row.exercise,
        text: row.note,
        hadNote: Boolean(row.note),
        chips: row.date !== ui.today && !row.note.includes(mark) ? [mark] : [],
        key: rowKey(row),
      });
    },

    noteInput(text) {
      if (!ui.sheet || ui.sheet.type !== 'note') return;
      ui.sheet = { ...ui.sheet, text };
      invalidate();
    },

    noteAppend(text) {
      if (!ui.sheet || ui.sheet.type !== 'note') return;
      const current = ui.sheet.text.trim();
      ui.sheet = { ...ui.sheet, text: (current ? `${current}; ${text}` : text).slice(0, NOTE_LIMIT), chips: ui.sheet.chips.filter((c) => c !== text) };
      invalidate();
    },

    noteSave(text) {
      if (!ui.sheet || ui.sheet.type !== 'note') return;
      const row = findRow(ui.sheet.key);
      const note = String(text).trim().slice(0, NOTE_LIMIT);
      if (row && row.note !== note) sync.queue(row, { note });
      closeSheet();
    },

    /** «Делаю эту тренировку сегодня»: включает таймер для этого дня и ставит дату в заметку. */
    markLive(date) {
      feedback.prime();
      ui.live = { date, on: ui.today };
      storage.set('live', ui.live);
      const mark = `сделано ${formatNumericDay(ui.today)}`;
      const rows = sync.getState().journal.filter((r) => r.date === date);
      if (rows.length && !rows.some((r) => r.note.includes(mark))) {
        const first = rows[0];
        const note = first.note ? `${first.note}; ${mark}` : mark;
        if (note.length <= NOTE_LIMIT) sync.queue(first, { note });
      }
      invalidate();
    },

    dismissWeightNote() {
      store.set({ weightNoteSeen: true });
    },

    /* --- цифровая клавиатура --- */

    keypadKey(key) {
      const sheet = ui.sheet;
      if (!sheet || sheet.type !== 'keypad') return;
      const fields = sheet.fields.slice();
      fields[sheet.active] = pressKey(fields[sheet.active], key);
      ui.sheet = { ...sheet, fields, error: '' };
      invalidate();
    },

    keypadField(index) {
      const sheet = ui.sheet;
      if (!sheet || sheet.type !== 'keypad' || !sheet.fields[index]) return;
      ui.sheet = { ...sheet, active: index, error: '' };
      invalidate();
    },

    keypadNext() {
      const sheet = ui.sheet;
      if (!sheet || sheet.type !== 'keypad') return;
      const error = fieldError(sheet.fields[sheet.active]);
      if (error) {
        ui.sheet = { ...sheet, error };
        invalidate();
        return;
      }
      act.keypadField(Math.min(sheet.fields.length - 1, sheet.active + 1));
    },

    keypadDone() {
      const sheet = ui.sheet;
      if (!sheet || sheet.type !== 'keypad') return;
      const values = {};
      for (let i = 0; i < sheet.fields.length; i += 1) {
        const field = sheet.fields[i];
        const error = fieldError(field);
        if (error) {
          ui.sheet = { ...sheet, active: i, error };
          invalidate();
          return;
        }
        values[field.name] = fieldValue(field);
      }
      sheet.onDone(values);
      closeSheet();
    },

    keypadClear() {
      const sheet = ui.sheet;
      if (!sheet || sheet.type !== 'keypad') return;
      sheet.onClear();
      closeSheet();
    },

    setStep(exercise, step) {
      store.setStep(exercise, step);
    },

    /* --- листы --- */

    openSync() {
      openSheet({ type: 'sync', title: 'Синхронизация с таблицей' });
    },

    closeSheet,

    sheetClosed() {
      if (!ui.sheet) return;
      ui.sheet = null;
      invalidate();
    },

    confirmSheet() {
      const sheet = ui.sheet;
      if (!sheet || sheet.type !== 'confirm') return;
      sheet.onConfirm();
      closeSheet();
    },

    /* --- отдых --- */

    startRest(seconds) {
      feedback.prime();
      beginRest(seconds || store.get().restSec);
      invalidate();
    },

    extendRest(seconds) {
      if (!ui.timer) return;
      feedback.prime();
      ui.timer = extendRest(ui.timer, now(), seconds);
      ui.timerEnded = false;
      ui.timerFlash = false;
      saveTimer();
      invalidate();
    },

    stopRest() {
      ui.timer = null;
      ui.timerEnded = false;
      ui.timerFlash = false;
      saveTimer();
      runTicker();
      invalidate();
    },

    /* --- синхронизация и подключение --- */

    syncNow() {
      sync.sync();
    },

    retryFailed(index) {
      sync.retryFailed(index);
    },

    dropFailed(index) {
      sync.dropFailed(index);
    },

    formInput(name, value) {
      let form = { ...ui.form, [name]: value, error: '' };
      const found = extractConnection(value);
      // адрес и ключ вставили одним куском: раскладываем по полям
      if (found.url && found.key) form = { ...form, url: found.url, key: found.key };
      ui.form = form;
      invalidate();
    },

    editConnection() {
      ui.form = { url: '', key: '', error: '', busy: false, editing: true };
      invalidate();
    },

    cancelEdit() {
      ui.form = { url: '', key: '', error: '', busy: false, editing: false };
      invalidate();
    },

    async connect() {
      const form = ui.form;
      if (form.busy) return;
      const address = normalizeBridgeUrl(form.url, { allowLocal: env.local });
      const key = form.key.trim();
      let error = '';
      if (address.error) error = address.error;
      else if (!key) error = 'Вставьте ключ.';
      else if (/\s/.test(key) || key.length > 200) error = 'Ключ — одна строка без пробелов.';
      if (error) {
        ui.form = { ...form, error };
        invalidate();
        return;
      }
      ui.form = { ...form, busy: true, error: '' };
      invalidate();
      const result = await sync.connect({ url: address.url, key });
      if (result.ok) {
        ui.form = { url: '', key: '', error: '', busy: false, editing: false };
        if (navigator.storage && typeof navigator.storage.persist === 'function') navigator.storage.persist().catch(() => {});
        toast('Таблица подключена');
        act.go('#/today', { replace: true });
      } else {
        ui.form = { ...ui.form, busy: false, error: CONNECT_ERRORS[result.error.code] || result.error.message };
      }
      invalidate();
    },

    askReset() {
      const pending = sync.getState().pending;
      openSheet({
        type: 'confirm',
        title: 'Отключить таблицу?',
        text: `${pending ? `В очереди неотправленных записей: ${pending}. Они пропадут. ` : ''}Приложение забудет адрес, ключ и журнал на этом телефоне. В таблице ничего не изменится.`,
        confirmLabel: 'Отключить',
        danger: true,
        onConfirm: () => {
          sync.reset();
          storage.remove('live');
          ui.live = null;
          ui.focus = null;
          act.stopRest();
          toast('Таблица отключена');
        },
      });
    },

    /* --- настройки и приложение --- */

    setSetting(patch) {
      store.set(patch);
    },

    applyUpdate() {
      pwa.applyUpdate();
    },

    checkUpdate() {
      pwa.check({ force: true });
    },

    promptInstall() {
      pwa.promptInstall();
    },
  };

  /* ---------------------------------------------------------------- */
  /* События страницы                                                  */
  /* ---------------------------------------------------------------- */

  function onRoute() {
    const prev = ui.route;
    const next = parseRoute(window.location.hash);
    if (next.name === 'day' && next.date === ui.today) {
      window.location.replace('#/today');
      return;
    }
    const screen = root.querySelector('.screen');
    if (prev.name === 'plan' && screen) ui.planScroll = screen.scrollTop;
    ui.restorePlan = next.name === 'plan' && prev.name === 'day';
    ui.route = next;
    ui.open = {};
    ui.setIndex = {};
    ui.slots = {};
    if (next.name !== 'settings') ui.form = { url: '', key: '', error: '', busy: false, editing: false };
    if (ui.sheet) closeSheet();
    invalidate();
  }

  function refreshToday() {
    const today = todayISO(new Date(now()));
    if (today === ui.today) return;
    ui.today = today;
    if (ui.live && ui.live.on !== today) {
      ui.live = null;
      storage.remove('live');
    }
    invalidate();
  }

  /** Возврат в приложение: новый день, очередь, обновление, экран и таймер. */
  function wake() {
    refreshToday();
    sync.wake();
    feedback.onVisible();
    pwa.check();
    tick();
    invalidate();
  }

  return {
    invalidate,

    start() {
      window.addEventListener('hashchange', onRoute);
      window.addEventListener('resize', invalidate);
      window.addEventListener('online', () => {
        sync.wake();
        invalidate();
      });
      window.addEventListener('offline', invalidate);
      document.addEventListener('visibilitychange', () => {
        if (document.visibilityState === 'visible') wake();
      });
      window.addEventListener('pageshow', (event) => {
        if (event.persisted) wake();
      });
      window.matchMedia('(display-mode: standalone)').addEventListener('change', invalidate);
      setInterval(() => {
        if (document.visibilityState === 'visible') refreshToday();
      }, 30000);
      if (ui.route.name === 'day' && ui.route.date === ui.today) window.location.replace('#/today');
      runTicker();
      draw();
      sync.wake({ staleAfterMs: 0 });
    },
  };
}
