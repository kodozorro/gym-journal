// Тесты очереди неотправленных записей и таймера отдыха.

import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
  emptyOutbox, normalizeOutbox, queuePatch, buildPush, ackPush, applyOutbox, pendingCount, retryFailed, dropFailed,
} from '../js/core/outbox.js';
import {
  startRest, restLeft, restOver, restOvertime, restProgress, extendRest, validRest, formatClock,
} from '../js/core/timer.js';

const hack = { date: '2026-11-11', workout: 'Силовая B', exercise: 'Гакк-жим', plan: '2 × 12–15', weight: null, sets: [null, null, null], km: null, min: null, note: '' };
const fly = { ...hack, exercise: 'Сведение рук' };
const walk = { date: '2026-11-11', workout: 'Ходьба', exercise: 'Ходьба до и после силовой', plan: '3 км', weight: null, sets: [null, null, null], km: null, min: null, note: '' };

test('очередь: правки одной строки сливаются в одну запись', () => {
  let box = emptyOutbox();
  box = queuePatch(box, hack, { weight: 40 }, 1000);
  box = queuePatch(box, hack, { sets: [15] }, 2000);
  box = queuePatch(box, hack, { sets: [15, 14, null] }, 3000);
  box = queuePatch(box, fly, { weight: 25, sets: [15, null, null] }, 4000);
  assert.equal(pendingCount(box), 2);
  const { entries, sent } = buildPush(box);
  assert.deepEqual(entries, [
    { date: '2026-11-11', exercise: 'Гакк-жим', weight: 40, sets: [15, 14, null] },
    { date: '2026-11-11', exercise: 'Сведение рук', weight: 25, sets: [15, null, null] },
  ]);
  assert.deepEqual(sent.map((s) => s.key), ['2026-11-11|Гакк-жим|0', '2026-11-11|Сведение рук|0']);
  assert.equal(box.items['2026-11-11|Гакк-жим|0'].at, 3000);
});

test('очередь: в запрос попадают только поля, которые меняли', () => {
  let box = queuePatch(emptyOutbox(), hack, { note: 'сиденье 4' });
  box = queuePatch(box, walk, { km: 1 });
  box = queuePatch(box, walk, { min: 12.5 });
  const { entries } = buildPush(box);
  assert.deepEqual(entries[0], { date: '2026-11-11', exercise: 'Гакк-жим', note: 'сиденье 4' });
  assert.deepEqual(entries[1], { date: '2026-11-11', exercise: 'Ходьба до и после силовой', km: 1, min: 12.5 });
  assert.equal(queuePatch(box, hack, {}), box, 'пустая правка ничего не меняет');
  assert.equal(queuePatch(box, hack, { unknown: 1 }), box);
});

test('очередь: мусор в полях превращается в пустые значения', () => {
  const box = queuePatch(emptyOutbox(), hack, { weight: '40', sets: [15, 'x', NaN, 9], note: 5 });
  assert.deepEqual(buildPush(box).entries[0], { date: '2026-11-11', exercise: 'Гакк-жим', weight: null, sets: [15, null, null], note: '' });
});

test('очередь: номер строки-повтора передаётся, только когда он не нулевой', () => {
  const box = queuePatch(queuePatch(emptyOutbox(), walk, { km: 3 }), { ...walk, occ: 1 }, { km: 1.5 });
  const { entries } = buildPush(box);
  assert.equal('occ' in entries[0], false);
  assert.equal(entries[1].occ, 1);
  assert.equal(pendingCount(box), 2);
});

test('очередь: принятые записи уходят, отклонённые переезжают в список ошибок', () => {
  let box = queuePatch(emptyOutbox(), hack, { weight: 40 }, 1);
  box = queuePatch(box, fly, { weight: 25 }, 2);
  box = queuePatch(box, walk, { km: 3 }, 3);
  const { sent } = buildPush(box);
  const next = ackPush(box, sent, [
    { status: 'written' },
    { status: 'not_found', reason: 'В журнале нет строки с такой датой и упражнением.' },
    { status: 'unchanged' },
  ], 5000);
  assert.equal(pendingCount(next), 0);
  assert.equal(next.failed.length, 1);
  assert.equal(next.failed[0].exercise, 'Сведение рук');
  assert.equal(next.failed[0].status, 'not_found');
  assert.match(next.failed[0].reason, /нет строки/);
  assert.equal(next.failed[0].failedAt, 5000);
  assert.deepEqual(next.failed[0].fields, { weight: 25 });
  assert.equal(next.seq, box.seq, 'счётчик версий не откатывается');
});

test('очередь: правка во время отправки не теряется', () => {
  let box = queuePatch(emptyOutbox(), hack, { weight: 40, sets: [15, null, null] });
  const { sent } = buildPush(box);
  box = queuePatch(box, hack, { sets: [15, 14, null] }); // пользователь записал второй подход, пока запрос в пути
  const next = ackPush(box, sent, [{ status: 'written' }]);
  assert.equal(pendingCount(next), 1);
  assert.deepEqual(buildPush(next).entries[0].sets, [15, 14, null]);
  // следующая отправка подтверждает уже новую версию
  const done = ackPush(next, buildPush(next).sent, [{ status: 'written' }]);
  assert.equal(pendingCount(done), 0);
});

test('очередь: ответ не той длины не принимается', () => {
  const box = queuePatch(emptyOutbox(), hack, { weight: 40 });
  const { sent } = buildPush(box);
  assert.throws(() => ackPush(box, sent, []));
  assert.throws(() => ackPush(box, sent, undefined));
});

test('очередь: неотправленные правки видны поверх данных таблицы', () => {
  const journal = [hack, fly, walk];
  assert.equal(applyOutbox(journal, emptyOutbox()), journal, 'без очереди журнал тот же самый');
  let box = queuePatch(emptyOutbox(), hack, { weight: 40, sets: [15, null, null] });
  box = queuePatch(box, { date: '2030-01-01', exercise: 'Нет такой строки' }, { weight: 1 });
  const view = applyOutbox(journal, box);
  assert.equal(view[0].weight, 40);
  assert.deepEqual(view[0].sets, [15, null, null]);
  assert.equal(view[0].pending, true);
  assert.equal(view[0].note, '', 'поля вне правки берутся из таблицы');
  assert.equal(view[1], fly);
  assert.equal(hack.weight, null, 'исходные строки не тронуты');
  view[0].sets[1] = 99;
  assert.deepEqual(box.items['2026-11-11|Гакк-жим|0'].fields.sets, [15, null, null]);
});

test('очередь: отклонённую запись можно повторить или убрать', () => {
  let box = queuePatch(emptyOutbox(), hack, { weight: 40 });
  box = ackPush(box, buildPush(box).sent, [{ status: 'rejected', reason: 'Вес должен быть числом от 0 до 1000.' }]);
  assert.equal(box.failed.length, 1);
  const retried = retryFailed(box, 0);
  assert.equal(retried.failed.length, 0);
  assert.deepEqual(buildPush(retried).entries, [{ date: '2026-11-11', exercise: 'Гакк-жим', weight: 40 }]);
  assert.equal(dropFailed(box, 0).failed.length, 0);
  assert.equal(retryFailed(box, 5), box);
  // новая правка той же строки сама убирает старую ошибку
  assert.equal(queuePatch(box, hack, { weight: 42.5 }).failed.length, 0);
});

test('очередь: повтор отклонённой записи не затирает более свежую правку', () => {
  let box = queuePatch(emptyOutbox(), hack, { weight: 40, note: 'старая' });
  box = ackPush(box, buildPush(box).sent, [{ status: 'rejected' }]);
  box = { ...box, items: queuePatch(emptyOutbox(), hack, { weight: 45 }).items, seq: 10 };
  const retried = retryFailed(box, 0);
  assert.deepEqual(buildPush(retried).entries[0], { date: '2026-11-11', exercise: 'Гакк-жим', weight: 45, note: 'старая' });
});

test('очередь: восстановление из хранилища отбрасывает мусор', () => {
  assert.deepEqual(normalizeOutbox(null), emptyOutbox());
  assert.deepEqual(normalizeOutbox('строка'), emptyOutbox());
  assert.deepEqual(normalizeOutbox({ items: 5, failed: 'x' }), emptyOutbox());
  let box = queuePatch(emptyOutbox(), hack, { weight: 40, sets: [15, 14, null] }, 100);
  box = queuePatch(box, { ...walk, occ: 1 }, { km: 3 }, 200);
  box = ackPush(box, [buildPush(box).sent[1]], [{ status: 'not_found', reason: 'нет строки' }], 300);
  const restored = normalizeOutbox(JSON.parse(JSON.stringify(box)));
  assert.deepEqual(restored, box);
  const dirty = normalizeOutbox({
    seq: 'x',
    items: { a: null, b: { date: 1 }, c: { date: '2026-11-11', exercise: 'Гакк-жим', fields: { weight: '40' }, rev: 7 } },
    failed: [null, { date: '2026-11-11', exercise: 'Сведение рук', fields: {} }],
  });
  assert.equal(pendingCount(dirty), 1);
  assert.equal(dirty.seq, 7);
  assert.deepEqual(dirty.items['2026-11-11|Гакк-жим|0'].fields, { weight: null });
  assert.equal(dirty.failed.length, 1);
  assert.equal(dirty.failed[0].status, 'rejected');
});

test('очередь: большой хвост уходит частями в порядке появления', () => {
  let box = emptyOutbox();
  for (let i = 0; i < 7; i += 1) box = queuePatch(box, { date: '2026-11-11', exercise: `Упражнение ${i}` }, { weight: i });
  const first = buildPush(box, 3);
  assert.deepEqual(first.entries.map((e) => e.weight), [0, 1, 2]);
  box = ackPush(box, first.sent, first.entries.map(() => ({ status: 'written' })));
  assert.deepEqual(buildPush(box, 3).entries.map((e) => e.weight), [3, 4, 5]);
});

test('таймер: остаток считается по часам', () => {
  const t0 = 1_800_000_000_000;
  const timer = startRest(t0, 90);
  assert.equal(restLeft(timer, t0), 90);
  assert.equal(restLeft(timer, t0 + 500), 90, 'остаток округляется вверх: 1:30 держится целую секунду');
  assert.equal(restLeft(timer, t0 + 1000), 89);
  assert.equal(restLeft(timer, t0 + 89_001), 1);
  assert.equal(restLeft(timer, t0 + 90_000), 0);
  assert.equal(restOver(timer, t0 + 89_999), false);
  assert.equal(restOver(timer, t0 + 90_000), true);
  // телефон заблокировали на три минуты: после возврата таймер уже истёк, а не «продолжает тикать»
  assert.equal(restLeft(timer, t0 + 180_000), 0);
  assert.equal(restOvertime(timer, t0 + 180_000), 90);
  assert.equal(restOvertime(timer, t0 + 10_000), 0);
  assert.equal(restProgress(timer, t0), 0);
  assert.equal(restProgress(timer, t0 + 45_000), 0.5);
  assert.equal(restProgress(timer, t0 + 200_000), 1);
});

test('таймер: добавление времени', () => {
  const t0 = 1_800_000_000_000;
  const timer = startRest(t0, 90);
  const more = extendRest(timer, t0 + 60_000, 30);
  assert.equal(restLeft(more, t0 + 60_000), 60);
  assert.equal(more.total, 120);
  const late = extendRest(timer, t0 + 100_000, 30);
  assert.equal(restLeft(late, t0 + 100_000), 30, 'после окончания отсчёт идёт от текущего момента');
  assert.equal(restProgress(late, t0 + 115_000), 0.5);
});

test('таймер: проверка сохранённого значения и вывод времени', () => {
  assert.equal(validRest(startRest(1000, 90)), true);
  assert.equal(validRest(null), false);
  assert.equal(validRest({ startedAt: 5, endsAt: 'x', total: 3 }), false);
  assert.equal(validRest({ startedAt: 10, endsAt: 5, total: 3 }), false);
  assert.equal(formatClock(90), '1:30');
  assert.equal(formatClock(5), '0:05');
  assert.equal(formatClock(0), '0:00');
  assert.equal(formatClock(720), '12:00');
  assert.equal(formatClock(-3), '0:00');
});
