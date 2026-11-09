// Графики: линия «лучший вес по неделям» и столбцы «километры по неделям».
//
// Один ряд — один цвет, поэтому легенды нет: что нарисовано, сказано в заголовке карточки.
// Подписано только последнее значение, остальные показывает подсказка по касанию или наведению,
// а полные данные — таблица под графиком.

import { h, render } from './vdom.js';
import { linear, niceScale } from '../core/scale.js';
import { fmt } from './parts.js';

const HEIGHT = 210;
const PAD = { top: 24, right: 12, bottom: 26, left: 38 };
const MIN_WIDTH = 240;

/**
 * @param {object} spec
 * @param {'line'|'bars'} spec.kind
 * @param {string} spec.id меняется вместе с набором данных: выделение точки сбрасывается
 * @param {{x:number, y:number, value:string, title:string}[]} spec.points x — номер недели
 * @param {number} spec.xMin
 * @param {number} spec.xMax
 * @param {{value:number, label:string}|null} [spec.goal] линия цели (для столбцов)
 * @param {string} spec.label описание для экранного диктора
 * @param {string} spec.empty текст, когда данных нет
 */
export function chart(spec) {
  return h('div', { class: 'chart', hook: { create: (el) => sync(el, spec), update: (el) => sync(el, spec) } });
}

function sync(el, spec) {
  let model = el.__chart;
  if (!model) {
    model = { spec, hover: -1, width: MIN_WIDTH };
    el.__chart = model;
  }
  if (model.spec.id !== spec.id) model.hover = -1;
  model.spec = spec;
  model.width = Math.max(MIN_WIDTH, Math.round(el.clientWidth) || MIN_WIDTH);
  draw(el);
}

function draw(el) {
  render(el, view(el, el.__chart));
}

function setHover(el, index) {
  const model = el.__chart;
  if (model.hover === index) return;
  model.hover = index;
  draw(el);
}

function view(el, model) {
  const { spec, width: W, hover } = model;
  const points = spec.points;
  if (!points.length) return h('p', { class: 'chart__empty' }, spec.empty);

  const H = HEIGHT;
  const bars = spec.kind === 'bars';
  const count = Math.max(1, spec.xMax - spec.xMin + 1);
  const band = (W - PAD.left - PAD.right) / count;
  const xOf = (week) => PAD.left + band * (week - spec.xMin + 0.5);

  const values = points.map((p) => p.y);
  const top = Math.max(...values, spec.goal ? spec.goal.value : -Infinity);
  const scale = bars ? niceScale(0, top, { fromZero: true }) : niceScale(Math.min(...values), top);
  const yOf = linear(scale.lo, scale.hi, H - PAD.bottom, PAD.top);
  const base = H - PAD.bottom;

  const nearest = (event) => {
    const rect = event.currentTarget.getBoundingClientRect();
    const px = ((event.clientX - rect.left) / rect.width) * W;
    let best = 0;
    points.forEach((p, i) => {
      if (Math.abs(xOf(p.x) - px) < Math.abs(xOf(points[best].x) - px)) best = i;
    });
    return best;
  };

  const onKey = (event) => {
    const last = points.length - 1;
    let next = null;
    if (event.key === 'ArrowRight') next = hover < 0 ? 0 : Math.min(last, hover + 1);
    else if (event.key === 'ArrowLeft') next = hover < 0 ? last : Math.max(0, hover - 1);
    else if (event.key === 'Home') next = 0;
    else if (event.key === 'End') next = last;
    else if (event.key === 'Escape') next = -1;
    if (next === null) return;
    event.preventDefault();
    setHover(el, next);
  };

  const every = band >= 22 ? 1 : band >= 11 ? 2 : 4;
  const xTicks = [];
  for (let week = spec.xMin; week <= spec.xMax; week += 1) {
    if ((week - spec.xMin) % every === 0) xTicks.push(week);
  }

  const marks = [];
  if (bars) {
    const barW = Math.min(24, Math.max(6, band * 0.62));
    points.forEach((p, i) => {
      if (!(p.y > 0)) return;
      const x0 = xOf(p.x) - barW / 2;
      const y0 = yOf(p.y);
      const r = Math.min(4, barW / 2, base - y0);
      marks.push(
        h('path', {
          class: i === hover ? 'chart__bar chart__bar--on' : 'chart__bar', key: `bar-${p.x}`,
          d: `M${x0} ${base}V${y0 + r}Q${x0} ${y0} ${x0 + r} ${y0}H${x0 + barW - r}Q${x0 + barW} ${y0} ${x0 + barW} ${y0 + r}V${base}Z`,
        }),
      );
    });
  } else {
    if (points.length > 1) {
      marks.push(h('path', { class: 'chart__line', key: 'line', d: points.map((p, i) => `${i ? 'L' : 'M'}${xOf(p.x)} ${yOf(p.y)}`).join('') }));
    }
    points.forEach((p) => {
      marks.push(h('circle', { class: 'chart__dot', key: `dot-${p.x}`, cx: xOf(p.x), cy: yOf(p.y), r: 4 }));
    });
  }

  // подписано только последнее значение
  const lastPoint = points[points.length - 1];
  const lastX = xOf(lastPoint.x);
  const anchor = lastX > W - 40 ? 'end' : lastX < PAD.left + 24 ? 'start' : 'middle';
  const labelX = anchor === 'end' ? Math.min(W - 2, lastX + 10) : anchor === 'start' ? lastX - 6 : lastX;
  const endLabel = hover === points.length - 1
    ? null
    : h('text', { class: 'chart__label', key: 'end-label', x: labelX, y: yOf(lastPoint.y) - 10, 'text-anchor': anchor }, lastPoint.value);

  const focus = hover >= 0 ? points[hover] : null;
  const fx = focus ? xOf(focus.x) : 0;
  const fy = focus ? yOf(focus.y) : 0;

  return [
    h('svg', {
      key: 'svg', viewBox: `0 0 ${W} ${H}`, width: W, height: H, role: 'img', tabindex: 0,
      'aria-label': spec.label,
      onPointerDown: (event) => setHover(el, nearest(event)),
      onPointerMove: (event) => {
        if (event.pointerType === 'mouse' || event.buttons) setHover(el, nearest(event));
      },
      onPointerLeave: (event) => {
        if (event.pointerType === 'mouse') setHover(el, -1);
      },
      onKeyDown: onKey,
      onBlur: () => setHover(el, -1),
    },
    scale.ticks.map((tick) => h('g', { key: `y-${tick}` },
      tick === scale.lo && bars ? null : h('line', { class: 'chart__grid', x1: PAD.left, x2: W - PAD.right, y1: yOf(tick), y2: yOf(tick) }),
      h('text', { class: 'chart__tick', x: PAD.left - 8, y: yOf(tick), dy: '0.32em', 'text-anchor': 'end' }, fmt(tick)))),
    h('line', { class: 'chart__base', key: 'base', x1: PAD.left, x2: W - PAD.right, y1: base, y2: base }),
    xTicks.map((week) => h('text', { class: 'chart__tick', key: `x-${week}`, x: xOf(week), y: H - 7, 'text-anchor': 'middle' }, week)),
    spec.goal
      ? [
        h('line', { class: 'chart__goal', key: 'goal', x1: PAD.left, x2: W - PAD.right, y1: yOf(spec.goal.value), y2: yOf(spec.goal.value), 'stroke-dasharray': '5 4' }),
        h('text', { class: 'chart__note', key: 'goal-label', x: W - PAD.right, y: yOf(spec.goal.value) - 6, 'text-anchor': 'end' }, spec.goal.label),
      ]
      : null,
    focus && !bars ? h('line', { class: 'chart__cross', key: 'cross', x1: fx, x2: fx, y1: PAD.top, y2: base }) : null,
    marks,
    focus && !bars ? h('circle', { class: 'chart__focus', key: 'focus', cx: fx, cy: fy, r: 6 }) : null,
    endLabel),
    focus
      ? h('div', {
        class: 'chart__tip', key: 'tip', role: 'status',
        style: { left: `${Math.min(W - 80, Math.max(80, fx))}px`, top: `${Math.max(0, fy - 12)}px`, transform: 'translate(-50%, -100%)' },
      }, h('b', null, focus.value), focus.title)
      : null,
  ];
}
