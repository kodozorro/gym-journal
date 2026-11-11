// Разбор строки пути SVG в простые команды: M, L, C, Q, Z с абсолютными координатами.
//
// Рисунки и значки веб-приложения описаны путями SVG. Приложению на Swift разбирать полный
// синтаксис незачем: здесь относительные команды переводятся в абсолютные, а дуги — в кривые
// Безье. На выходе строка команд и плоский список чисел: «MLC» и [x, y, x, y, …].

const ARGS = { M: 2, L: 2, H: 1, V: 1, C: 6, Q: 4, A: 7, Z: 0 };
const NUMBER = /^[+-]?(?:\d*\.\d+|\d+\.?)(?:[eE][+-]?\d+)?/;

/** Разбивает строку пути на команды с числами: [{ op: 'M', args: [x, y] }, …]. */
export function tokenize(d) {
  const out = [];
  let rest = String(d).trim();
  let op = null;
  while (rest.length) {
    rest = rest.replace(/^[\s,]+/, '');
    if (!rest.length) break;
    const letter = /^[a-zA-Z]/.exec(rest);
    if (letter) {
      op = letter[0];
      rest = rest.slice(1);
      if (!(op.toUpperCase() in ARGS)) throw new Error(`Команда «${op}» в пути не поддержана: ${d}`);
      if (op.toUpperCase() === 'Z') {
        out.push({ op, args: [] });
        op = null;
      }
      continue;
    }
    if (!op) throw new Error(`Числа без команды в пути: ${d}`);
    const count = ARGS[op.toUpperCase()];
    const args = [];
    for (let i = 0; i < count; i += 1) {
      rest = rest.replace(/^[\s,]+/, '');
      // флаги дуги — одна цифра, следующую можно писать вплотную: «0 01-2»
      if (op.toUpperCase() === 'A' && (i === 3 || i === 4)) {
        if (rest[0] !== '0' && rest[0] !== '1') throw new Error(`Ожидался флаг дуги: ${d}`);
        args.push(Number(rest[0]));
        rest = rest.slice(1);
        continue;
      }
      const m = NUMBER.exec(rest);
      if (!m) throw new Error(`Ожидалось число в пути: ${d}`);
      args.push(Number(m[0]));
      rest = rest.slice(m[0].length);
    }
    out.push({ op, args });
    // после M без новой буквы идут неявные L
    if (op === 'M') op = 'L';
    else if (op === 'm') op = 'l';
  }
  return out;
}

/**
 * Дуга эллипса кривыми Безье (приложение F.6 спецификации SVG).
 * @returns {number[][]} отрезки [x1, y1, x2, y2, x, y]
 */
export function arcToCubics(x0, y0, rxIn, ryIn, rotation, large, sweep, x, y) {
  if (x0 === x && y0 === y) return [];
  let rx = Math.abs(rxIn);
  let ry = Math.abs(ryIn);
  if (rx === 0 || ry === 0) return [[x0, y0, x, y, x, y]];
  const phi = (rotation * Math.PI) / 180;
  const cos = Math.cos(phi);
  const sin = Math.sin(phi);
  const dx = (x0 - x) / 2;
  const dy = (y0 - y) / 2;
  const x1 = cos * dx + sin * dy;
  const y1 = -sin * dx + cos * dy;
  const lambda = (x1 * x1) / (rx * rx) + (y1 * y1) / (ry * ry);
  if (lambda > 1) {
    rx *= Math.sqrt(lambda);
    ry *= Math.sqrt(lambda);
  }
  const num = rx * rx * ry * ry - rx * rx * y1 * y1 - ry * ry * x1 * x1;
  const den = rx * rx * y1 * y1 + ry * ry * x1 * x1;
  const k = (large === sweep ? -1 : 1) * Math.sqrt(Math.max(0, num / den));
  const cx1 = (k * rx * y1) / ry;
  const cy1 = (-k * ry * x1) / rx;
  const cx = cos * cx1 - sin * cy1 + (x0 + x) / 2;
  const cy = sin * cx1 + cos * cy1 + (y0 + y) / 2;
  const angle = (ux, uy, vx, vy) => {
    const dot = ux * vx + uy * vy;
    const len = Math.hypot(ux, uy) * Math.hypot(vx, vy);
    const a = Math.acos(Math.min(1, Math.max(-1, dot / len)));
    return ux * vy - uy * vx < 0 ? -a : a;
  };
  const start = angle(1, 0, (x1 - cx1) / rx, (y1 - cy1) / ry);
  let delta = angle((x1 - cx1) / rx, (y1 - cy1) / ry, (-x1 - cx1) / rx, (-y1 - cy1) / ry);
  if (!sweep && delta > 0) delta -= 2 * Math.PI;
  if (sweep && delta < 0) delta += 2 * Math.PI;

  const pieces = Math.max(1, Math.ceil(Math.abs(delta) / (Math.PI / 2) - 1e-9));
  const step = delta / pieces;
  const t = (4 / 3) * Math.tan(step / 4);
  const point = (a) => {
    const px = rx * Math.cos(a);
    const py = ry * Math.sin(a);
    return [cos * px - sin * py + cx, sin * px + cos * py + cy];
  };
  const tangent = (a) => {
    const tx = -rx * Math.sin(a);
    const ty = ry * Math.cos(a);
    return [cos * tx - sin * ty, sin * tx + cos * ty];
  };
  const out = [];
  for (let i = 0; i < pieces; i += 1) {
    const a = start + step * i;
    const b = a + step;
    const [ax, ay] = point(a);
    const [bx, by] = point(b);
    const [tax, tay] = tangent(a);
    const [tbx, tby] = tangent(b);
    out.push([ax + t * tax, ay + t * tay, bx - t * tbx, by - t * tby, bx, by]);
  }
  // последняя точка — ровно та, что задана в пути
  out[out.length - 1][4] = x;
  out[out.length - 1][5] = y;
  return out;
}

const round = (value) => {
  const out = Math.round(value * 100) / 100;
  return Object.is(out, -0) ? 0 : out;
};

/**
 * Путь в простых командах.
 * @returns {{o: string, n: number[]}} o — команды M, L, C, Q, Z; n — их числа подряд
 */
export function simplify(d) {
  let ops = '';
  const numbers = [];
  let x = 0;
  let y = 0;
  let startX = 0;
  let startY = 0;
  const push = (op, ...values) => {
    ops += op;
    for (const value of values) numbers.push(round(value));
  };
  for (const { op, args } of tokenize(d)) {
    const relative = op !== op.toUpperCase();
    const bx = relative ? x : 0;
    const by = relative ? y : 0;
    switch (op.toUpperCase()) {
      case 'M':
        x = bx + args[0];
        y = by + args[1];
        startX = x;
        startY = y;
        push('M', x, y);
        break;
      case 'L':
        x = bx + args[0];
        y = by + args[1];
        push('L', x, y);
        break;
      case 'H':
        x = bx + args[0];
        push('L', x, y);
        break;
      case 'V':
        y = by + args[0];
        push('L', x, y);
        break;
      case 'C':
        push('C', bx + args[0], by + args[1], bx + args[2], by + args[3], bx + args[4], by + args[5]);
        x = bx + args[4];
        y = by + args[5];
        break;
      case 'Q':
        push('Q', bx + args[0], by + args[1], bx + args[2], by + args[3]);
        x = bx + args[2];
        y = by + args[3];
        break;
      case 'A': {
        const ex = bx + args[5];
        const ey = by + args[6];
        for (const c of arcToCubics(x, y, args[0], args[1], args[2], args[3], args[4], ex, ey)) push('C', ...c);
        x = ex;
        y = ey;
        break;
      }
      case 'Z':
        push('Z');
        x = startX;
        y = startY;
        break;
      default:
        throw new Error(`Команда «${op}» не поддержана`);
    }
  }
  return { o: ops, n: numbers };
}

/** Окружность четырьмя кривыми. */
export function circlePath(cx, cy, r) {
  const k = 0.5522847498 * r;
  return simplify(
    `M${cx + r} ${cy}C${cx + r} ${cy + k} ${cx + k} ${cy + r} ${cx} ${cy + r}` +
    `C${cx - k} ${cy + r} ${cx - r} ${cy + k} ${cx - r} ${cy}` +
    `C${cx - r} ${cy - k} ${cx - k} ${cy - r} ${cx} ${cy - r}` +
    `C${cx + k} ${cy - r} ${cx + r} ${cy - k} ${cx + r} ${cy}Z`,
  );
}

/** Прямоугольник со скруглёнными углами. */
export function rectPath(x, y, width, height, radius = 0) {
  const r = Math.max(0, Math.min(radius, width / 2, height / 2));
  if (r === 0) return simplify(`M${x} ${y}H${x + width}V${y + height}H${x}Z`);
  const k = 0.5522847498 * r;
  const right = x + width;
  const bottom = y + height;
  return simplify(
    `M${x + r} ${y}L${right - r} ${y}C${right - r + k} ${y} ${right} ${y + r - k} ${right} ${y + r}` +
    `L${right} ${bottom - r}C${right} ${bottom - r + k} ${right - r + k} ${bottom} ${right - r} ${bottom}` +
    `L${x + r} ${bottom}C${x + r - k} ${bottom} ${x} ${bottom - r + k} ${x} ${bottom - r}` +
    `L${x} ${y + r}C${x} ${y + r - k} ${x + r - k} ${y} ${x + r} ${y}Z`,
  );
}

/** Обратно в строку пути: для проверки рисунков в браузере. */
export function toPathData({ o, n }) {
  const count = { M: 2, L: 2, C: 6, Q: 4, Z: 0 };
  let out = '';
  let index = 0;
  for (const op of o) {
    out += op + n.slice(index, index + count[op]).join(' ');
    index += count[op];
  }
  return out;
}
