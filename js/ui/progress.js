// Экран «Прогресс»: текущая неделя, лучший вес по упражнению и ходьба по неделям.
// Показатели те же, что на листе «Прогресс» таблицы.

import { h } from './vdom.js';
import { icon } from './icons.js';
import { chart } from './chart.js';
import { fmt, meter } from './parts.js';
import { weekOfDate } from './plan.js';
import { dayStatus, summarize } from '../core/journal.js';
import { exerciseHistory, exerciseList, weeklyBest, weeklyWalk, weeksOf } from '../core/stats.js';
import { formatRange, formatSheetDay } from '../core/dates.js';

export function progressScreen(ctx) {
  const { state, journal, start, today, settings, act } = ctx;
  if (!state.configured || !state.snapshot || !journal.length) {
    return [
      h('div', { class: 'empty', key: 'empty' },
        h('h2', null, 'Пока нечего показывать'),
        h('p', null, state.configured ? 'Графики появятся после первых записей.' : 'Графики появятся, когда вы подключите таблицу и запишете первую тренировку.'),
        state.configured ? null : h('a', { class: 'btn btn--soft', href: '#/settings' }, 'Открыть настройки')),
    ];
  }

  const weeks = weeksOf(journal, start).filter((w) => typeof w.week === 'number');
  const numbers = weeks.map((w) => w.week);
  const xMin = Math.min(1, ...numbers);
  const xMax = Math.max(12, ...numbers);
  const byWeek = new Map(weeks.map((w) => [w.week, w]));
  const weekTitle = (week) => {
    const item = byWeek.get(week);
    return item ? `неделя ${week} · ${formatRange(item.days[0].date, item.days[item.days.length - 1].date)}` : `неделя ${week}`;
  };

  const nowWeek = weekOfDate(weeks, today) ?? numbers[0] ?? 1;
  const walk = weeklyWalk(journal, start);
  const goal = state.snapshot.walkGoalKm;
  const walkNow = walk.find((w) => w.week === nowWeek);
  const kmNow = walkNow ? walkNow.km : 0;
  const daysNow = byWeek.get(nowWeek) ? byWeek.get(nowWeek).days : [];
  const doneNow = daysNow.filter((d) => dayStatus(d.rows, d.date, today) === 'done').length;

  const exercises = exerciseList(journal);
  const withData = exercises.find((name) => weeklyBest(journal, name, start).length);
  const chosen = exercises.includes(settings.chartExercise) ? settings.chartExercise : withData || exercises[0] || '';
  const best = chosen ? weeklyBest(journal, chosen, start) : [];
  const history = chosen ? exerciseHistory(journal, chosen) : [];
  const walkWeeks = walk.filter((w) => w.km > 0 || w.min > 0);

  return [
    h('div', { class: 'tiles', key: 'tiles' },
      h('section', { class: 'card tile' },
        h('p', { class: 'tile__label' }, 'Ходьба'),
        h('p', { class: 'tile__value' }, fmt(kmNow), h('small', null, goal ? ` из ${fmt(goal)} км` : ' км')),
        goal ? meter(kmNow / goal, 'Километры за неделю') : null),
      h('section', { class: 'card tile' },
        h('p', { class: 'tile__label' }, 'Тренировки'),
        h('p', { class: 'tile__value' }, doneNow, h('small', null, ` из ${daysNow.length}`)),
        meter(daysNow.length ? doneNow / daysNow.length : 0, 'Тренировки за неделю'))),

    exercises.length
      ? h('section', { class: 'card chart-card', key: 'weights' },
        h('div', null,
          h('h2', { class: 'chart-card__title' }, 'Лучший вес за неделю'),
          h('p', { class: 'chart-card__sub' }, 'Килограммы по неделям программы')),
        h('label', { class: 'select' },
          h('span', { class: 'sr-only' }, 'Упражнение'),
          h('select', { onChange: (event) => act.setSetting({ chartExercise: event.target.value }) },
            exercises.map((name) => h('option', { key: name, value: name, selected: name === chosen }, name))),
          icon('chevronDown')),
        chart({
          kind: 'line',
          id: `weight:${chosen}`,
          points: best.map((b) => ({ x: b.week, y: b.best, value: `${fmt(b.best)} кг`, title: weekTitle(b.week) })),
          xMin,
          xMax,
          label: best.length
            ? `Лучший вес по неделям, ${chosen}: ${best.map((b) => `неделя ${b.week}: ${fmt(b.best)} кг`).join(', ')}`
            : `Лучший вес по неделям, ${chosen}: записей нет`,
          empty: 'По этому упражнению ещё нет записей с весом.',
        }),
        best.length
          ? h('details', { class: 'table-toggle', key: 'table' },
            h('summary', null, 'Показать таблицей'),
            h('table', { class: 'table' },
              h('thead', null, h('tr', null, h('th', { scope: 'col' }, 'Неделя'), h('th', { scope: 'col' }, 'Лучший вес, кг'))),
              h('tbody', null, best.map((b) => h('tr', { key: b.week }, h('td', null, weekTitle(b.week)), h('td', null, fmt(b.best)))))))
          : null,
        history.length
          ? h('div', { key: 'history' },
            h('h3', { class: 'subhead' }, 'Записи'),
            h('ul', { class: 'history' }, history.map((row) => h('li', { key: `${row.date}|${row.occ || 0}` },
              h('span', { class: 'history__date' }, formatSheetDay(row.date)),
              h('span', null, summarize(row, fmt), row.note ? h('span', { class: 'history__note' }, row.note) : null)))))
          : null)
      : null,

    h('section', { class: 'card chart-card', key: 'walk' },
      h('div', null,
        h('h2', { class: 'chart-card__title' }, 'Ходьба по неделям'),
        h('p', { class: 'chart-card__sub' }, 'Километры за неделю')),
      chart({
        kind: 'bars',
        id: 'walk',
        points: walkWeeks.map((w) => ({
          x: w.week,
          y: w.km,
          value: `${fmt(w.km)} км`,
          title: w.min ? `${weekTitle(w.week)} · ${fmt(w.min, 0)} мин` : weekTitle(w.week),
        })),
        xMin,
        xMax,
        goal: goal ? { value: goal, label: `цель ${fmt(goal)} км` } : null,
        label: walkWeeks.length
          ? `Километры ходьбы по неделям: ${walkWeeks.map((w) => `неделя ${w.week}: ${fmt(w.km)} км`).join(', ')}${goal ? `. Цель ${fmt(goal)} км в неделю` : ''}`
          : 'Километры ходьбы по неделям: записей нет',
        empty: 'Записей о ходьбе пока нет.',
      }),
      walkWeeks.length
        ? h('details', { class: 'table-toggle', key: 'table' },
          h('summary', null, 'Показать таблицей'),
          h('table', { class: 'table' },
            h('thead', null, h('tr', null, h('th', { scope: 'col' }, 'Неделя'), h('th', { scope: 'col' }, 'Км'), h('th', { scope: 'col' }, 'Мин'))),
            h('tbody', null, walkWeeks.map((w) => h('tr', { key: w.week }, h('td', null, weekTitle(w.week)), h('td', null, fmt(w.km)), h('td', null, fmt(w.min, 0)))))))
        : null),
  ];
}
