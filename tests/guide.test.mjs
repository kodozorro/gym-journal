// Справочник упражнений (кнопка «i»): по названиям из таблицы находятся фото тренажёра, рисунок и
// подсказки; файлы фотографий на месте; рисунки собираются без ошибок.

import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { ROOT } from './helpers.mjs';
import { PROGRAM } from '../tools/fixture.mjs';
import { appFiles } from '../tools/stamp.mjs';
import { LEGEND, PHOTO_DIR, PHOTO_SIZE, STRENGTH_RULE, guideArt, guideFor, guidePhotos, machineOf } from '../js/core/guide.js';
import { ART_NAMES, art } from '../js/ui/art.js';

const photo = (name) => ({ src: `${PHOTO_DIR}${name}.webp`, ...PHOTO_SIZE });

/** Упражнение учебной программы → [рисунок, фото]. Программа та же, что в tools/fixture.mjs. */
const EXPECTED = {
  'Жим ногами сидя': ['seated-leg-press', 'seated-leg-press'],
  'Жим от груди': ['chest-press', 'chest-press'],
  'Сгибание ног': ['leg-curl', 'leg-curl'],
  'Тяга сидя узким хватом': ['row-narrow', 'low-pulley'],
  'Тяга сидя широким хватом': ['row-wide', 'low-pulley'],
  'Жим вверх': ['shoulder-press', 'shoulder-press'],
  'Обратные разведения': ['reverse-fly', 'pec-deck'],
  'Сведение рук': ['pec-fly', 'pec-deck'],
  'Гакк-жим': ['hack-press', 'hack-press'],
  'Разведение рук в стороны': ['lateral-raise', 'lateral-raise'],
  'Жим ногами': ['leg-press', 'leg-press'],
  'Ходьба до и после силовой': ['treadmill', null],
  'Ходьба ровным темпом': ['treadmill', null],
  'Ходьба или интервалы': ['treadmill', null],
};

test('справочник: у каждого упражнения программы есть рисунок и подсказки, у силовых — фото тренажёра', () => {
  assert.deepEqual([...new Set(PROGRAM.map((line) => line[1]))].sort(), Object.keys(EXPECTED).sort(), 'проверены все упражнения программы');
  for (const [workout, exercise, machine] of PROGRAM) {
    const guide = guideFor({ exercise, machine });
    const [drawing, picture] = EXPECTED[exercise];
    assert.equal(guide.art, drawing, exercise);
    assert.deepEqual(guide.photo, picture ? photo(picture) : null, exercise);
    assert.equal(guide.machine, machine);
    assert.equal(guide.search, '', `${exercise}: фото есть или это дорожка, искать нечего`);
    assert.ok(guide.steps.length >= 3 && guide.steps.length <= 4, `${exercise}: три-четыре шага`);
    assert.ok(guide.muscles && guide.legend, `${exercise}: мышцы и пояснение к рисунку`);
    if (workout === 'Ходьба') {
      assert.equal(guide.rule, '', 'к ходьбе правило о запасе повторов не относится');
      assert.equal(guide.look, '');
    } else {
      assert.equal(guide.rule, STRENGTH_RULE);
      assert.ok(guide.look, `${exercise}: по чему узнать тренажёр`);
    }
    // подсказки написаны по-русски и без марок: латиницы в них нет
    for (const line of [guide.look, guide.view, guide.legend, guide.muscles, guide.rule, ...guide.steps]) {
      assert.ok(!/[A-Za-z]/.test(line), `${exercise}: «${line}»`);
      assert.ok(line === '' || /[.!]$/.test(line), `${exercise}: «${line}» — законченное предложение`);
    }
  }
});

test('справочник: пояснение к рисунку говорит, откуда смотрим, если не сбоку', () => {
  const view = (exercise) => guideFor({ exercise, machine: '' });
  assert.equal(view('Сведение рук').view, 'Вид сверху.');
  assert.equal(view('Обратные разведения').view, 'Вид сверху.');
  assert.equal(view('Разведение рук в стороны').view, 'Вид спереди.');
  assert.equal(view('Жим от груди').view, '');
  assert.equal(view('Жим от груди').legend, LEGEND);
  assert.notEqual(view('Ходьба ровным темпом').legend, LEGEND, 'у дорожки своё пояснение: про наклон');
});

test('справочник: тренажёр узнаётся по типу, какой бы ни была марка и как бы ни было набрано название', () => {
  const type = (name) => {
    const found = machineOf(name);
    return found ? [found.id, found.photo] : null;
  };
  assert.deepEqual(type('Acme Seated Leg Press'), ['seated-leg-press', 'seated-leg-press']);
  assert.deepEqual(type('ACME  POWER LEG PRESS Premium'), ['leg-press', 'leg-press']);
  assert.deepEqual(type('Acme Hack Press'), ['hack-press', 'hack-press']);
  assert.deepEqual(type('Acme Kneeling Leg Curl'), ['leg-curl', 'leg-curl']);
  assert.deepEqual(type('Acme Chest Press (Rotary)'), ['chest-press', 'chest-press']);
  assert.deepEqual(type('Acme Adjustable Low Pulley'), ['low-pulley', 'low-pulley']);
  assert.deepEqual(type('Acme Shoulder Press'), ['shoulder-press', 'shoulder-press']);
  assert.deepEqual(type('Acme Standing Lateral Raise'), ['lateral-raise', 'lateral-raise']);
  assert.deepEqual(type('  беговая   дорожка '), ['treadmill', null]);
  // сведение и обратные разведения в одном тренажёре — есть фото; тренажёр только под сведение — другой, фото нет
  assert.deepEqual(type('Acme Pec Dec Fly (With Reverse)'), ['pec-deck', 'pec-deck']);
  assert.deepEqual(type('Acme Rear Delt / Pec Deck'), ['pec-deck', 'pec-deck']);
  assert.deepEqual(type('Acme Pec Dec Fly'), ['pec-deck', null]);
  // незнакомое и пустое
  assert.equal(type('Smith Machine'), null);
  assert.equal(type('Leg Extension'), null, 'разгибание ног — не сгибание и не жим');
  assert.equal(type(''), null);
  assert.equal(type(undefined), null);
});

test('справочник: на одном тренажёре два упражнения различаются по названию', () => {
  const on = (machine, exercise) => guideFor({ exercise, machine }).art;
  assert.equal(on('Acme Pec Dec Fly (With Reverse)', 'Сведение рук'), 'pec-fly');
  assert.equal(on('Acme Pec Dec Fly (With Reverse)', 'Обратные разведения'), 'reverse-fly');
  // тренажёр только под сведение: рисунок тот же, а фото другое, и в приложении его нет
  const plain = guideFor({ exercise: 'Сведение рук', machine: 'Acme Pec Dec Fly' });
  assert.deepEqual([plain.art, plain.photo, plain.look], ['pec-fly', null, '']);
  assert.equal(new URL(plain.search).searchParams.get('q'), 'Acme Pec Dec Fly');
  assert.equal(on('Acme Adjustable Low Pulley', 'Тяга сидя широким хватом'), 'row-wide');
  assert.equal(on('Acme Adjustable Low Pulley', 'Тяга сидя узким хватом'), 'row-narrow');
  assert.equal(on('Acme Adjustable Low Pulley', 'Тяга к поясу'), 'row-narrow');

  // незнакомое упражнение на знакомом тренажёре: фото есть, чужой рисунок не подставляется
  const other = guideFor({ exercise: 'Что-то новое', machine: 'Acme Pec Dec Fly (With Reverse)' });
  assert.deepEqual(other.photo, photo('pec-deck'));
  assert.ok(other.look);
  assert.deepEqual([other.art, other.muscles, other.steps, other.rule, other.legend, other.search], ['', '', [], '', '', '']);
});

test('справочник: если тренажёр в таблице не указан, упражнение узнаётся по названию, фото нет', () => {
  for (const [exercise, [drawing]] of Object.entries(EXPECTED)) {
    for (const machine of ['', '   ', undefined]) {
      const guide = guideFor({ exercise, machine });
      assert.equal(guide.art, drawing, exercise);
      assert.equal(guide.photo, null);
      assert.equal(guide.search, '');
      assert.equal(guide.machine, '');
    }
  }
  assert.equal(guideFor({ exercise: '  ЖИМ   ВВЕРХ ' }).art, 'shoulder-press', 'регистр и пробелы не мешают');
  assert.equal(guideFor({ exercise: 'Приседания' }).art, '');
});

test('справочник: для незнакомого тренажёра рисунка нет, фото предлагается найти по названию', () => {
  const guide = guideFor({ exercise: 'Жим от груди', machine: ' Smith & Wesson #5 ' });
  assert.equal(guide.machine, 'Smith & Wesson #5');
  assert.deepEqual([guide.photo, guide.look, guide.art, guide.muscles, guide.steps, guide.rule], [null, '', '', '', [], '']);
  const url = new URL(guide.search);
  assert.equal(`${url.origin}${url.pathname}`, 'https://www.google.com/search');
  assert.equal(url.searchParams.get('q'), 'Smith & Wesson #5', 'название уходит в запрос целиком и не ломает адрес');
  assert.equal(url.searchParams.get('tbm'), 'isch');

  for (const empty of [null, undefined, {}, { exercise: '', machine: '' }]) {
    const none = guideFor(empty);
    assert.deepEqual([none.machine, none.photo, none.art, none.steps, none.search], ['', null, '', [], '']);
  }
});

test('справочник: подсказки нельзя испортить снаружи', () => {
  const first = guideFor({ exercise: 'Гакк-жим', machine: '' });
  first.steps.push('лишнее');
  assert.equal(guideFor({ exercise: 'Гакк-жим', machine: '' }).steps.includes('лишнее'), false);
});

/* ------------------------------------------------------------------ */
/* Фотографии                                                          */
/* ------------------------------------------------------------------ */

/** Размер картинки WebP из её заголовка. */
function webpSize(bytes) {
  assert.equal(bytes.subarray(0, 4).toString('latin1'), 'RIFF');
  assert.equal(bytes.subarray(8, 12).toString('latin1'), 'WEBP');
  const kind = bytes.subarray(12, 16).toString('latin1');
  assert.equal(kind, 'VP8 ', 'обычный WebP с потерями, без прозрачности и вложенных данных');
  return { width: bytes.readUInt16LE(26) & 0x3fff, height: bytes.readUInt16LE(28) & 0x3fff };
}

test('фото тренажёров: файлы на месте, одного размера, без лишнего и сохраняются для работы без сети', () => {
  const dir = path.join(ROOT, PHOTO_DIR);
  const onDisk = fs.readdirSync(dir).map((name) => `${PHOTO_DIR}${name}`).sort();
  const wanted = guidePhotos().sort();
  assert.ok(wanted.length >= 9);
  assert.deepEqual(onDisk, wanted, 'в папке лежат ровно те фото, на которые ссылается справочник');
  const cached = new Set(appFiles());
  let total = 0;
  for (const rel of wanted) {
    // названия файлов — тип тренажёра, без марок и номеров
    assert.match(rel, /^img\/machines\/[a-z]+(?:-[a-z]+)*\.webp$/);
    assert.ok(cached.has(rel), `${rel} нет в списке файлов для работы без сети`);
    const bytes = fs.readFileSync(path.join(ROOT, rel));
    assert.deepEqual(webpSize(bytes), { ...PHOTO_SIZE }, rel);
    assert.equal(bytes.readUInt32LE(4) + 8, bytes.length, `${rel}: в файле нет ничего, кроме картинки`);
    total += bytes.length;
  }
  assert.ok(total < 300 * 1024, `все фото вместе весят ${Math.round(total / 1024)} КБ: приложение скачивает их при установке`);
});

/* ------------------------------------------------------------------ */
/* Рисунки                                                             */
/* ------------------------------------------------------------------ */

/** Все узлы рисунка, кроме текстовых. */
function nodes(root) {
  const out = [];
  const visit = (node) => {
    if (!node || node.text !== undefined) return;
    out.push(node);
    node.children.forEach(visit);
  };
  visit(root);
  return out;
}

test('рисунки: у каждого упражнения справочника свой рисунок, лишних нет', () => {
  assert.deepEqual(guideArt().sort(), [...ART_NAMES].sort());
  assert.equal(art('нет такого', 'подпись'), null);
  assert.equal(art('constructor', 'подпись'), null, 'имя рисунка не достаёт ничего постороннего');
});

test('рисунки: собираются без ошибок, координаты — числа в пределах холста, цвет задаётся только классом', () => {
  const NUMBERS = /-?\d+(?:\.\d+)?(?:e-?\d+)?/g;
  const COLOR = new Set(['fill', 'stroke', 'style', 'color', 'opacity']);
  const seen = new Set();
  for (const name of ART_NAMES) {
    const svg = art(name, `Рисунок: ${name}`);
    assert.equal(svg.tag, 'svg');
    assert.equal(svg.props.viewBox, '0 0 320 240');
    assert.equal(svg.props.role, 'img');
    assert.equal(svg.props['aria-label'], `Рисунок: ${name}`);
    const all = nodes(svg);
    assert.ok(all.length >= 12, `${name}: в рисунке ${all.length} узлов`);
    assert.ok(all.some((node) => /art__arrow/.test(node.props.class || '')), `${name}: есть стрелка усилия`);
    assert.ok(all.some((node) => /art__body|art__head/.test(node.props.class || '')), `${name}: есть фигура человека`);
    for (const node of all) {
      for (const [key, value] of Object.entries(node.props)) {
        const where = `${name}: <${node.tag} ${key}="${value}">`;
        assert.ok(!COLOR.has(key), `${where} — цвет и прозрачность задаёт css/app.css, иначе сломается тёмная тема`);
        assert.ok(!/NaN|undefined|null|Infinity/.test(String(value)), where);
        if (key === 'class' || key === 'viewBox' || key === 'aria-label' || key === 'role' || key === 'focusable') continue;
        // всё остальное — геометрия: числа должны укладываться в холст с небольшим запасом
        for (const number of String(value).match(NUMBERS) || []) {
          assert.ok(Math.abs(Number(number)) <= 420, `${where} — число ${number} далеко за холстом`);
        }
      }
    }
    // два разных упражнения не должны получить один и тот же рисунок
    const print = JSON.stringify(all.map((node) => [node.tag, node.props.d, node.props.cx, node.props.cy, node.props.x, node.props.y]));
    assert.ok(!seen.has(print), `${name}: рисунок повторяет другой`);
    seen.add(print);
  }
});
