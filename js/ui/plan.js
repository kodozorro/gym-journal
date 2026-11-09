// Экран «План»: все недели программы и дни в них. Отсюда открывается любой день.

import { h } from './vdom.js';
import { dayRow, fmt } from './parts.js';
import { weeklyWalk, weeksOf } from '../core/stats.js';
import { formatRange } from '../core/dates.js';
import { alerts } from './day.js';

/** Номер недели программы, на которую приходится дата, или null. */
export function weekOfDate(weeks, date) {
  let found = null;
  for (const week of weeks) {
    if (week.days.length && week.days[0].date <= date) found = week.week;
  }
  return found;
}

export function planScreen(ctx) {
  const { state, journal, start, today } = ctx;
  if (!state.configured || !state.snapshot) {
    return [
      h('div', { class: 'empty', key: 'empty' },
        h('h2', null, 'Плана пока нет'),
        h('p', null, state.configured ? 'Журнал ещё не загружен из таблицы.' : 'План появится, когда вы подключите таблицу.'),
        h('a', { class: 'btn btn--soft', href: state.configured ? '#/today' : '#/settings' }, state.configured ? 'На главный экран' : 'Открыть настройки')),
    ];
  }
  const weeks = weeksOf(journal, start);
  if (!weeks.length) {
    return [h('div', { class: 'empty', key: 'empty' }, h('h2', null, 'Журнал пуст'), h('p', null, 'В листе «Журнал» нет строк с датой и упражнением.'))];
  }
  const current = weekOfDate(weeks, today);
  const walked = new Map(weeklyWalk(journal, start).map((w) => [w.week, w.km]));
  const goal = state.snapshot.walkGoalKm;

  const out = alerts(ctx);
  for (const week of weeks) {
    const first = week.days[0].date;
    const last = week.days[week.days.length - 1].date;
    const isCurrent = week.week === current;
    const km = walked.get(week.week);
    let kmText = '';
    if (km != null || (first <= today && goal)) {
      kmText = goal ? `${fmt(km || 0)} из ${fmt(goal)} км` : `${fmt(km || 0)} км`;
    }
    out.push(
      h('section', {
        class: 'week', key: `week-${week.week}`,
        'aria-current': isCurrent ? 'true' : null,
        hook: isCurrent ? { create: (el) => el.scrollIntoView({ block: 'start' }) } : null,
      },
      h('div', { class: 'week__head' },
        h('h2', { class: 'week__title' }, week.week == null ? 'Без номера недели' : `Неделя ${week.week}`, h('small', null, formatRange(first, last))),
        kmText ? h('span', { class: 'week__km' }, kmText) : null),
      h('ul', { class: 'days' }, week.days.map((day) => h('li', { key: day.date }, dayRow(ctx, day))))),
    );
  }
  return out;
}
