// Рисунки упражнений и значки веб-приложения в виде, который читает приложение на Swift.
//
// Источник один — js/ui/art.js и js/ui/icons.js. Здесь их разметка SVG превращается в список
// фигур из простых команд пути. Цвет не записывается: остаются имена ролей («frame», «body»),
// а приложение красит их под свою тему так же, как css/app.css.

import { art, ART_NAMES } from '../../js/ui/art.js';
import { icon } from '../../js/ui/icons.js';
import { circlePath, rectPath, simplify } from './svgpath.mjs';

const ART_PREFIX = 'art__';

function roles(className) {
  return String(className || '').split(/\s+/).filter(Boolean).map((name) => {
    if (!name.startsWith(ART_PREFIX)) throw new Error(`Класс «${name}» не из рисунков`);
    return name.slice(ART_PREFIX.length);
  });
}

function shapeOf(node) {
  const p = node.props;
  if (node.tag === 'path') return simplify(p.d);
  if (node.tag === 'circle') return circlePath(Number(p.cx), Number(p.cy), Number(p.r));
  if (node.tag === 'rect') return rectPath(Number(p.x), Number(p.y), Number(p.width), Number(p.height), Number(p.rx || 0));
  throw new Error(`Элемент <${node.tag}> в рисунке не поддержан`);
}

function artNode(node) {
  if (node.tag === 'g') {
    return { c: roles(node.props.class), ch: node.children.map(artNode) };
  }
  const out = { c: roles(node.props.class), ...shapeOf(node) };
  const width = node.props['stroke-width'];
  if (width !== undefined) out.w = Math.round(Number(width) * 100) / 100;
  const dash = node.props['stroke-dasharray'];
  if (dash !== undefined) out.dash = String(dash).trim().split(/[\s,]+/).map(Number);
  return out;
}

/** Все рисунки: { width, height, items: { имя: [узлы] } }. */
export function exportArt() {
  const items = {};
  let size = null;
  for (const name of ART_NAMES) {
    const svg = art(name, '');
    const [, , width, height] = svg.props.viewBox.split(' ').map(Number);
    size = { width, height };
    items[name] = svg.children.map(artNode);
  }
  return { ...size, items };
}

/** Имена значков берутся из самого модуля: в нём нет списка наружу, поэтому читаем исходник. */
export function iconNames(source) {
  const body = /const SHAPES = \{([\s\S]*?)\n\};/.exec(source);
  if (!body) throw new Error('В js/ui/icons.js не найден список значков');
  return [...body[1].matchAll(/^\s{2}([A-Za-z][A-Za-z0-9]*):/gm)].map((m) => m[1]);
}

/** Все значки: { size, items: { имя: [пути] } }. Линии толщиной 2 на поле 24 × 24. */
export function exportIcons(source) {
  const items = {};
  for (const name of iconNames(source)) {
    const svg = icon(name);
    items[name] = svg.children.map((node) => {
      if (node.tag === 'path') return simplify(node.props.d);
      return shapeOf(node);
    });
    if (!items[name].length) throw new Error(`Значок «${name}» пуст`);
  }
  return { size: 24, stroke: 2, items };
}
