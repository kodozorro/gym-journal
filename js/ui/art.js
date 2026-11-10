// Рисунки упражнений: тренажёр и человек в двух крайних положениях.
//
// Собраны из линий прямо в коде, как и значки: рисунки перекрашиваются под тему и работают
// без сети. Яркая и бледная фигуры — начало и конец движения, красным показано то, что на
// тренажёре движется, синей стрелкой — рабочее усилие.
//
// Углы в градусах: 0 — вправо, 90 — вниз. Холст 320 × 240, пол на высоте FLOOR.

import { h } from './vdom.js';

const WIDTH = 320;
const HEIGHT = 240;
const FLOOR = 222;
const RAD = Math.PI / 180;

/** Длины звеньев фигуры при масштабе 1. */
const SIZE = { torso: 54, upper: 31, fore: 29, thigh: 49, shin: 47, foot: 16, neck: 21, head: 10.5 };

const round = (value) => Math.round(value * 10) / 10;
const at = (p, deg, len) => [p[0] + len * Math.cos(deg * RAD), p[1] + len * Math.sin(deg * RAD)];
const add = (p, dx, dy) => [p[0] + dx, p[1] + dy];
const angleOf = (a, b) => Math.atan2(b[1] - a[1], b[0] - a[0]) / RAD;
const dist = (a, b) => Math.hypot(b[0] - a[0], b[1] - a[1]);
/** Точка p, повёрнутая вокруг c на deg градусов. */
const turn = (p, c, deg) => at(c, angleOf(c, p) + deg, dist(c, p));
const line = (points) => points.map((p, i) => `${i ? 'L' : 'M'}${round(p[0])} ${round(p[1])}`).join('');

/**
 * Средний сустав двухзвенной конечности от a к c: колено или локоть.
 * side (+1 или −1) выбирает сторону сгиба. Недостижимая цель подтягивается ближе.
 */
function joint(a, c, l1, l2, side) {
  const d = Math.min(l1 + l2 - 0.5, Math.max(Math.abs(l1 - l2) + 0.5, dist(a, c)));
  const base = angleOf(a, c);
  const inner = Math.acos((l1 * l1 + d * d - l2 * l2) / (2 * l1 * d)) / RAD;
  return [at(a, base + side * inner, l1), at(a, base, d)];
}

/* ------------------------------------------------------------------ */
/* Детали                                                              */
/* ------------------------------------------------------------------ */

const frame = (width, ...points) => h('path', { class: 'art__frame', 'stroke-width': width, d: line(points) });
const pad = (width, ...points) => h('path', { class: 'art__pad', 'stroke-width': width, d: line(points) });
const red = (width, ...points) => h('path', { class: 'art__move', 'stroke-width': width, d: line(points) });
const ink = (width, ...points) => h('path', { class: 'art__body', 'stroke-width': width, d: line(points) });
const gap = (width, ...points) => h('path', { class: 'art__halo', 'stroke-width': width, d: line(points) });
const cable = (...points) => h('path', { class: 'art__cable', 'stroke-width': 1.6, d: line(points) });

const circle = (c, r) => ({ cx: round(c[0]), cy: round(c[1]), r: round(r) });
const inkDot = (c, r) => h('circle', { class: 'art__fill-body', ...circle(c, r) });
const gapDot = (c, r) => h('circle', { class: 'art__fill-panel', ...circle(c, r) });
const padDot = (c, r) => h('circle', { class: 'art__fill-pad', ...circle(c, r) });
const redDot = (c, r) => h('circle', { class: 'art__fill-move', ...circle(c, r) });
const hub = (c, r) => h('circle', { class: 'art__hub', 'stroke-width': 2, ...circle(c, r) });
/** Блин: диск со ступицей. */
const plate = (c, r) => [padDot(c, r), gapDot(c, r * 0.22)];

const floor = (x1 = 12, x2 = WIDTH - 12) => h('path', { class: 'art__floor', 'stroke-width': 2, d: line([[x1, FLOOR], [x2, FLOOR]]) });
const ghost = (...children) => h('g', { class: 'art__ghost' }, children);
const box = (x, y, width, height, rx) => ({ 'stroke-width': 2, x: round(x), y: round(y), width: round(width), height: round(height), rx });

/** Кожух грузового стека с плитками. */
function tower(x, y, width, height = FLOOR - 1 - y) {
  const marks = [];
  for (let level = y + height * 0.42 + 7; level < y + height - 8; level += 7) {
    marks.push(h('path', { class: 'art__frame', 'stroke-width': 1.4, d: line([[x + 7, level], [x + width - 7, level]]) }));
  }
  return [h('rect', { class: 'art__tower', ...box(x, y, width, height, 4) }), marks];
}

function arrowHead(tip, deg) {
  return h('path', { class: 'art__fill-arrow', d: `${line([at(tip, deg, 3), at(tip, deg + 150, 9), at(tip, deg - 150, 9)])}Z` });
}

/** Прямая стрелка от a к b. */
function arrow(a, b) {
  const deg = angleOf(a, b);
  return [h('path', { class: 'art__arrow', 'stroke-width': 3, d: line([a, at(b, deg + 180, 5)]) }), arrowHead(b, deg)];
}

/** Стрелка по дуге вокруг c от угла from до угла to. */
function arcArrow(c, r, from, to) {
  const clockwise = to > from;
  const stop = to - (clockwise ? 1 : -1) * (5 / r) / RAD;
  const a = at(c, from, r);
  const b = at(c, stop, r);
  const large = Math.abs(stop - from) > 180 ? 1 : 0;
  return [
    h('path', {
      class: 'art__arrow', 'stroke-width': 3,
      d: `M${round(a[0])} ${round(a[1])}A${round(r)} ${round(r)} 0 ${large} ${clockwise ? 1 : 0} ${round(b[0])} ${round(b[1])}`,
    }),
    arrowHead(at(c, to, r), to + (clockwise ? 90 : -90)),
  ];
}

/* ------------------------------------------------------------------ */
/* Фигура сбоку                                                        */
/* ------------------------------------------------------------------ */

function limb(root, spec, l1, l2) {
  if (!spec) return null;
  if (spec.mid) return { mid: spec.mid, end: spec.end };
  if (spec.to) {
    const [mid, end] = joint(root, spec.to, l1, l2, spec.side || 1);
    return { mid, end };
  }
  const mid = at(root, spec.a, l1);
  return { mid, end: at(mid, spec.b, l2) };
}

function legOf(hip, spec, k) {
  const leg = limb(hip, spec, SIZE.thigh * k, SIZE.shin * k);
  if (leg) leg.toe = at(leg.end, spec.toe === undefined ? 0 : spec.toe, SIZE.foot * k);
  return leg;
}

/**
 * Суставы фигуры, видимой сбоку.
 * @param {object} spec
 * @param {number[]} spec.hip таз
 * @param {number} spec.torso направление от таза к плечу
 * @param {number} [spec.neck] направление от плеча к голове
 * @param {object} [spec.arm] {to, side} — кисть в точке to, {a, b} — углы плеча и предплечья, {mid, end} — готовые точки
 * @param {object} [spec.leg] {to, side, toe} — голеностоп в точке to, или {a, b, toe}
 * @param {object} [spec.farArm] дальняя рука
 * @param {object} [spec.farLeg] дальняя нога
 * @param {boolean} [spec.farHollow] дальняя нога не работает: рисуется контуром
 * @param {number} [spec.k] масштаб
 */
function sideJoints(spec) {
  const k = spec.k || 1;
  const hip = spec.hip;
  const shoulder = at(hip, spec.torso, SIZE.torso * k);
  return {
    k,
    hip,
    shoulder,
    head: at(shoulder, spec.neck === undefined ? spec.torso : spec.neck, SIZE.neck * k),
    arm: limb(shoulder, spec.arm, SIZE.upper * k, SIZE.fore * k),
    leg: legOf(hip, spec.leg, k),
    farArm: limb(shoulder, spec.farArm, SIZE.upper * k, SIZE.fore * k),
    farLeg: legOf(hip, spec.farLeg, k),
    farHollow: Boolean(spec.farHollow),
  };
}

/** Фигура по суставам. outline — светлый просвет вокруг, чтобы тело не сливалось с тренажёром. */
function sideFigure(j, outline = true) {
  const k = j.k;
  const trunk = [[20, j.hip, j.shoulder]];
  const leg = j.leg ? [[14, j.hip, j.leg.mid], [11.5, j.leg.mid, j.leg.end], [8, j.leg.end, j.leg.toe]] : [];
  const arm = j.arm ? [[9.5, j.shoulder, j.arm.mid], [8.5, j.arm.mid, j.arm.end]] : [];
  const draw = (parts, make, extra = 0) => parts.map(([width, ...points]) => make(width * k + extra, ...points));
  const farLeg = j.farLeg ? [[13.5, j.hip, j.farLeg.mid], [11, j.farLeg.mid, j.farLeg.end], [8, j.farLeg.end, j.farLeg.toe]] : [];
  return [
    draw(farLeg, ink),
    j.farHollow ? draw(farLeg, gap, -4.5) : null,
    j.farArm ? draw([[9.5, j.shoulder, j.farArm.mid], [8.5, j.farArm.mid, j.farArm.end]], ink) : null,
    outline ? [draw(trunk, gap, 4), gapDot(j.head, SIZE.head * k + 2), draw(leg, gap, 4)] : null,
    draw(trunk, ink),
    inkDot(j.head, SIZE.head * k),
    draw(leg, ink),
    j.arm ? [gap(14.5 * k, j.shoulder, j.arm.mid, j.arm.end), draw(arm, ink)] : null,
  ];
}

/**
 * Рисунок из двух крайних положений. pose(t) описывает фигуру в начале (t = 0) и в конце (t = 1)
 * рабочего движения, moving(суставы, t) рисует подвижные части тренажёра. Ярким рисуется
 * положение solid, второе — бледным под ним.
 */
function twoPoses({ still, pose, moving, arrows, solid = 0 }) {
  const dark = sideJoints(pose(solid));
  const light = sideJoints(pose(1 - solid));
  return [
    floor(),
    still,
    ghost(moving ? moving(light, 1 - solid) : null, sideFigure(light, false)),
    moving ? moving(dark, solid) : null,
    sideFigure(dark),
    arrows,
  ];
}

/* ------------------------------------------------------------------ */
/* Рисунки: вид сбоку                                                  */
/* ------------------------------------------------------------------ */

/** Жим ногами сидя: платформа неподвижна, сиденье отъезжает назад по наклонным направляющим. */
function seatedLegPress() {
  const BACK = 191; // направление «назад» вдоль направляющих
  const ankle = [226, 150];
  const pose = (t) => {
    const hip = at([159, 166], BACK, 26 * t);
    return { hip, torso: -115, neck: -104, arm: { to: add(hip, 2, -3), side: -1 }, leg: { to: ankle, side: -1, toe: -80 } };
  };
  const moving = (j) => {
    const base = add(j.hip, 0, 21);
    return [
      red(7, at(base, BACK + 180, 28), at(base, BACK, 32)),
      red(6, at(base, BACK, 28), add(j.shoulder, -19, 6)),
      pad(8, add(j.hip, -10, 13), add(j.hip, 30, 9)),
      pad(8, add(j.hip, -14, 5), add(j.shoulder, -14, 1)),
    ];
  };
  const railFrom = at([159, 193], BACK + 180, 80);
  const railTo = at([159, 193], BACK, 112);
  return twoPoses({
    still: [
      tower(264, 60, 34),
      frame(5, [40, 219], [300, 219]),
      frame(5, railFrom, railTo),
      frame(5, railTo, add(railTo, -4, 46)),
      frame(5, railFrom, add(railFrom, 4, 12)),
      frame(5, [238, 136], [264, 136]),
      frame(8, [243, 100], [231, 176]),
    ],
    pose,
    moving,
    arrows: arrow([150, 210], [96, 199.5]),
  });
}

/** Жим от груди: рычаги на шарнире у пола, рукояти идут вперёд по дуге. */
function chestPress() {
  const hip = [116, 169];
  const pivot = [138, 213];
  const grip = [124, 136];
  const swing = 28;
  const pose = (t) => ({
    hip, torso: -97, neck: -92,
    arm: { to: turn(grip, pivot, swing * t), side: 1 },
    leg: { a: -4, b: 84, toe: 12 },
  });
  const moving = (j) => [red(6, pivot, at(j.arm.end, angleOf(pivot, j.arm.end), 10)), redDot(pivot, 5)];
  return twoPoses({
    still: [
      tower(22, 54, 34),
      frame(5, [22, 219], [206, 219]),
      frame(5, [56, 122], [98, 122]),
      frame(5, [118, 184], [118, 217]),
      pad(8, [100, 181], [144, 180]),
      pad(9, [102, 168], [92, 88]),
    ],
    pose,
    moving,
    arrows: arcArrow(pivot, dist(pivot, grip) + 17, angleOf(pivot, grip) + 3, angleOf(pivot, grip) + swing + 3),
  });
}

/** Жим вверх: длинный рычаг на шарнире позади, рукояти у плеч. */
function shoulderPress() {
  const hip = [118, 172];
  const pivot = [50, 104];
  const grip = [130, 114];
  const swing = -38;
  const pose = (t) => ({
    hip, torso: -92, neck: -90,
    arm: { to: turn(grip, pivot, swing * t), side: 1 },
    leg: { a: -4, b: 84, toe: 12 },
  });
  const moving = (j) => [red(7, pivot, at(j.arm.end, angleOf(pivot, j.arm.end), 30)), redDot(pivot, 5)];
  return twoPoses({
    still: [
      tower(22, 40, 34),
      frame(5, [22, 219], [206, 219]),
      frame(5, [122, 187], [122, 217]),
      pad(8, [102, 184], [146, 183]),
      pad(9, [104, 172], [101, 98]),
    ],
    pose,
    moving,
    arrows: arcArrow(pivot, dist(pivot, grip) + 22, angleOf(pivot, grip) - 3, angleOf(pivot, grip) + swing + 5),
  });
}

/**
 * Тяга сидя: трос от нижнего блока, ноги в упорах. Ярким показан конец движения: вытянутые
 * руки иначе закрыли бы всё остальное. Широкий хват — локти выше и в стороны, кисти к груди.
 */
function seatedRow(wide) {
  const hip = [112, 163];
  const pulley = [246, 146];
  const pose = (t) => {
    const torso = -80 - 17 * t;
    const shoulder = at(hip, torso, SIZE.torso);
    let arm = { to: [174, 138], side: 1 };
    if (t) arm = wide ? { mid: add(shoulder, -9, 14), end: add(shoulder, 18, 21) } : { to: [126, 145], side: 1 };
    return { hip, torso, arm, leg: { to: [198, 178], side: -1, toe: -74 } };
  };
  const moving = (j) => [
    cable(j.arm.end, pulley),
    red(5, add(j.arm.end, 0, -7), add(j.arm.end, 0, 7)),
  ];
  return twoPoses({
    still: [
      tower(268, 40, 34),
      frame(5, [38, 219], [268, 219]),
      frame(5, [58, 180], [52, 217]),
      frame(5, [128, 180], [134, 217]),
      frame(5, [252, 217], [240, 70]),
      frame(5, [240, 70], [268, 62]),
      frame(5, [206, 196], [214, 217]),
      frame(8, [197, 204], [211, 152]),
      hub(pulley, 7),
      pad(9, [40, 177], [142, 177]),
    ],
    pose,
    moving,
    solid: 1,
    arrows: arrow([200, 122], [160, 115]),
  });
}

/** Жим ногами под 45°: спина на наклонной спинке, платформа с дисками уходит вверх по направляющим. */
function legPress45() {
  const UP = -45; // вверх вдоль направляющих
  const hip = [112, 190];
  const ankle = at(hip, -42, 69);
  const pose = (t) => ({
    hip, torso: -152, neck: -160,
    arm: { to: add(hip, 6, 4), side: -1 },
    leg: { to: at(ankle, UP, 24 * t), side: -1, toe: UP - 90 },
  });
  const onRail = (j) => at(at(j.leg.end, UP, 7), UP + 90, 22);
  const moving = (j) => {
    const sole = at(j.leg.end, UP, 7);
    const sled = onRail(j);
    return [
      plate(at(at(sled, UP, 36), UP + 90, 4), 20),
      plate(at(at(sled, UP, 8), UP + 90, 22), 14),
      red(7, at(sled, UP + 180, 6), at(sled, UP, 44)),
      red(8, at(sole, UP + 90, 20), at(sole, UP - 90, 40)),
    ];
  };
  const rail = onRail(sideJoints(pose(0)));
  const railTop = at(rail, UP, 128);
  return twoPoses({
    still: [
      frame(5, [30, 219], [296, 219]),
      frame(5, at(rail, UP + 180, 86), railTop),
      frame(5, railTop, [railTop[0] + 6, 217]),
      frame(5, [66, 196], [60, 217]),
      pad(9, add(hip, 0, 15), at(add(hip, -7, 12), -152, 88)),
      pad(9, add(hip, 2, 15), add(hip, 22, 9)),
    ],
    pose,
    moving,
    arrows: arrow([116, 106], at([116, 106], UP, 36)),
  });
}

/** Гакк-жим: стопы на неподвижной платформе, спина и плечи на каретке, каретка скользит под 45°. */
function hackPress() {
  const UP = -45;
  const ACROSS = 45; // от груди к спине
  const ankle = [92, 178];
  const top = at(at(ankle, UP, 94), ACROSS, 8);
  const pose = (t) => {
    const hip = at(top, UP + 180, 26 * (1 - t));
    const shoulder = at(hip, UP, SIZE.torso);
    return {
      hip, torso: UP,
      arm: { to: at(at(shoulder, UP, 12), ACROSS + 180, 13), side: -1 },
      leg: { to: ankle, side: 1, toe: UP - 90 },
    };
  };
  const moving = (j) => {
    const low = at(at(j.hip, ACROSS, 22), UP + 180, 12);
    const high = at(at(j.shoulder, ACROSS, 22), UP, 22);
    return [
      plate(at(at(high, ACROSS, 14), UP + 180, 8), 18),
      red(7, low, high),
      pad(9, at(at(j.hip, ACROSS, 13), UP + 180, 4), at(at(j.shoulder, ACROSS, 13), UP, 8)),
      pad(9, at(at(j.shoulder, UP, 13), ACROSS, 12), at(at(j.shoulder, UP, 13), ACROSS + 180, 8)),
    ];
  };
  const sole = at(ankle, UP + 180, 7);
  const railLow = at(at(top, ACROSS, 31), UP + 180, 96);
  const railHigh = at(at(top, ACROSS, 31), UP, 96);
  const heelEnd = at(sole, ACROSS, 16);
  const toeEnd = at(sole, ACROSS + 180, 44);
  return twoPoses({
    still: [
      frame(5, [40, 219], [286, 219]),
      frame(5, railLow, railHigh),
      frame(5, railHigh, [railHigh[0] + 8, 217]),
      frame(5, railLow, [railLow[0] - 4, 217]),
      frame(5, heelEnd, [heelEnd[0] + 4, 217]),
      frame(5, toeEnd, [toeEnd[0] - 6, 217]),
      frame(8, heelEnd, toeEnd),
    ],
    pose,
    moving,
    arrows: arrow([124, 96], at([124, 96], UP, 36)),
  });
}

/**
 * Сгибание ног с опорой на колено: предплечья и бедро на подушках, колено второй ноги на своей
 * подушке, валик за голеностопом рабочей ноги, ось рычага у колена.
 */
function kneelingLegCurl() {
  const hip = [164, 104];
  const THIGH = 122;
  const HANG = 92;
  const CURL = 115;
  const knee = at(hip, THIGH, SIZE.thigh);
  const pose = (t) => ({
    hip, torso: -28, neck: -14,
    arm: { a: 78, b: -5 },
    leg: { a: THIGH, b: HANG + CURL * t, toe: HANG + CURL * t - 82 },
    farLeg: { a: 100, b: 178, toe: 100 },
    farHollow: true,
  });
  const moving = (j, t) => {
    const shin = HANG + CURL * t;
    const roller = at(at(knee, shin, SIZE.shin - 9), shin + 90, 13);
    return [red(6, knee, roller), padDot(roller, 9), redDot(knee, 5)];
  };
  const rest = sideJoints(pose(0));
  const farKnee = rest.farLeg.mid;
  const front = at(hip, THIGH - 90, 13.5);
  return twoPoses({
    still: [
      frame(5, [96, 219], [262, 219]),
      frame(5, [238, 217], [238, rest.arm.end[1] + 14]),
      frame(5, [238, 166], add(knee, 14, 8)),
      frame(5, [farKnee[0] + 6, farKnee[1] + 16], [farKnee[0] + 6, 217]),
      frame(4, add(rest.arm.end, 4, 8), add(rest.arm.end, 8, -14)),
      pad(8, [farKnee[0] - 10, farKnee[1] + 11], [farKnee[0] + 18, farKnee[1] + 11]),
      pad(9, add(rest.arm.mid, -8, 11), add(rest.arm.end, 6, 11)),
      pad(11, at(front, THIGH, 8), at(front, THIGH, SIZE.thigh - 1)),
    ],
    pose,
    moving,
    arrows: arcArrow(knee, SIZE.shin + 17, HANG + 10, HANG + CURL - 8),
  });
}

/** Ходьба в гору на дорожке. Наклон на рисунке нарочно больше настоящего, чтобы его было видно. */
function treadmill() {
  const k = 0.92;
  const rear = [58, 212];
  const front = [240, 186];
  const slope = (front[1] - rear[1]) / (front[0] - rear[0]);
  const belt = (x) => rear[1] + (x - rear[0]) * slope - 6;
  const j = sideJoints({
    k, hip: [150, 103], torso: -82, neck: -86,
    arm: { a: 112, b: 70 },
    farArm: { a: 54, b: 0 },
    leg: { to: [178, belt(178) - 6], side: -1, toe: -9 },
    farLeg: { to: [111, belt(111) - 17], side: -1, toe: 58 },
  });
  return [
    floor(),
    h('path', { class: 'art__floor', 'stroke-width': 1.6, 'stroke-dasharray': '4 5', d: line([rear, [front[0] + 4, rear[1]]]) }),
    frame(12, rear, front),
    frame(5, [front[0] - 2, front[1]], [front[0] + 14, 98]),
    frame(5, [front[0] + 9, 128], [front[0] - 30, 132]),
    frame(12, [front[0] + 2, 92], [front[0] + 22, 88]),
    frame(5, [front[0] + 4, front[1] + 6], [front[0] + 4, 217]),
    frame(5, [rear[0] + 2, 214], [rear[0] + 2, 217]),
    sideFigure(j),
    arrow([front[0] + 22, rear[1] - 1], [front[0] + 22, front[1] + 2]),
  ];
}

/* ------------------------------------------------------------------ */
/* Рисунки: вид сверху и спереди                                       */
/* ------------------------------------------------------------------ */

/**
 * Сведение рук и обратные разведения: один тренажёр, рычаги вращаются над плечами. Вид сверху,
 * стойка слева. При сведении человек сидит спиной к подушке, при обратных разведениях — лицом.
 * Ярким показано положение «руки впереди», бледным — «руки в стороны».
 */
function pecDeck(reverse) {
  const face = reverse ? -1 : 1; // куда смотрит человек: 1 — вправо, от стойки, −1 — влево, к ней
  const x = 152;
  const y = 120;
  const padX = x - 22;
  const reach = 60;
  const shoulders = [[x, y - 29], [x, y + 29]];
  const pivots = [[x - 13, y - 31], [x - 13, y + 31]];
  // углы верхнего рычага; нижний зеркален
  const forward = reverse ? 163 : 17;
  const aside = reverse ? 278 : -104;
  const hands = (deg) => [at(pivots[0], deg, reach), at(pivots[1], -deg, reach)];
  const levers = (deg) => hands(deg).map((hand, i) => [red(5, pivots[i], hand), redDot(hand, 7.5)]);
  const arms = (deg, outline) => hands(deg).map((hand, i) => {
    const [mid, end] = joint(shoulders[i], hand, SIZE.upper, SIZE.fore, (i ? 1 : -1) * face);
    return [outline ? gap(14.5, shoulders[i], mid, end) : null, ink(10, shoulders[i], mid), ink(9, mid, end), inkDot(end, 5.5)];
  });
  const nose = x + face * 13;
  const from = reverse ? forward : aside;
  const to = reverse ? aside : forward;
  return [
    h('rect', { class: 'art__tower', ...box(26, y - 52, 30, 104, 4) }),
    frame(5, [56, y], [padX, y]),
    frame(5, pivots[0], pivots[1]),
    h('rect', { class: 'art__seat', ...box(x - 21, y - 23, 46, 46, 10) }),
    // бёдра и стопы сидящего: они ниже рук, поэтому бледнее
    h('g', { class: 'art__below' }, [-1, 1].map((sign) => [
      ink(9, [x + face * 58, y + sign * 16], [x + face * 74, y + sign * 17]),
      ink(16, [x + face * 8, y + sign * 13], [x + face * 58, y + sign * 15]),
    ])),
    pad(10, [padX, y - 16], [padX, y + 16]),
    ghost(levers(aside), arms(aside, false)),
    ink(26, [x, y - 22], [x, y + 22]),
    levers(forward),
    arms(forward, true),
    h('circle', { class: 'art__head', 'stroke-width': 2.5, ...circle([x + face * 2, y], 13) }),
    h('path', { class: 'art__fill-body', d: `${line([[nose, y - 5], [nose, y + 5], [nose + face * 8, y]])}Z` }),
    redDot(pivots[0], 4.5),
    redDot(pivots[1], 4.5),
    arcArrow(pivots[0], reach + 17, from + 8, to - 10),
    arcArrow(pivots[1], reach + 17, -from - 8, -to + 10),
  ];
}

/** Разведение рук в стороны стоя: вид спереди, подушки рычагов лежат на руках снаружи, у локтей. */
function lateralRaise() {
  const k = 0.94;
  const mid = 160;
  const feet = 206;
  const hipY = feet - 8 - (SIZE.thigh + SIZE.shin) * k;
  const shoulderY = hipY - SIZE.torso * k + 4;
  const shoulders = [[mid - 24, shoulderY], [mid + 24, shoulderY]];
  const armAt = (i, deg) => {
    const out = i ? 180 - deg : deg;
    return {
      out,
      elbow: at(shoulders[i], out, SIZE.upper * k + 4),
      cushion: at(at(shoulders[i], out, SIZE.upper * k - 5), out + (i ? -90 : 90), 11.5),
    };
  };
  const arms = (deg) => [0, 1].map((i) => {
    const a = armAt(i, deg);
    return [ink(10.5, shoulders[i], a.elbow), inkDot(a.elbow, 7)];
  });
  const pivot = (i) => add(shoulders[i], i ? -5 : 5, -5);
  const levers = (deg) => [0, 1].map((i) => {
    const a = armAt(i, deg);
    return [red(5, pivot(i), at(a.cushion, a.out, -20), a.cushion), red(9, at(a.cushion, a.out, -9), at(a.cushion, a.out, 9))];
  });
  const from = 101;
  const to = 176;
  const body = [[mid - 19, shoulderY + 1], [mid + 19, shoulderY + 1], [mid + 12, hipY + 2], [mid - 12, hipY + 2]];
  return [
    floor(),
    h('rect', { class: 'art__tower', ...box(mid - 30, 14, 60, FLOOR - 15, 4) }),
    frame(5, [mid - 60, 219], [mid + 60, 219]),
    frame(9, [mid - 52, feet + 6], [mid + 52, feet + 6]),
    ghost(levers(to), arms(to)),
    levers(from),
    ink(13, [mid - 9, hipY], [mid - 11, feet - 6]),
    ink(13, [mid + 9, hipY], [mid + 11, feet - 6]),
    ink(8, [mid - 11, feet - 3], [mid - 19, feet - 2]),
    ink(8, [mid + 11, feet - 3], [mid + 19, feet - 2]),
    h('path', { class: 'art__body art__fill-body', 'stroke-width': 11, d: `${line(body)}Z` }),
    inkDot([mid, shoulderY - SIZE.neck * k], SIZE.head * k),
    arms(from),
    redDot(pivot(0), 4.5),
    redDot(pivot(1), 4.5),
    arcArrow(shoulders[0], SIZE.upper * k + 27, from + 5, to - 3),
    arcArrow(shoulders[1], SIZE.upper * k + 27, 180 - from - 5, 180 - to + 3),
  ];
}

/* ------------------------------------------------------------------ */

const DRAW = {
  'seated-leg-press': seatedLegPress,
  'chest-press': chestPress,
  'shoulder-press': shoulderPress,
  'row-narrow': () => seatedRow(false),
  'row-wide': () => seatedRow(true),
  'leg-press': legPress45,
  'hack-press': hackPress,
  'leg-curl': kneelingLegCurl,
  'pec-fly': () => pecDeck(false),
  'reverse-fly': () => pecDeck(true),
  'lateral-raise': lateralRaise,
  treadmill,
};

export const ART_NAMES = Object.keys(DRAW);

/**
 * Рисунок упражнения.
 * @param {string} name одно из ART_NAMES
 * @param {string} label описание для экранного диктора
 */
export function art(name, label) {
  if (!Object.hasOwn(DRAW, name)) return null;
  return h('svg', { class: 'art', viewBox: `0 0 ${WIDTH} ${HEIGHT}`, role: 'img', 'aria-label': label, focusable: 'false' }, DRAW[name]());
}
