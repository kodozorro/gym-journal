// Экран «Настройки»: подключение таблицы, поведение тренировки, оформление, сброс.

import { h } from './vdom.js';
import { icon } from './icons.js';
import { errorText, fmt } from './parts.js';
import { SETUP_URL } from './day.js';
import { formatSheetDay } from '../core/dates.js';
import { formatClock } from '../core/timer.js';
import { REST_MAX, REST_MIN, REST_STEP, STEP_CHOICES } from '../data/store.js';
import { VERSION } from '../version.js';

const TIME = new Intl.DateTimeFormat('ru-RU', { hour: '2-digit', minute: '2-digit' });
const DAY_TIME = new Intl.DateTimeFormat('ru-RU', { day: 'numeric', month: 'long', hour: '2-digit', minute: '2-digit' });

/** «12:31» для сегодняшнего времени, «9 ноября, 12:31» для более раннего. */
export function formatMoment(ms, now) {
  if (!ms) return 'ещё ни разу';
  const date = new Date(ms);
  const sameDay = new Date(now).toDateString() === date.toDateString();
  return sameDay ? TIME.format(date) : DAY_TIME.format(date);
}

/** Одной фразой: что сейчас с записями. */
export function syncText(state, now) {
  if (!state.configured) return 'Таблица не подключена.';
  if (state.phase === 'syncing') return 'Идёт обмен с таблицей…';
  if (state.phase === 'error') {
    if (!state.error) return 'Таблица не принимает записи.';
    const { title, text } = errorText(state.error);
    return `${title}. ${text}`.trim();
  }
  if (state.pending) {
    if (!state.online) return 'Нет сети. Записи сохранены в телефоне и уйдут в таблицу, когда сеть появится.';
    if (state.phase === 'waiting') {
      const wait = state.retryAt ? Math.max(1, Math.ceil((state.retryAt - now) / 1000)) : 0;
      const reason = state.error ? state.error.message : 'Нет связи с таблицей.';
      return `${reason} Записи сохранены в телефоне. ${wait ? `Следующая попытка через ${wait} с.` : ''}`.trim();
    }
    return 'Записи отправляются в таблицу.';
  }
  if (state.phase === 'waiting') return state.error ? state.error.message : 'Нет связи с таблицей.';
  if (!state.online) return 'Нет сети. Показан журнал, сохранённый в телефоне.';
  if (state.failed.length) return `Таблица не приняла записей: ${state.failed.length}. Остальное сохранено.`;
  return 'Все записи в таблице.';
}

/** Что было в записи, которую таблица не приняла. */
export function describeFields(fields) {
  const parts = [];
  if ('weight' in fields) parts.push(fields.weight === null ? 'вес стёрт' : `${fmt(fields.weight)} кг`);
  if ('sets' in fields) {
    const sets = fields.sets.filter((v) => v !== null);
    parts.push(sets.length ? `подходы ${sets.join(', ')}` : 'подходы стёрты');
  }
  if ('km' in fields) parts.push(fields.km === null ? 'км стёрты' : `${fmt(fields.km)} км`);
  if ('min' in fields) parts.push(fields.min === null ? 'минуты стёрты' : `${fmt(fields.min)} мин`);
  if ('note' in fields) parts.push(fields.note ? `заметка «${fields.note}»` : 'заметка стёрта');
  return parts.join(' · ');
}

export function failedList(ctx) {
  const { state, act } = ctx;
  return h('ul', { class: 'failed' }, state.failed.map((item, index) => h('li', { key: `${item.date}|${item.exercise}|${item.occ}|${item.rev}` },
    h('span', null, h('b', null, `${formatSheetDay(item.date)} · ${item.exercise}`), `: ${describeFields(item.fields)}`),
    h('span', { class: 'failed__reason' },
      item.reason || (item.status === 'not_found' ? 'В журнале нет такой строки.' : 'Таблица отклонила запись.')),
    h('span', { class: 'failed__actions' },
      h('button', { class: 'btn btn--small', type: 'button', onClick: () => act.retryFailed(index) }, 'Повторить'),
      h('button', { class: 'btn btn--small btn--ghost', type: 'button', onClick: () => act.dropFailed(index) }, 'Убрать')))));
}

function toggle(label, hint, on, onChange) {
  return h('div', { class: 'row', key: label },
    h('div', { class: 'row__text' }, h('p', { class: 'row__label' }, label), hint ? h('p', { class: 'row__hint' }, hint) : null),
    h('button', { class: 'switch', type: 'button', role: 'switch', 'aria-checked': String(on), 'aria-label': label, onClick: () => onChange(!on) }));
}

function segmented(label, options, value, onChange) {
  return h('div', { class: 'seg', role: 'group', 'aria-label': label }, options.map(([id, text]) => h('button', {
    type: 'button', key: id, 'aria-pressed': String(id === value), onClick: () => onChange(id),
  }, text)));
}

function shortUrl(url) {
  const match = /\/s\/([^/]+)\/exec$/.exec(url);
  if (!match) return url.replace(/^https?:\/\//, '');
  const id = match[1];
  return id.length > 12 ? `…${id.slice(0, 5)}…${id.slice(-4)}/exec` : `…${id}/exec`;
}

function connection(ctx) {
  const { state, ui, act, env, now } = ctx;
  const form = ui.form;
  const installFirst = env.ios && !env.standalone
    ? h('p', { class: 'banner banner--warn', key: 'install-first' },
      h('span', null, h('b', null, 'Сначала поставьте приложение на экран «Домой». '), 'У значка своё хранилище, отдельное от Safari: таблицу нужно подключать уже в нём.'))
    : null;

  if (state.configured && !form.editing) {
    return h('section', { class: 'card section', key: 'conn' },
      h('h2', { class: 'section__title' }, 'Таблица'),
      h('p', { class: 'section__text', role: 'status' }, syncText(state, now)),
      h('dl', { class: 'kv' },
        h('dt', null, 'Скрипт'), h('dd', null, shortUrl(state.conn.url)),
        h('dt', null, 'Журнал прочитан'), h('dd', null, state.snapshot ? formatMoment(state.snapshot.fetchedAt, now) : 'ещё ни разу'),
        h('dt', null, 'В очереди'), h('dd', null, state.pending)),
      h('div', { class: 'sheet__actions' },
        h('button', { class: 'btn btn--soft', type: 'button', disabled: state.phase === 'syncing', onClick: act.syncNow }, icon('sync'), 'Обновить'),
        h('button', { class: 'btn', type: 'button', onClick: act.editConnection }, 'Изменить')));
  }

  return h('section', { class: 'card section', key: 'conn' },
    h('h2', { class: 'section__title' }, state.configured ? 'Новое подключение' : 'Подключение таблицы'),
    h('p', { class: 'section__text' }, 'Вставьте адрес веб-приложения и ключ из редактора скрипта. Можно вставить оба сразу в первое поле.'),
    installFirst,
    h('label', { class: 'field', key: 'url' },
      h('span', { class: 'field__label' }, 'Адрес веб-приложения'),
      h('textarea', {
        class: 'input input--mono', rows: 3, value: form.url, placeholder: 'https://script.google.com/\nmacros/s/…/exec',
        autocapitalize: 'off', autocomplete: 'off', autocorrect: 'off', spellcheck: 'false',
        onInput: (event) => act.formInput('url', event.target.value),
      })),
    h('label', { class: 'field', key: 'key' },
      h('span', { class: 'field__label' }, 'Ключ'),
      h('input', {
        class: 'input input--mono', type: 'text', value: form.key, placeholder: '40 знаков из журнала setup',
        autocapitalize: 'off', autocomplete: 'off', autocorrect: 'off', spellcheck: 'false',
        onInput: (event) => act.formInput('key', event.target.value),
      })),
    form.error ? h('p', { class: 'field__error', key: 'error', role: 'alert' }, form.error) : null,
    h('button', { class: 'btn btn--primary btn--block', key: 'submit', type: 'button', disabled: form.busy, onClick: act.connect },
      form.busy ? 'Проверяю…' : 'Подключить'),
    state.configured ? h('button', { class: 'btn btn--ghost btn--block', key: 'cancel', type: 'button', onClick: act.cancelEdit }, 'Отмена') : null,
    h('a', { class: 'btn btn--ghost btn--block', key: 'help', href: SETUP_URL, target: '_blank', rel: 'noopener' }, 'Как поставить скрипт', icon('link')));
}

function workout(ctx) {
  const { settings, act, env } = ctx;
  const set = (patch) => act.setSetting(patch);
  return h('section', { class: 'card section', key: 'workout' },
    h('h2', { class: 'section__title' }, 'Тренировка'),
    h('div', null,
      h('div', { class: 'row', key: 'rest' },
        h('div', { class: 'row__text' }, h('p', { class: 'row__label' }, 'Время отдыха'), h('p', { class: 'row__hint' }, 'Между кругами пары')),
        h('div', { class: 'stepper' },
          h('button', { type: 'button', 'aria-label': 'Меньше отдыха', disabled: settings.restSec <= REST_MIN, onClick: () => set({ restSec: settings.restSec - REST_STEP }) }, icon('minus')),
          h('output', { 'aria-live': 'polite' }, formatClock(settings.restSec)),
          h('button', { type: 'button', 'aria-label': 'Больше отдыха', disabled: settings.restSec >= REST_MAX, onClick: () => set({ restSec: settings.restSec + REST_STEP }) }, icon('plus')))),
      toggle('Автозапуск отдыха', 'Когда записан подход у обоих упражнений пары', settings.autoTimer, (on) => set({ autoTimer: on })),
      env.canSound
        ? toggle('Звук в конце отдыха', env.ios ? 'В беззвучном режиме телефона не слышен' : '', settings.sound, (on) => set({ sound: on }))
        : null,
      env.canVibrate ? toggle('Вибрация в конце отдыха', '', settings.vibrate, (on) => set({ vibrate: on })) : null,
      toggle('Подсказка о прибавке веса', 'Когда в прошлый раз все подходы дошли до верхней границы', settings.hints, (on) => set({ hints: on })),
      h('div', { class: 'row row--stack', key: 'awake' },
        h('div', { class: 'row__text' },
          h('p', { class: 'row__label' }, 'Не гасить экран'),
          h('p', { class: 'row__hint' }, env.canWakeLock
            ? 'Пока идёт отдых или всё время, пока открыта тренировка.'
            : 'Этот телефон не даёт приложению держать экран включённым.')),
        segmented('Не гасить экран', [['rest', 'В отдых'], ['workout', 'Всегда'], ['off', 'Нет']], settings.wakeLock, (id) => set({ wakeLock: id }))),
      h('div', { class: 'row row--stack', key: 'step' },
        h('div', { class: 'row__text' },
          h('p', { class: 'row__label' }, 'Шаг веса, кг'),
          h('p', { class: 'row__hint' }, 'Для кнопок «+» и «−». У каждого упражнения шаг можно поменять в окне ввода веса.')),
        h('div', { class: 'chips' }, STEP_CHOICES.map((step) => h('button', {
          class: 'chip', type: 'button', key: step, 'aria-pressed': String(step === settings.defaultStep), onClick: () => set({ defaultStep: step }),
        }, fmt(step)))))));
}

function look(ctx) {
  const { settings, act } = ctx;
  return h('section', { class: 'card section', key: 'look' },
    h('h2', { class: 'section__title' }, 'Оформление'),
    segmented('Тема', [['auto', 'Авто'], ['light', 'Светлая'], ['dark', 'Тёмная']], settings.theme, (id) => act.setSetting({ theme: id })));
}

function application(ctx) {
  const { act, env, pwa } = ctx;
  let offline = 'Этот браузер не умеет сохранять приложение: оно откроется только с сетью.';
  if (pwa.supported) offline = pwa.offlineReady ? 'Приложение сохранено в телефоне и открывается без сети.' : 'Приложение сохраняется в телефон…';
  if (pwa.error) offline = 'Сохранить приложение в телефон не удалось: без сети оно не откроется.';
  return h('section', { class: 'card section', key: 'app' },
    h('h2', { class: 'section__title' }, 'Приложение'),
    h('p', { class: 'section__text', role: 'status' }, offline),
    h('dl', { class: 'kv' }, h('dt', null, 'Версия'), h('dd', null, VERSION)),
    pwa.updateReady
      ? h('button', { class: 'btn btn--primary btn--block', key: 'update', type: 'button', onClick: act.applyUpdate }, 'Обновить приложение')
      : pwa.supported
        ? h('button', { class: 'btn btn--block', key: 'check', type: 'button', disabled: pwa.checking, onClick: act.checkUpdate }, pwa.checking ? 'Проверяю…' : 'Проверить обновление')
        : null,
    env.standalone
      ? null
      : env.ios
        ? h('p', { class: 'section__text', key: 'install' }, 'Чтобы поставить приложение на экран: откройте эту страницу в Safari, нажмите «Поделиться», затем «На экран „Домой“».')
        : pwa.canPrompt
          ? h('button', { class: 'btn btn--soft btn--block', key: 'install', type: 'button', onClick: act.promptInstall }, 'Установить на экран')
          : null,
    h('p', { class: 'section__text', key: 'weight' }, 'Вес записывается так, как он выставлен на тренажёре: число на плитке стека или сумма дисков.'));
}

function danger(ctx) {
  const { state, act } = ctx;
  if (!state.configured) return null;
  return h('section', { class: 'card section', key: 'reset' },
    h('h2', { class: 'section__title' }, 'Сброс'),
    h('p', { class: 'section__text' }, 'Приложение забудет адрес, ключ и сохранённый журнал на этом телефоне. Таблица не изменится.'),
    h('button', { class: 'btn btn--block', type: 'button', onClick: act.askReset }, 'Отключить таблицу'));
}

export function settingsScreen(ctx) {
  const { state } = ctx;
  return [
    connection(ctx),
    state.failed.length
      ? h('section', { class: 'card section', key: 'failed' },
        h('h2', { class: 'section__title' }, 'Не записано'),
        h('p', { class: 'section__text' }, 'Таблица не приняла эти записи. Исправьте причину и повторите или уберите запись.'),
        failedList(ctx))
      : null,
    workout(ctx),
    look(ctx),
    application(ctx),
    danger(ctx),
    h('p', { class: 'about', key: 'about' }, 'Журнал тренировок. Данные хранятся в вашей Google Таблице.'),
  ];
}
