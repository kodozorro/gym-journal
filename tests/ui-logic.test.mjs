// Логика, на которую опирается экран: цифровая клавиатура, шкалы графиков, настройки, адрес экрана.

import test from 'node:test';
import assert from 'node:assert/strict';
import { fieldError, fieldValue, makeField, pressKey } from '../js/core/keypad.js';
import { linear, niceScale, niceStep } from '../js/core/scale.js';
import { createStorage } from '../js/data/storage.js';
import { createStore, DEFAULTS, normalizeSettings } from '../js/data/store.js';
import { memoryBackend } from './helpers.mjs';

const type = (field, keys) => keys.reduce((f, key) => pressKey(f, key), field);

test('клавиатура: первая цифра заменяет подставленное значение', () => {
  const field = makeField({ name: 'weight', value: 42.5, max: 1000 });
  assert.equal(field.text, '42,5');
  assert.equal(field.fresh, true);
  const next = pressKey(field, '4');
  assert.equal(next.text, '4');
  assert.equal(next.fresh, false);
  assert.equal(fieldValue(type(field, ['4', '5'])), 45);
});

test('клавиатура: стирание подставленного значения очищает поле целиком', () => {
  const field = pressKey(makeField({ name: 'weight', value: 42.5, max: 1000 }), 'back');
  assert.equal(field.text, '');
  assert.equal(fieldValue(field), null);
});

test('клавиатура: дробные числа через запятую, не больше двух знаков', () => {
  const empty = makeField({ name: 'weight', max: 1000 });
  assert.equal(fieldValue(type(empty, ['4', '2', ',', '5'])), 42.5);
  assert.equal(type(empty, [',', '5']).text, '0,5');
  assert.equal(type(empty, ['1', ',', '2', '5', '9']).text, '1,25', 'третий знак после запятой не принимается');
  assert.equal(type(empty, ['1', ',', ',', '2']).text, '1,2', 'вторая запятая не принимается');
  assert.equal(type(empty, ['0', '7']).text, '7', 'ведущий ноль заменяется');
  assert.equal(fieldValue(type(empty, ['1', '2', ','])), 12, 'запятая в конце не мешает');
});

test('клавиатура: повторы — только целые, длина ограничена', () => {
  const reps = makeField({ name: 'reps', integer: true, max: 500, whole: 3 });
  assert.equal(type(reps, ['1', ',', '2']).text, '12', 'запятая в целом поле не ставится');
  assert.equal(type(reps, ['1', '2', '3', '4']).text, '123', 'четвёртая цифра не принимается');
  assert.equal(fieldError(type(reps, ['9', '9', '9'])), 'Не больше 500.');
  assert.equal(fieldError(type(reps, ['1', '2'])), '');
});

test('клавиатура: значение из таблицы показывается как есть', () => {
  assert.equal(makeField({ name: 'km', value: 3.25, max: 200 }).text, '3,25');
  assert.equal(makeField({ name: 'min', value: 38, max: 1440, digits: 1 }).text, '38');
  assert.equal(makeField({ name: 'reps', value: 12, integer: true, max: 500 }).text, '12');
  assert.equal(makeField({ name: 'km', value: null, max: 200 }).fresh, false);
});

test('шкала: круглые деления', () => {
  assert.equal(niceStep(10, 4), 2.5);
  assert.equal(niceStep(3, 4), 1);
  assert.equal(niceStep(0.9, 4), 0.25);
  assert.deepEqual(niceScale(40, 42.5).ticks, [40, 41, 42, 43]);
  assert.deepEqual(niceScale(0, 17, { fromZero: true }).ticks, [0, 5, 10, 15, 20]);
});

test('шкала: одна точка и нули не ломают ось', () => {
  const one = niceScale(40, 40);
  assert.ok(one.lo < 40 && one.hi > 40, 'точка лежит внутри оси');
  assert.ok(one.ticks.length >= 2);
  const zero = niceScale(0, 0, { fromZero: true });
  assert.equal(zero.lo, 0);
  assert.ok(zero.hi > 0);
  assert.ok(niceScale(0.5, 0.5).lo >= 0, 'ось веса не уходит ниже нуля');
});

test('шкала: значения переводятся в пиксели линейно', () => {
  const y = linear(0, 20, 200, 0);
  assert.equal(y(0), 200);
  assert.equal(y(10), 100);
  assert.equal(y(20), 0);
  assert.equal(linear(5, 5, 0, 100)(5), 50, 'вырожденный отрезок — середина');
});

test('настройки: значения по умолчанию и защита от мусора в хранилище', () => {
  assert.deepEqual(normalizeSettings(null), { ...DEFAULTS, steps: {} });
  const messy = normalizeSettings({
    restSec: 5000, theme: 'pink', wakeLock: 'always', sound: 'yes', defaultStep: -1,
    steps: { 'Жим ногами': 5, '': 2, 'Жим вверх': 'много' }, chartExercise: 42,
  });
  assert.equal(messy.restSec, 300, 'отдых ограничен сверху');
  assert.equal(messy.theme, 'auto');
  assert.equal(messy.wakeLock, 'rest');
  assert.equal(messy.sound, true);
  assert.equal(messy.defaultStep, 2.5);
  assert.deepEqual(messy.steps, { 'Жим ногами': 5 });
  assert.equal(messy.chartExercise, '');
});

test('настройки: свой шаг веса у упражнения переживает перезапуск', () => {
  const backend = memoryBackend();
  let changes = 0;
  const store = createStore(createStorage(backend), () => {
    changes += 1;
  });
  assert.equal(store.stepFor('Жим ногами'), 2.5);
  store.setStep('Жим ногами', 5);
  store.set({ restSec: 60, theme: 'dark' });
  assert.equal(changes, 2);

  const again = createStore(createStorage(backend));
  assert.equal(again.stepFor('Жим ногами'), 5);
  assert.equal(again.stepFor('Жим вверх'), 2.5, 'у остальных — шаг по умолчанию');
  assert.equal(again.get().restSec, 60);
  assert.equal(again.get().theme, 'dark');

  again.setStep('Жим ногами', 2.5);
  assert.deepEqual(again.get().steps, {}, 'шаг, равный общему, не хранится отдельно');
});
