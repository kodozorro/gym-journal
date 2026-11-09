// Экран тренировки: «Сегодня» и любой другой день журнала.
//
// Упражнения идут парами в порядке строк таблицы. Открыта пара, с которой сейчас работают;
// записанные упражнения сворачиваются сами. Повторы записываются одним касанием числа.

import { h, cx } from './vdom.js';
import { icon } from './icons.js';
import { banner, dayRow, errorText, fmt, meter } from './parts.js';
import {
  dayProgress, dayStatus, hasData, isDone, isWalk, lastTime, nextSetIndex, paceOf, progression, rowKey,
  setsOf, slotCount, splitDay, summarize, workoutTitle,
} from '../core/journal.js';
import { MAX_SETS, strengthPlan } from '../core/plan.js';
import { addDays, formatLongDay, formatNumericDay, formatSheetDay } from '../core/dates.js';
import { formatClock } from '../core/timer.js';
import { EXPECTED_SCRIPT } from '../data/api.js';

export const SETUP_URL = 'https://github.com/kodozorro/gym-journal/blob/main/docs/setup.md';

/** Сколько ячеек подходов показано: по плану и записям, плюс добавленная кнопкой «+». */
export function slotsOf(ui, row) {
  return Math.min(MAX_SETS, Math.max(slotCount(row), ui.slots[rowKey(row)] || 0));
}

/** Подход, в который попадёт следующее число: выбранный касанием или первый пустой. -1 — все записаны. */
export function selectedSet(ui, row) {
  const chosen = ui.setIndex[rowKey(row)];
  if (Number.isInteger(chosen) && chosen >= 0 && chosen < slotsOf(ui, row)) return chosen;
  return nextSetIndex(row);
}

/** Пара, с которой работают: та, где записывали последней, а если она готова — первая незаконченная. */
export function activePair(ui, date, pairs) {
  const focus = ui.focus && ui.focus.date === date ? ui.focus.pair : -1;
  if (focus >= 0 && focus < pairs.length && pairs[focus].some((r) => !isDone(r))) return focus;
  return pairs.findIndex((pair) => pair.some((r) => !isDone(r)));
}

/** Вес, который подставлен, но ещё не записан: с прошлого раза. */
export function draftWeight(journal, row) {
  if (row.weight != null) return null;
  const last = lastTime(journal, row);
  return last && last.weight != null ? last.weight : null;
}

/* ------------------------------------------------------------------ */
/* Экраны                                                              */
/* ------------------------------------------------------------------ */

export function todayScreen(ctx) {
  const { state, days, today } = ctx;
  if (!state.configured) return welcome();
  if (!state.snapshot) return firstLoad(ctx);
  const out = alerts(ctx);
  const day = days.find((d) => d.date === today);
  if (!days.length) {
    out.push(
      h('div', { class: 'empty', key: 'empty' },
        h('h2', null, 'Журнал пуст'),
        h('p', null, 'В листе «Журнал» нет строк с датой и упражнением.')),
    );
  } else if (day) {
    out.push(...dayBody(ctx, day));
  } else {
    out.push(freeDay(ctx));
  }
  out.push(catchUp(ctx));
  return out;
}

export function dayScreen(ctx, date) {
  const { state, days, today } = ctx;
  if (!state.configured) return welcome();
  if (!state.snapshot) return firstLoad(ctx);
  const day = days.find((d) => d.date === date);
  if (!day) {
    return [
      h('div', { class: 'empty', key: 'empty' },
        h('h2', null, 'В этот день тренировки нет'),
        h('p', null, `В журнале нет строк за ${formatLongDay(date)}.`),
        h('a', { class: 'btn btn--soft', href: '#/plan' }, 'Открыть план')),
    ];
  }
  const out = alerts(ctx);
  if (date !== today) out.push(otherDayBanner(ctx, day));
  out.push(...dayBody(ctx, day));
  return out;
}

function welcome() {
  return [
    h('div', { class: 'empty', key: 'welcome' },
      h('h2', null, 'Подключите таблицу'),
      h('p', null, 'Приложение записывает тренировки в вашу Google Таблицу и берёт из неё план. Данные хранятся только там.'),
      h('ol', { class: 'steps' },
        h('li', null, h('span', null, 'Поставьте в таблицу скрипт по инструкции. Это делается один раз, с компьютера.')),
        h('li', null, h('span', null, 'Скопируйте адрес веб-приложения и ключ.')),
        h('li', null, h('span', null, 'Вставьте их в настройках этого приложения.'))),
      h('a', { class: 'btn btn--primary btn--block', href: '#/settings' }, 'Открыть настройки'),
      h('a', { class: 'btn btn--ghost', href: SETUP_URL, target: '_blank', rel: 'noopener' }, 'Инструкция', icon('link'))),
  ];
}

function firstLoad(ctx) {
  const { state, act } = ctx;
  if (state.phase === 'syncing') {
    return [h('div', { class: 'empty', key: 'loading', role: 'status' }, h('p', null, 'Читаю журнал из таблицы…'))];
  }
  return [
    h('div', { class: 'empty', key: 'load-failed' },
      h('h2', null, 'Журнал ещё не загружен'),
      h('p', null, state.error ? state.error.message : 'Нужна связь с таблицей, чтобы прочитать план.'),
      h('button', { class: 'btn btn--primary', type: 'button', onClick: act.syncNow }, 'Повторить')),
  ];
}

/** Плашки о том, что требует внимания: запись не сохраняется, таблица не принимает данные. */
export function alerts(ctx) {
  const { state, act } = ctx;
  const out = [];
  if (!state.outboxSaved || !ctx.env.persistent) {
    out.push(
      banner('alert-storage', 'bad',
        h('span', null, h('b', null, 'Телефон не даёт сохранять данные. '), 'Записи держатся только пока приложение открыто. Не закрывайте его, пока они не уйдут в таблицу.')),
    );
  }
  if (state.phase === 'error' && state.error) {
    const { title, text } = errorText(state.error);
    out.push(
      banner('alert-error', 'bad',
        h('span', null, h('b', null, `${title}. `), text),
        h('a', { class: 'btn btn--small', href: '#/settings' }, 'Открыть настройки')),
    );
  } else if (state.phase === 'waiting' && state.error && state.error.code === 'not_json') {
    out.push(banner('alert-page', 'warn', h('span', null, state.error.message)));
  }
  if (state.failed.length) {
    out.push(
      banner('alert-failed', 'bad',
        h('span', null, h('b', null, `Не записано: ${state.failed.length}. `), 'Таблица не приняла эти записи.'),
        h('button', { class: 'btn btn--small', type: 'button', onClick: act.openSync }, 'Посмотреть')),
    );
  }
  if (state.snapshot && typeof state.snapshot.script === 'number' && state.snapshot.script < EXPECTED_SCRIPT) {
    out.push(
      banner('alert-script', 'warn',
        h('span', null, h('b', null, 'Скрипт в таблице устарел. '), 'Обновите его код по инструкции и выпустите новую версию развёртывания.'),
        h('a', { class: 'btn btn--small', href: SETUP_URL, target: '_blank', rel: 'noopener' }, 'Инструкция')),
    );
  }
  return out;
}

function otherDayBanner(ctx, day) {
  const { today, act } = ctx;
  const live = ctx.isLive(day.date);
  const mark = `сделано ${formatNumericDay(today)}`;
  if (live) {
    return banner('other-day', '',
      h('span', null, h('b', null, `Тренировка за ${formatSheetDay(day.date)} идёт сегодня. `),
        day.rows.some((r) => r.note.includes(mark)) ? `В заметке отмечено: ${mark}.` : ''));
  }
  const past = day.date < today;
  return banner('other-day', '',
    h('span', null,
      h('b', null, past ? `Запись за ${formatSheetDay(day.date)}. ` : `План на ${formatSheetDay(day.date)}. `),
      `Сегодня ${formatSheetDay(today)}. Если делаете эту тренировку сейчас, отметьте это: включится таймер отдыха, а в заметке появится дата.`),
    h('button', { class: 'btn btn--small', type: 'button', onClick: () => act.markLive(day.date) }, 'Делаю сегодня'));
}

function freeDay(ctx) {
  const { days, today } = ctx;
  const next = days.find((d) => d.date > today);
  const first = days[0];
  const last = days[days.length - 1];
  let title = 'Сегодня тренировки нет';
  let text = 'По плану день отдыха.';
  if (today < first.date) {
    title = 'Программа ещё не началась';
    text = `Первая тренировка: ${formatLongDay(first.date)}.`;
  } else if (today > last.date) {
    title = 'Программа закончилась';
    text = `Последняя тренировка была ${formatLongDay(last.date)}. Чтобы продолжить, добавьте недели в таблицу.`;
  }
  return h('section', { class: 'linklist', key: 'free' },
    h('div', { class: 'empty' }, h('h2', null, title), h('p', null, text)),
    next ? [h('h3', { class: 'linklist__title' }, 'Следующая тренировка'), h('ul', { class: 'days' }, h('li', null, dayRow(ctx, next)))] : null);
}

/** Прошлые дни без записи за две недели: их можно дозаписать. */
function catchUp(ctx) {
  const { days, today } = ctx;
  const from = addDays(today, -14);
  const list = days
    .filter((d) => d.date < today && d.date >= from)
    .filter((d) => {
      const status = dayStatus(d.rows, d.date, today);
      return status === 'missed' || status === 'partial';
    })
    .reverse()
    .slice(0, 6);
  if (!list.length) return null;
  return h('section', { class: 'linklist', key: 'catch-up' },
    h('h3', { class: 'linklist__title' }, 'Не записано раньше'),
    h('ul', { class: 'days' }, list.map((d) => h('li', { key: d.date }, dayRow(ctx, d)))));
}

/* ------------------------------------------------------------------ */
/* День                                                                */
/* ------------------------------------------------------------------ */

function dayBody(ctx, day) {
  const { ui, settings, act } = ctx;
  const rows = day.rows;
  const { pairs, walks } = splitDay(rows);
  const progress = dayProgress(rows);
  const active = activePair(ui, day.date, pairs);
  const out = [];

  out.push(
    h('section', { class: 'day-head', key: 'head' },
      h('div', { class: 'day-head__row' },
        h('h2', { class: 'day-head__title' }, pairs.length ? workoutTitle(rows) : 'Ходьба'),
        h('span', { class: 'day-head__count' }, `${progress.done} из ${progress.total}`)),
      meter(progress.total ? progress.done / progress.total : 0, 'Записано упражнений')),
  );

  if (pairs.length && !settings.weightNoteSeen) {
    out.push(
      banner('weight-note', '',
        h('span', null, h('b', null, 'Как записывать вес. '), 'Так, как он выставлен на тренажёре: число на плитке стека или сумма дисков. Тогда график покажет настоящий прогресс.'),
        h('button', { class: 'btn btn--small', type: 'button', onClick: act.dismissWeightNote }, 'Понятно')),
    );
  }

  // Силовой день начинается с ходьбы, а её строка в таблице последняя: кнопка сверху, пока ничего не записано.
  const untouched = rows.every((r) => !hasData(r));
  if (pairs.length && walks.length && untouched) {
    out.push(
      h('button', { class: 'btn btn--soft btn--block', key: 'warmup', type: 'button', onClick: () => act.openWalk(walks[0], 'add') },
        icon('plus'), 'Записать ходьбу до силовой'),
    );
  }

  pairs.forEach((pair, index) => {
    out.push(
      h('section', { class: 'group', key: `pair-${index}` },
        h('div', { class: 'group__head' },
          h('h3', { class: 'group__title' }, pairs.length > 1 ? `Пара ${index + 1}` : 'Упражнения'),
          index === active
            ? h('button', { class: 'rest-btn', type: 'button', onClick: () => act.startRest() }, icon('timer'), `Отдых ${formatClock(settings.restSec)}`)
            : null),
        pair.map((row) => exerciseCard(ctx, row, index, index === active))),
    );
  });

  if (walks.length) {
    out.push(
      h('section', { class: 'group', key: 'walks' },
        pairs.length ? h('div', { class: 'group__head' }, h('h3', { class: 'group__title' }, 'Ходьба')) : null,
        walks.map((row) => walkCard(ctx, row))),
    );
  }
  return out;
}

function lastLine(last) {
  if (!last) return h('p', { class: 'ex__last', key: 'last' }, 'Раньше не записывалось');
  return h('p', { class: 'ex__last', key: 'last' }, 'Прошлый раз: ', h('b', null, summarize(last, fmt)), `, ${formatSheetDay(last.date)}`);
}

function footer(ctx, row) {
  return h('div', { class: 'ex__foot', key: 'foot' },
    h('button', { class: cx('note-btn', row.note && 'note-btn--has'), type: 'button', onClick: () => ctx.act.openNote(row) },
      icon('note'), h('span', null, row.note || 'Заметка')),
    row.pending ? h('span', { class: 'unsent' }, 'не отправлено') : null);
}

function exerciseCard(ctx, row, pairIndex, inActivePair) {
  const { journal, settings, store, ui, act } = ctx;
  const key = rowKey(row);
  const plan = strengthPlan(row.plan);
  const done = isDone(row);
  const manual = ui.open[key];
  const open = manual !== undefined ? manual : inActivePair && !done;
  const last = lastTime(journal, row);

  const meta = [row.machine, plan.unknown ? row.plan : plan.tail].filter(Boolean).join(' · ');
  const closedText = hasData(row)
    ? summarize(row, fmt)
    : [plan.unknown ? row.plan : `${plan.sets} × ${rangeText(plan)}`, last && last.weight != null ? `прошлый раз ${fmt(last.weight)} кг` : '']
      .filter(Boolean).join(' · ');

  const head = h('button',
    { class: 'ex__head', key: 'head', type: 'button', 'aria-expanded': String(open), onClick: () => act.toggleCard(row, pairIndex, !open) },
    h('span', { class: 'ex__names' },
      h('span', { class: 'ex__title' }, row.exercise),
      open ? (meta ? h('span', { class: 'ex__meta' }, meta) : null) : h('span', { class: 'ex__summary' }, closedText)),
    done ? h('span', { class: 'ex__check' }, icon('check'), h('span', { class: 'sr-only' }, 'записано')) : null,
    open && !plan.unknown ? h('span', { class: 'plan-chip' }, `${plan.sets} × ${rangeText(plan)}`) : null,
    h('span', { class: 'ex__chev' }, icon(open ? 'chevronUp' : 'chevronDown')));

  if (!open) {
    return h('article', { class: 'card ex ex--closed', key, 'data-key': key, 'aria-label': row.exercise }, head);
  }

  const sets = setsOf(row);
  const slots = slotsOf(ui, row);
  const selected = selectedSet(ui, row);
  const step = store.stepFor(row.exercise);
  const draft = row.weight == null && last && last.weight != null ? last.weight : null;
  const shown = row.weight != null ? row.weight : draft;
  const hint = settings.hints && row.weight == null ? progression(last, step) : null;
  const canAdd = slots < MAX_SETS;

  return h('article', { class: 'card ex', key, 'data-key': key, 'aria-label': row.exercise },
    head,
    lastLine(last),
    hint
      ? h('div', { class: 'hint', key: 'hint' },
        h('span', null, `В прошлый раз все подходы дошли до ${hint.reps}. По правилу программы пора прибавить.`),
        h('button', { class: 'btn btn--small', type: 'button', onClick: () => act.setWeight(row, hint.weight) }, `Взять ${fmt(hint.weight)} кг`))
      : null,
    h('div', { class: 'weight', key: 'weight' },
      h('button', {
        class: 'step', type: 'button', 'aria-label': `Убавить вес на ${fmt(step)} кг`,
        disabled: shown == null || shown <= 0, onClick: () => act.stepWeight(row, -1),
      }, icon('minus')),
      h('button', {
        class: cx('weight__value', row.weight == null && 'weight__value--draft'), type: 'button',
        'aria-label': shown != null ? `Вес ${fmt(shown)} кг. Изменить` : 'Указать вес',
        onClick: () => act.openWeight(row),
      },
      h('span', { class: 'weight__num' }, shown != null ? fmt(shown) : '—', ' ', h('small', null, 'кг')),
      h('span', { class: 'weight__cap' }, row.weight != null ? `шаг ${fmt(step)} кг` : draft != null ? 'как в прошлый раз' : 'укажите вес')),
      h('button', { class: 'step', type: 'button', 'aria-label': `Прибавить вес на ${fmt(step)} кг`, onClick: () => act.stepWeight(row, 1) }, icon('plus'))),
    h('div', { class: 'sets', key: 'sets', style: canAdd ? { 'grid-auto-flow': 'row', 'grid-template-columns': `repeat(${slots}, 1fr) 52px` } : null },
      Array.from({ length: slots }, (_, i) => h('button', {
        class: cx('set', sets[i] === null && 'set--empty'), type: 'button', key: `set-${i}`,
        'aria-pressed': String(i === selected),
        'aria-label': `Подход ${i + 1}: ${sets[i] === null ? 'не записан' : sets[i]}`,
        onClick: () => act.selectSet(row, i),
      },
      h('span', { class: 'set__label' }, `Подход ${i + 1}`),
      h('span', { class: 'set__value' }, sets[i] === null ? '—' : sets[i]))),
      canAdd
        ? h('button', { class: 'set set--empty', type: 'button', key: 'add', 'aria-label': 'Добавить подход', onClick: () => act.addSet(row) },
          h('span', { class: 'set__label' }, 'ещё'), icon('plus'))
        : null),
    selected >= 0 ? repsStrip(ctx, row, plan, selected, sets, last) : null,
    footer(ctx, row));
}

function rangeText(plan) {
  return plan.low === plan.high ? String(plan.low) : `${plan.low}–${plan.high}`;
}

function repsStrip(ctx, row, plan, selected, sets, last) {
  const { act } = ctx;
  const current = sets[selected];
  const lastReps = last ? setsOf(last)[selected] : null;
  const low = plan.unknown ? 1 : Math.max(1, plan.low - 5);
  const high = plan.unknown ? 30 : plan.high + 5;
  // посередине ленты — записанное число, иначе прошлое, если оно в диапазоне плана, иначе верх диапазона
  const inPlan = (n) => plan.unknown || (n >= plan.low && n <= plan.high);
  const anchor = current ?? (lastReps != null && inPlan(lastReps) ? lastReps : plan.unknown ? 10 : plan.high);
  const values = [];
  for (let n = low; n <= high; n += 1) values.push(n);
  return [
    h('p', { class: 'reps__cap', key: 'reps-cap' }, `Повторы в подходе ${selected + 1}`),
    h('div', {
      class: 'reps', key: 'reps', role: 'group', 'aria-label': `Повторы в подходе ${selected + 1}`,
      'data-anchor': `${selected}:${anchor}`, hook: { create: centerStrip, update: centerStrip },
    },
    values.map((n) => h('button', {
      class: cx('rep', !plan.unknown && n >= plan.low && n <= plan.high && 'rep--plan', n === lastReps && 'rep--last'),
      key: n, type: 'button', 'data-value': n, 'aria-pressed': String(n === current),
      'aria-label': n === lastReps ? `${n}, как в прошлый раз` : null,
      onClick: () => act.recordSet(row, selected, n),
    }, n)),
    h('button', { class: 'rep rep--text', key: 'other', type: 'button', onClick: () => act.openReps(row, selected) }, 'Другое')),
  ];
}

// Лента повторов прокручивается так, чтобы нужное число оказалось посередине.
// Повторно — только когда сменился подход или значение: руками сдвинутую ленту не дёргаем.
function centerStrip(el) {
  const anchor = el.getAttribute('data-anchor');
  if (el.__anchor === anchor) return;
  el.__anchor = anchor;
  const value = anchor.split(':')[1];
  let target = null;
  for (const child of el.children) {
    if (child.getAttribute('data-value') === value) target = child;
  }
  if (!target) target = el.querySelector('.rep--plan');
  if (!target) return;
  const box = el.getBoundingClientRect();
  const item = target.getBoundingClientRect();
  el.scrollLeft += item.left - box.left - (box.width - item.width) / 2;
}

function walkCard(ctx, row) {
  const { journal, act } = ctx;
  const key = rowKey(row);
  const last = lastTime(journal, row);
  const pace = paceOf(row.km, row.min);
  const tile = (label, value, focus) => h('button', {
    class: cx('tile-btn', value == null && 'tile-btn--empty'), type: 'button',
    'aria-label': `${label}: ${value == null ? 'не записано' : fmt(value)}. Изменить`,
    onClick: () => act.openWalk(row, focus),
  },
  h('span', { class: 'tile-btn__label' }, label),
  h('span', { class: 'tile-btn__value' }, value == null ? '—' : fmt(value)));

  return h('article', { class: 'card ex', key, 'data-key': key, 'aria-label': row.exercise },
    h('div', { class: 'ex__head', key: 'head' },
      h('div', { class: 'ex__names' },
        h('h4', { class: 'ex__title' }, row.exercise),
        h('p', { class: 'ex__meta' }, [row.machine, row.plan].filter(Boolean).join(' · '))),
      isDone(row) ? h('span', { class: 'ex__check' }, icon('check'), h('span', { class: 'sr-only' }, 'записано')) : null),
    lastLine(last),
    h('div', { class: 'walk__tiles', key: 'tiles' }, tile('Километры', row.km, 'km'), tile('Минуты', row.min, 'min')),
    pace ? h('p', { class: 'walk__pace', key: 'pace' }, `Темп ${pace.pace} мин/км · ${fmt(pace.speed, 1)} км/ч`) : null,
    h('button', { class: 'btn btn--soft btn--block', key: 'add', type: 'button', onClick: () => act.openWalk(row, 'add') }, icon('plus'), 'Добавить отрезок'),
    footer(ctx, row));
}
