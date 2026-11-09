// Маленький виртуальный DOM. Экран описывается заново при каждом изменении состояния,
// а в настоящем DOM меняется только то, что изменилось. Поэтому кнопка под пальцем
// остаётся той же кнопкой, даже если в эту секунду пришёл ответ от таблицы:
// нажатие не теряется, прокрутка и фокус не сбрасываются.
//
// Разметка собирается только через createElement и текстовые узлы, без innerHTML:
// текст из таблицы не может стать кодом.

const SVG_NS = 'http://www.w3.org/2000/svg';
const EMPTY = Object.freeze({});
const AS_PROPERTY = new Set(['checked', 'disabled', 'selected', 'readOnly', 'hidden']);

/**
 * Описание узла.
 * @param {string} tag
 * @param {object|null} props class, style (объект), on<Событие>, key, hook {create, update}, остальное — атрибуты
 * @param {...any} children узлы, строки, числа, массивы; null и false пропускаются
 */
export function h(tag, props, ...children) {
  const node = { tag, props: props || EMPTY, children: [], key: props && props.key !== undefined ? props.key : null, el: null };
  collect(node.children, children);
  return node;
}

function collect(out, list) {
  for (const child of list) {
    if (child === null || child === undefined || child === false || child === true) continue;
    if (Array.isArray(child)) collect(out, child);
    else if (typeof child === 'object') out.push(child);
    else out.push({ text: String(child), key: null, el: null });
  }
}

/** Приводит содержимое контейнера к описанию view. Кроме описанного, в контейнере ничего быть не должно. */
export function render(container, view) {
  const next = [];
  collect(next, [view]);
  let prev = container.__vdom;
  if (!prev) {
    container.textContent = '';
    prev = [];
  }
  const after = [];
  patchChildren(container, prev, next, null, after);
  container.__vdom = next;
  for (const job of after) job();
}

function create(node, ns, after) {
  if (node.text !== undefined) {
    node.el = document.createTextNode(node.text);
    return node.el;
  }
  const ownNs = node.tag === 'svg' ? SVG_NS : ns;
  const el = ownNs ? document.createElementNS(ownNs, node.tag) : document.createElement(node.tag);
  node.el = el;
  for (const child of node.children) el.appendChild(create(child, ownNs, after));
  const props = node.props;
  for (const name in props) setProp(el, name, props[name], undefined);
  if (props.hook && props.hook.create) after.push(() => props.hook.create(el));
  return el;
}

/**
 * Узлы с ключом сопоставляются по ключу, остальные — по порядку среди таких же.
 * Сначала убирается лишнее, потом расставляется нужное: уцелевшие узлы при этом
 * не переносятся, так что вставка плашки сверху не сбрасывает прокрутку карточек ниже.
 */
function patchChildren(parent, prev, next, ns, after) {
  const keyed = new Map();
  const loose = [];
  for (const node of prev) {
    if (node.key !== null) keyed.set(node.key, node);
    else loose.push(node);
  }
  let looseIndex = 0;
  const used = new Set();
  const match = new Array(next.length);
  for (let i = 0; i < next.length; i += 1) {
    const b = next[i];
    let a;
    if (b.key !== null) {
      a = keyed.get(b.key);
    } else {
      a = loose[looseIndex];
      looseIndex += 1;
    }
    if (a && a.tag === b.tag && !used.has(a)) {
      used.add(a);
      match[i] = a;
    } else {
      match[i] = null;
    }
  }
  for (const node of prev) {
    if (!used.has(node)) parent.removeChild(node.el);
  }
  let ref = parent.firstChild;
  for (let i = 0; i < next.length; i += 1) {
    const a = match[i];
    const b = next[i];
    if (!a) {
      parent.insertBefore(create(b, ns, after), ref);
      continue;
    }
    if (b.text !== undefined) {
      b.el = a.el;
      if (a.text !== b.text) b.el.nodeValue = b.text;
    } else {
      patch(a, b, ns, after);
    }
    if (b.el === ref) ref = ref.nextSibling;
    else parent.insertBefore(b.el, ref);
  }
}

function patch(a, b, ns, after) {
  const el = a.el;
  b.el = el;
  const ownNs = b.tag === 'svg' ? SVG_NS : ns;
  patchChildren(el, a.children, b.children, ownNs, after);
  const before = a.props;
  const props = b.props;
  for (const name in props) {
    if (props[name] !== before[name] || name === 'value') setProp(el, name, props[name], before[name]);
  }
  for (const name in before) {
    if (!(name in props)) setProp(el, name, undefined, before[name]);
  }
  if (props.hook && props.hook.update) after.push(() => props.hook.update(el));
}

function setProp(el, name, value, before) {
  if (name === 'key' || name === 'hook') return;
  if (name === 'class') {
    if (value) el.setAttribute('class', value);
    else el.removeAttribute('class');
    return;
  }
  if (name === 'style') {
    setStyle(el, value || EMPTY, before || EMPTY);
    return;
  }
  if (name.length > 2 && name[0] === 'o' && name[1] === 'n') {
    setHandler(el, name.slice(2).toLowerCase(), value);
    return;
  }
  if (name === 'value') {
    const text = value === null || value === undefined ? '' : String(value);
    if (el.value !== text) el.value = text;
    return;
  }
  if (AS_PROPERTY.has(name)) {
    el[name] = Boolean(value);
    return;
  }
  if (value === null || value === undefined || value === false) el.removeAttribute(name);
  else el.setAttribute(name, value === true ? '' : String(value));
}

// Стили ставятся по одному свойству через CSSOM: политика безопасности страницы
// запрещает атрибут style, но не запрещает el.style.
function setStyle(el, style, before) {
  for (const name in before) {
    if (!(name in style)) el.style.removeProperty(name);
  }
  for (const name in style) {
    const value = style[name];
    if (value === before[name]) continue;
    if (value === null || value === undefined || value === false) el.style.removeProperty(name);
    else el.style.setProperty(name, String(value));
  }
}

// На элементе висит один постоянный слушатель на тип события; меняется только то, что он вызывает.
function setHandler(el, type, fn) {
  let map = el.__on;
  if (!map) {
    map = {};
    el.__on = map;
  }
  if (!(type in map)) el.addEventListener(type, dispatch);
  map[type] = typeof fn === 'function' ? fn : null;
}

function dispatch(event) {
  const fn = this.__on && this.__on[event.type];
  if (fn) fn.call(this, event);
}

/** Склеивает имена классов, пропуская пустые: cx('ex', done && 'ex--closed'). */
export function cx(...names) {
  return names.filter(Boolean).join(' ');
}
