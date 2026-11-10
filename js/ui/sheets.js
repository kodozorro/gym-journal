// Нижние листы: цифровая клавиатура, заметка, состояние синхронизации, справка об упражнении,
// подтверждение.
// Лист — это системный <dialog>: он сам запирает фокус внутри и закрывается по Esc.

import { h, cx } from './vdom.js';
import { icon } from './icons.js';
import { art } from './art.js';
import { fmt } from './parts.js';
import { failedList, formatMoment, syncText } from './settings.js';
import { STEP_CHOICES } from '../data/store.js';
import { guideFor } from '../core/guide.js';

const KEYS = ['1', '2', '3', '4', '5', '6', '7', '8', '9', ',', '0', 'back'];

export function sheetView(ctx) {
  const { ui, act } = ctx;
  const sheet = ui.sheet;
  if (!sheet) return null;
  let body;
  if (sheet.type === 'keypad') body = keypadBody(ctx, sheet);
  else if (sheet.type === 'note') body = noteBody(ctx, sheet);
  else if (sheet.type === 'sync') body = syncBody(ctx);
  else if (sheet.type === 'info') body = infoBody(ctx, sheet);
  else body = confirmBody(ctx, sheet);

  return h('dialog', {
    class: cx('sheet', sheet.top && 'sheet--top'),
    key: `sheet-${sheet.id}`,
    'aria-labelledby': 'sheet-title',
    hook: { create: openDialog },
    onClose: act.sheetClosed,
    onClick: (event) => {
      if (event.target === event.currentTarget) act.closeSheet();
    },
    onKeyDown: sheet.type === 'keypad' ? (event) => keypadKeyDown(event, act) : null,
  },
  h('div', { class: 'sheet__head' },
    h('h2', { class: 'sheet__title', id: 'sheet-title' }, sheet.title, sheet.sub ? h('small', null, sheet.sub) : null),
    h('button', { class: 'icon-btn', type: 'button', 'aria-label': 'Закрыть', onClick: act.closeSheet }, icon('close'))),
  h('div', { class: 'sheet__body' }, body));
}

function openDialog(el) {
  if (el.open) return;
  try {
    el.showModal();
  } catch {
    el.setAttribute('open', '');
  }
}

// Клавиатура компьютера работает наравне с экранной: удобно при проверке и с внешней клавиатурой.
function keypadKeyDown(event, act) {
  if (event.ctrlKey || event.metaKey || event.altKey) return;
  if (/^\d$/.test(event.key)) act.keypadKey(event.key);
  else if (event.key === ',' || event.key === '.') act.keypadKey(',');
  else if (event.key === 'Backspace') act.keypadKey('back');
  else return;
  event.preventDefault();
}

function keypadBody(ctx, sheet) {
  const { act, store } = ctx;
  const many = sheet.fields.length > 1;
  const active = sheet.fields[sheet.active];
  // «Далее», пока второе поле ещё не заполняли
  const next = many && sheet.active < sheet.fields.length - 1 && sheet.fields[sheet.active + 1].text === '';

  const display = sheet.fields.map((field, i) => {
    const blank = field.text === '';
    const inner = [
      h('span', { class: 'display__label' }, field.label),
      h('span', { class: cx('display__value', blank && 'display__value--blank', field.fresh && !blank && 'display__value--fresh') },
        h('span', null, blank ? '—' : field.text), field.unit ? h('small', null, ` ${field.unit}`) : null),
    ];
    if (!many) return h('div', { class: 'display__field display__field--solo', key: field.name, role: 'status' }, inner);
    return h('button', {
      class: 'display__field', key: field.name, type: 'button', 'aria-pressed': String(i === sheet.active), onClick: () => act.keypadField(i),
    }, inner);
  });

  const step = sheet.stepsFor ? store.stepFor(sheet.stepsFor) : null;

  return [
    h('div', { class: 'display', key: 'display' }, display),
    h('p', { class: 'display__error', key: 'error', role: 'alert' }, sheet.error || ''),
    h('div', { class: 'keypad', key: 'keys' }, KEYS.map((key) => h('button', {
      class: 'key', type: 'button', key,
      'aria-label': key === 'back' ? 'Стереть цифру' : key === ',' ? 'Запятая' : null,
      disabled: key === ',' && active.integer,
      onClick: () => act.keypadKey(key),
    }, key === 'back' ? icon('backspace') : key))),
    sheet.stepsFor
      ? h('div', { class: 'field', key: 'steps' },
        h('p', { class: 'sheet__cap' }, 'Шаг кнопок «+» и «−», кг'),
        h('div', { class: 'chips' }, STEP_CHOICES.map((value) => h('button', {
          class: 'chip', type: 'button', key: value, 'aria-pressed': String(value === step), onClick: () => act.setStep(sheet.stepsFor, value),
        }, fmt(value)))))
      : null,
    h('div', { class: 'sheet__actions', key: 'actions' },
      sheet.canClear ? h('button', { class: 'btn', type: 'button', key: 'clear', onClick: act.keypadClear }, 'Стереть') : null,
      h('button', { class: 'btn btn--primary', type: 'button', key: 'done', autofocus: true, onClick: next ? act.keypadNext : act.keypadDone },
        next ? 'Далее' : 'Готово')),
  ];
}

function noteBody(ctx, sheet) {
  const { act } = ctx;
  return [
    h('textarea', {
      class: 'input', key: 'text', rows: 3, maxlength: 500, value: sheet.text, autofocus: true,
      'aria-label': 'Заметка', placeholder: 'Например: сиденье на 4, было легко',
      onInput: (event) => act.noteInput(event.target.value),
    }),
    sheet.chips && sheet.chips.length
      ? h('div', { class: 'chips', key: 'chips' }, sheet.chips.map((text) => h('button', {
        class: 'chip', type: 'button', key: text, onClick: () => act.noteAppend(text),
      }, text)))
      : null,
    h('div', { class: 'sheet__actions', key: 'actions' },
      sheet.hadNote ? h('button', { class: 'btn', type: 'button', key: 'clear', onClick: () => act.noteSave('') }, 'Стереть') : null,
      h('button', { class: 'btn btn--primary', type: 'button', key: 'save', onClick: () => act.noteSave(sheet.text) }, 'Сохранить')),
  ];
}

function syncBody(ctx) {
  const { state, act, now } = ctx;
  return [
    h('p', { class: 'sheet__text', key: 'text', role: 'status' }, syncText(state, now)),
    state.configured
      ? h('dl', { class: 'kv', key: 'kv' },
        h('dt', null, 'Журнал прочитан'), h('dd', null, state.snapshot ? formatMoment(state.snapshot.fetchedAt, now) : 'ещё ни разу'),
        h('dt', null, 'В очереди'), h('dd', null, state.pending),
        state.failed.length ? [h('dt', null, 'Не принято таблицей'), h('dd', null, state.failed.length)] : null)
      : null,
    state.failed.length ? h('div', { key: 'failed' }, failedList(ctx)) : null,
    h('div', { class: 'sheet__actions', key: 'actions' },
      h('a', { class: 'btn', href: '#/settings', key: 'settings' }, 'Настройки'),
      state.configured
        ? h('button', { class: 'btn btn--primary', type: 'button', key: 'sync', disabled: state.phase === 'syncing', onClick: act.syncNow },
          state.phase === 'syncing' ? 'Обмен…' : 'Обновить')
        : null),
  ];
}

/** Кнопка «i»: как выглядит тренажёр и как на нём делать упражнение. Чего в справочнике нет, то не показывается. */
function infoBody(ctx, sheet) {
  const { act } = ctx;
  const guide = guideFor(sheet);
  const drawing = guide.art ? art(guide.art, `Рисунок упражнения: ${sheet.exercise}`) : null;
  return [
    guide.photo || guide.search
      ? h('section', { class: 'info', key: 'machine' },
        h('h3', { class: 'sheet__cap' }, 'Тренажёр'),
        guide.photo
          ? h('img', {
            class: 'info__photo', src: guide.photo.src, width: guide.photo.width, height: guide.photo.height,
            alt: `Фото тренажёра: ${guide.machine}`, decoding: 'async',
          })
          : h('p', { class: 'info__text' }, 'Фото этого тренажёра в приложении нет.'),
        guide.look ? h('p', { class: 'info__cap' }, guide.look) : null,
        guide.search
          ? h('a', { class: 'btn btn--soft', href: guide.search, target: '_blank', rel: 'noopener noreferrer' }, 'Найти фото в интернете', icon('link'))
          : null)
      : null,
    drawing
      ? h('section', { class: 'info', key: 'move' },
        h('h3', { class: 'sheet__cap' }, 'Упражнение'),
        h('div', { class: 'info__art' }, drawing),
        h('p', { class: 'info__cap' }, [guide.view, guide.legend].filter(Boolean).join(' ')))
      : null,
    guide.muscles
      ? h('section', { class: 'info', key: 'muscles' },
        h('h3', { class: 'sheet__cap' }, 'Что работает'),
        h('p', { class: 'info__text' }, guide.muscles))
      : null,
    guide.steps.length
      ? h('section', { class: 'info', key: 'steps' },
        h('h3', { class: 'sheet__cap' }, 'Как делать'),
        h('ol', { class: 'steps' }, guide.steps.map((step, i) => h('li', { key: i }, h('span', null, step)))))
      : null,
    guide.rule ? h('p', { class: 'banner', key: 'rule' }, guide.rule) : null,
    drawing || guide.steps.length
      ? null
      : h('p', { class: 'sheet__text', key: 'none' }, 'Рисунка и описания для этого упражнения в приложении пока нет.'),
    h('div', { class: 'sheet__actions', key: 'actions' },
      h('button', { class: 'btn btn--primary', type: 'button', key: 'ok', onClick: act.closeSheet }, 'Понятно')),
  ];
}

function confirmBody(ctx, sheet) {
  const { act } = ctx;
  return [
    h('p', { class: 'sheet__text', key: 'text' }, sheet.text),
    h('div', { class: 'sheet__actions', key: 'actions' },
      h('button', { class: 'btn', type: 'button', key: 'cancel', autofocus: true, onClick: act.closeSheet }, 'Отмена'),
      h('button', { class: cx('btn', sheet.danger ? 'btn--danger' : 'btn--primary'), type: 'button', key: 'ok', onClick: act.confirmSheet }, sheet.confirmLabel)),
  ];
}
