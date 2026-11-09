// Значки: контурные, 24×24, рисуются цветом текста. Собраны из линий прямо в коде,
// чтобы приложение не зависело от шрифтов и картинок и работало без сети.

import { h } from './vdom.js';

const SHAPES = {
  // вкладки
  today: [['path', 'M6.5 6.5v11M17.5 6.5v11M3.5 9.5v5M20.5 9.5v5M6.5 12h11']],
  plan: [['rect', { x: 4, y: 5, width: 16, height: 15, rx: 2.5 }], ['path', 'M4 10h16M8.5 3v4M15.5 3v4']],
  progress: [['path', 'M4 19.5h16M5.5 15l4-5 4 3 5.5-7.5']],
  settings: [['path', 'M4 7.5h9M19 7.5h1M4 16.5h1M11 16.5h9'], ['circle', { cx: 16, cy: 7.5, r: 2.5 }], ['circle', { cx: 8, cy: 16.5, r: 2.5 }]],

  check: [['path', 'M5 12.5l4.5 4.5L19 7.5']],
  chevronDown: [['path', 'M6 9l6 6 6-6']],
  chevronUp: [['path', 'M6 15l6-6 6 6']],
  chevronRight: [['path', 'M9 6l6 6-6 6']],
  chevronLeft: [['path', 'M15 6l-6 6 6 6']],
  plus: [['path', 'M12 5v14M5 12h14']],
  minus: [['path', 'M5 12h14']],
  close: [['path', 'M6 6l12 12M18 6L6 18']],
  backspace: [['path', 'M9 5h10a2 2 0 0 1 2 2v10a2 2 0 0 1-2 2H9l-6-7 6-7z'], ['path', 'M12 9.5l5 5M17 9.5l-5 5']],
  timer: [['circle', { cx: 12, cy: 14, r: 7 }], ['path', 'M12 14v-4M9.5 3h5M12 3v4']],
  note: [['path', 'M4 20h4L19 9l-4-4L4 16v4z'], ['path', 'M13 7l4 4']],
  sync: [['path', 'M20 11a8 8 0 0 0-14.3-4.5L4 8.5'], ['path', 'M4 4v4.5h4.5'], ['path', 'M4 13a8 8 0 0 0 14.3 4.5l1.7-2'], ['path', 'M20 20v-4.5h-4.5']],
  cloudUp: [['path', 'M7 18.5a4 4 0 0 1-.6-7.96A6 6 0 0 1 18 10a4.25 4.25 0 0 1-.5 8.5'], ['path', 'M12 19v-6M9.5 15.5L12 13l2.5 2.5']],
  cloudOff: [['path', 'M7 18.5a4 4 0 0 1-.6-7.96 6 6 0 0 1 1.1-2.54M10.5 5.7A6 6 0 0 1 18 10a4.25 4.25 0 0 1 2.2 7.7M7 18.5h9.5'], ['path', 'M4 4l16 16']],
  alert: [['path', 'M12 4.5l9 15.5H3l9-15.5z'], ['path', 'M12 10.5v4M12 17.4v.1']],
  info: [['circle', { cx: 12, cy: 12, r: 8.5 }], ['path', 'M12 11v5M12 7.9v.1']],
  share: [['path', 'M12 15V3.5M8 7l4-4 4 4'], ['path', 'M7.5 11H6a1.5 1.5 0 0 0-1.5 1.5v7A1.5 1.5 0 0 0 6 21h12a1.5 1.5 0 0 0 1.5-1.5v-7A1.5 1.5 0 0 0 18 11h-1.5']],
  link: [['path', 'M14 5h5v5M19 5l-8 8'], ['path', 'M17 13.5V18a1.5 1.5 0 0 1-1.5 1.5h-9A1.5 1.5 0 0 1 5 18V9a1.5 1.5 0 0 1 1.5-1.5H11']],
};

/** @param {keyof typeof SHAPES} name */
export function icon(name, props = null) {
  const shapes = SHAPES[name] || [];
  return h(
    'svg',
    {
      viewBox: '0 0 24 24',
      fill: 'none',
      stroke: 'currentColor',
      'stroke-width': 2,
      'stroke-linecap': 'round',
      'stroke-linejoin': 'round',
      'aria-hidden': 'true',
      focusable: 'false',
      ...props,
    },
    shapes.map(([tag, spec]) => h(tag, typeof spec === 'string' ? { d: spec } : spec)),
  );
}
