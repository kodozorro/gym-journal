// Общие кусочки экранов: строка дня, метка состояния, полоса выполнения.

import { h, cx } from './vdom.js';
import { icon } from './icons.js';
import { dayProgress, dayStatus, isWalk, summarize, workoutTitle, plannedKm } from '../core/journal.js';
import { formatNumber, plural } from '../core/numbers.js';
import { formatSheetDay } from '../core/dates.js';

export const fmt = (value, digits) => formatNumber(value, digits);

/** Полоса «сколько сделано». Доля — от 0 до 1. */
export function meter(share, label) {
  const value = Math.round(Math.min(1, Math.max(0, share)) * 100);
  return h(
    'div',
    { class: 'meter', role: 'progressbar', 'aria-valuemin': 0, 'aria-valuemax': 100, 'aria-valuenow': value, 'aria-label': label },
    h('div', { class: 'meter__fill', style: { width: `${value}%` } }),
  );
}

/** Что написать под названием дня: сделанное, а если записей нет — план. */
export function daySummary(rows) {
  const { done, touched, total } = dayProgress(rows);
  const strength = rows.filter((r) => !isWalk(r));
  const walks = rows.filter(isWalk);
  if (!strength.length) {
    if (touched) return walks.map((r) => summarize(r, fmt)).filter(Boolean).join('; ');
    return walks.map((r) => r.plan).filter(Boolean).join('; ');
  }
  if (touched && done < total) return `записано ${done} из ${total}`;
  if (touched) return walks.map((r) => summarize(r, fmt)).filter(Boolean).join('; ') || `записано ${done} из ${total}`;
  const parts = [`${strength.length} ${plural(strength.length, 'упражнение', 'упражнения', 'упражнений')}`];
  const km = walks.reduce((sum, r) => sum + (plannedKm(r) || 0), 0);
  if (km) parts.push(`${fmt(km)} км`);
  return parts.join(' · ');
}

/**
 * Метка состояния дня. Пропущенный день ничем не выделяется: пропуски — обычное дело,
 * запись можно сделать позже.
 */
export function statusChip(status) {
  if (status === 'done') return h('span', { class: 'status status--done status--icon' }, icon('check'), h('span', { class: 'sr-only' }, 'записано'));
  if (status === 'partial') return h('span', { class: 'status status--partial' }, 'частично');
  if (status === 'today') return h('span', { class: 'status status--today' }, 'сегодня');
  return h('span', { class: 'status status--none' }, icon('chevronRight'));
}

/** Строка дня в списках: дата, тренировка, состояние. Ведёт на экран дня. */
export function dayRow(ctx, day) {
  const isToday = day.date === ctx.today;
  const status = dayStatus(day.rows, day.date, ctx.today);
  return h(
    'a',
    { class: cx('day-row', isToday && 'day-row--today'), href: isToday ? '#/today' : `#/day/${day.date}` },
    h('span', { class: 'day-row__date' }, formatSheetDay(day.date)),
    h('span', { class: 'day-row__title' }, workoutTitle(day.rows), h('span', { class: 'day-row__sum' }, daySummary(day.rows))),
    statusChip(status),
  );
}

const ERROR_TITLES = {
  unauthorized: 'Ключ не подходит',
  no_key: 'В таблице не создан ключ',
  layout_changed: 'Лист «Журнал» изменился',
  no_journal: 'В таблице нет листа «Журнал»',
  no_spreadsheet: 'Скрипт не привязан к таблице',
  api_mismatch: 'Скрипт в таблице другой версии',
};

// Где сообщение скрипта слишком короткое, приложение говорит, что делать.
const ERROR_HELP = {
  unauthorized: 'В приложении записан другой ключ. Вставьте ключ заново: его показывает функция setup в редакторе скрипта.',
  no_journal: 'Проверьте, что скрипт стоит в той самой таблице и лист не переименован.',
};

/**
 * Ошибка, после которой нужен человек: заголовок и пояснение без повтора заголовка.
 * @param {{code: string, message: string}} error
 */
export function errorText(error) {
  const title = ERROR_TITLES[error.code] || 'Таблица не принимает записи';
  const full = ERROR_HELP[error.code] || error.message || '';
  const text = full.startsWith(title) ? full.slice(title.length).replace(/^[.:]\s*/, '') : full;
  return { title, text };
}

/** Плашка с сообщением. tone: '' | 'warn' | 'bad' */
export function banner(key, tone, ...children) {
  return h('div', { class: cx('banner', tone && `banner--${tone}`), key, role: tone === 'bad' ? 'alert' : 'status' }, children);
}
