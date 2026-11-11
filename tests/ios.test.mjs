// Приложение на Swift (папка ios) берёт рисунки, значки, учебный журнал и эталоны для своих
// тестов из кода веб-приложения. Здесь проверяется, что эти данные не отстали от кода и что
// перевод рисунков в простые команды пути работает. Сам код на Swift проверяет `swift test`
// на компьютере с Xcode: см. ios/README.md.

import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { ROOT } from './helpers.mjs';
import { outputs, stale } from '../ios/tools/generate.mjs';
import { circlePath, rectPath, simplify, tokenize, toPathData } from '../ios/tools/svgpath.mjs';
import { iconNames } from '../ios/tools/art.mjs';
import { iconSvg } from '../ios/tools/icon.mjs';
import { ART_NAMES } from '../js/ui/art.js';
import { guideArt, guidePhotos } from '../js/core/guide.js';

const read = (rel) => fs.readFileSync(path.join(ROOT, rel), 'utf8');
const json = (rel) => JSON.parse(read(rel));

test('данные для приложения на Swift соответствуют коду (node ios/tools/generate.mjs)', () => {
  assert.deepEqual(
    stale(),
    [],
    'после правки js/, apps-script/Code.gs или tools/fixture.mjs запустите node ios/tools/generate.mjs',
  );
});

test('скрипт делает ровно те файлы, которые читает приложение на Swift', () => {
  assert.deepEqual(Object.keys(outputs()).sort(), [
    'ios/App/Resources/art.json',
    'ios/App/Resources/icons.json',
    'ios/Core/Sources/GymJournalCore/Resources/demo.json',
    'ios/Core/Tests/GymJournalCoreTests/Fixtures/bridge.json',
    'ios/Core/Tests/GymJournalCoreTests/Fixtures/golden.json',
  ]);
});

test('в приложение на Swift попали все рисунки упражнений', () => {
  const art = json('ios/App/Resources/art.json');
  assert.equal(art.width, 320);
  assert.equal(art.height, 240);
  assert.deepEqual(Object.keys(art.items).sort(), [...ART_NAMES].sort());
  // справочник не ссылается на рисунок, которого нет
  for (const name of guideArt()) assert.ok(art.items[name], `нет рисунка ${name}`);

  const check = (node, where) => {
    assert.ok(Array.isArray(node.c), `${where}: нет списка ролей`);
    if (node.ch) {
      assert.ok(node.ch.length > 0, `${where}: пустая группа`);
      node.ch.forEach((child, index) => check(child, `${where}/${index}`));
      return;
    }
    assert.ok(node.c.length > 0, `${where}: фигура без роли останется невидимой`);
    assert.match(node.o, /^M[MLCQZ]*$/, `${where}: путь начинается не с M`);
    const count = [...node.o].reduce((sum, op) => sum + { M: 2, L: 2, C: 6, Q: 4, Z: 0 }[op], 0);
    assert.equal(node.n.length, count, `${where}: чисел не столько, сколько нужно командам`);
    assert.ok(node.n.every(Number.isFinite), `${where}: не число в координатах`);
  };
  for (const [name, nodes] of Object.entries(art.items)) {
    assert.ok(nodes.length > 0, `рисунок ${name} пуст`);
    nodes.forEach((node, index) => check(node, `${name}/${index}`));
  }
});

test('в приложение на Swift попали все значки', () => {
  const icons = json('ios/App/Resources/icons.json');
  assert.equal(icons.size, 24);
  assert.equal(icons.stroke, 2);
  const names = iconNames(read('js/ui/icons.js'));
  assert.ok(names.length >= 20);
  assert.deepEqual(Object.keys(icons.items).sort(), [...names].sort());
  for (const [name, shapes] of Object.entries(icons.items)) {
    assert.ok(shapes.length > 0, `значок ${name} пуст`);
    for (const shape of shapes) assert.match(shape.o, /^M[MLCQZ]*$/, `значок ${name}`);
  }
});

test('роли фигур в рисунках известны приложению на Swift', () => {
  const art = json('ios/App/Resources/art.json');
  const used = new Set();
  const collect = (node) => {
    node.c.forEach((role) => used.add(role));
    (node.ch || []).forEach(collect);
  };
  Object.values(art.items).flat().forEach(collect);

  const source = read('ios/App/Sources/Views/ArtView.swift');
  const known = new Set([...source.matchAll(/case "([a-z-]+)"/g)].map((m) => m[1]));
  const unknown = [...used].filter((role) => !known.has(role)).sort();
  assert.deepEqual(unknown, [], 'добавьте роль в ArtView.swift: иначе фигура не нарисуется');
  // и в стилях веб-приложения роль описана: цвета Swift повторяют css/app.css
  const css = read('css/app.css');
  for (const role of used) assert.ok(css.includes(`.art__${role}`), `в css/app.css нет класса art__${role}`);
});

test('значки, которые называет код на Swift, есть в данных', () => {
  const icons = json('ios/App/Resources/icons.json');
  const missing = [];
  const walk = (dir) => {
    for (const entry of fs.readdirSync(path.join(ROOT, dir), { withFileTypes: true })) {
      const rel = `${dir}/${entry.name}`;
      if (entry.isDirectory()) walk(rel);
      else if (rel.endsWith('.swift')) {
        for (const m of read(rel).matchAll(/\bIcon\("([A-Za-z]+)"/g)) {
          if (!icons.items[m[1]]) missing.push(`${rel}: ${m[1]}`);
        }
      }
    }
  };
  walk('ios/App/Sources');
  walk('ios/Core/Sources');
  assert.deepEqual(missing, []);
});

test('цвета приложения на Swift те же, что в css/app.css, в обеих темах', () => {
  const css = read('css/app.css');
  const block = (from, to) => css.slice(css.indexOf(from), css.indexOf(to, css.indexOf(from)));
  const colors = (text) => Object.fromEntries([...text.matchAll(/--([a-z0-9-]+):\s*#([0-9a-f]{6});/g)].map((m) => [m[1], m[2]]));
  const light = colors(block(':root {', '}'));
  const dark = colors(block(":root[data-theme='dark'] {", '}'));
  assert.ok(Object.keys(light).length >= 20);

  const swift = read('ios/App/Sources/Theme/Theme.swift');
  const roles = [...swift.matchAll(/static let (\w+) = dynamic\(0x([0-9A-Fa-f]{6}), 0x([0-9A-Fa-f]{6})\)/g)];
  assert.equal(roles.length, Object.keys(light).length, 'в Theme.swift должны быть все цвета из :root');
  for (const [, name, lightHex, darkHex] of roles) {
    // surface2 → surface-2, okSoftInk → ok-soft-ink
    const role = name.replace(/([A-Z0-9])/g, '-$1').toLowerCase();
    assert.equal(lightHex.toLowerCase(), light[role], `светлая тема, ${role}`);
    assert.equal(darkHex.toLowerCase(), dark[role], `тёмная тема, ${role}`);
  }
});

test('у приложения для iPhone есть значок, права на «Здоровье» и пояснения к ним', () => {
  const plist = read('ios/App/Info.plist');
  for (const key of ['NSHealthShareUsageDescription', 'NSHealthUpdateUsageDescription', 'CFBundleDisplayName']) {
    assert.match(plist, new RegExp(`<key>${key}</key>\\s*<string>[^<]{3,}</string>`), key);
  }
  assert.match(read('ios/App/GymJournal.entitlements'), /<key>com\.apple\.developer\.healthkit<\/key>\s*<true\/>/);

  const project = read('ios/project.yml');
  for (const file of ['App/Info.plist', 'App/GymJournal.entitlements', 'Config/Shared.xcconfig']) {
    assert.ok(project.includes(file), `project.yml не упоминает ${file}`);
    assert.ok(fs.existsSync(path.join(ROOT, 'ios', file)), `нет файла ios/${file}`);
  }
  // команда разработчика у каждого своя: в общих настройках её нет
  assert.doesNotMatch(read('ios/Config/Shared.xcconfig'), /^\s*DEVELOPMENT_TEAM/m);
  assert.doesNotMatch(project, /DEVELOPMENT_TEAM/);

  for (const dir of ['ios/App/Resources', 'ios/Watch/Resources']) {
    const set = `${dir}/Assets.xcassets/AppIcon.appiconset`;
    const { images } = json(`${set}/Contents.json`);
    assert.equal(images.length, 1);
    assert.equal(images[0].size, '1024x1024');
    const png = fs.readFileSync(path.join(ROOT, set, images[0].filename));
    assert.equal(png.readUInt32BE(16), 1024, `${set}: ширина значка`);
    assert.equal(png.readUInt32BE(20), 1024, `${set}: высота значка`);
    // значок приложения не бывает прозрачным: в заголовке PNG тип цвета 2 — RGB без альфа-канала
    assert.equal(png[25], 2, `${set}: значок с прозрачностью`);
  }
});

test('значок приложения на Swift рисуется из значка веб-приложения', () => {
  const source = read('icons/icon.svg');
  const full = iconSvg(source, 1);
  assert.match(full, /<rect width="512" height="512" fill="#256abf"\/>/);
  assert.ok(!full.includes('rx='), 'углы значка скругляет система');
  assert.ok(full.includes('M176 256h160'), 'гантель та же, что на значке веб-приложения');
  // на часах гантель меньше и стоит по центру
  assert.match(iconSvg(source, 0.5), /translate\(128\.00 128\.00\) scale\(0\.5\)/);
  assert.throws(() => iconSvg('<svg/>', 1), /устроен не так/);
});

test('фотографии тренажёров для приложения на Swift лежат в img/machines', () => {
  const golden = json('ios/Core/Tests/GymJournalCoreTests/Fixtures/golden.json');
  assert.equal(golden.guide.photos.length, guidePhotos().length);
  for (const name of golden.guide.photos) {
    assert.ok(fs.existsSync(path.join(ROOT, 'img/machines', `${name}.webp`)), `нет фото ${name}.webp`);
  }
});

test('учебный журнал для Swift — ответ скрипта с выдуманными числами', () => {
  const demo = json('ios/Core/Sources/GymJournalCore/Resources/demo.json');
  assert.equal(demo.ok, true);
  assert.equal(demo.api, 1);
  assert.equal(demo.start, '2026-11-09');
  assert.ok(demo.journal.length > 200);
  assert.ok(demo.journal.some((row) => row.weight !== null), 'в учебном журнале нет истории');
  for (const row of demo.journal) {
    assert.match(row.date, /^\d{4}-\d{2}-\d{2}$/);
    assert.equal(row.sets.length, 3);
    assert.equal(row.note, '', 'заметки в учебном журнале пустые');
  }
});

test('путь SVG переводится в простые команды', () => {
  // относительные команды становятся абсолютными, H и V — отрезками
  assert.deepEqual(simplify('M1 2l3 4h5v6z'), { o: 'MLLLZ', n: [1, 2, 4, 6, 9, 6, 9, 12] });
  assert.deepEqual(simplify('M10 10H20V20h-10Z'), { o: 'MLLLZ', n: [10, 10, 20, 10, 20, 20, 10, 20] });
  // после m без новой буквы идут отрезки
  assert.deepEqual(simplify('m5 5 5 0 0 5'), { o: 'MLL', n: [5, 5, 10, 5, 10, 10] });
  assert.deepEqual(simplify('M0 0c1 2 3 4 5 6q1 1 2 0'), { o: 'MCQ', n: [0, 0, 1, 2, 3, 4, 5, 6, 6, 7, 7, 6] });
  // числа можно писать вплотную
  assert.deepEqual(tokenize('M1-2.5.5,3e1'), [{ op: 'M', args: [1, -2.5] }, { op: 'L', args: [0.5, 30] }]);
  assert.equal(toPathData(simplify('M1 2l3 4h5v6z')), 'M1 2L4 6L9 6L9 12Z');
});

test('дуга становится кривыми и проходит через нужные точки', () => {
  // полуокружность радиуса 1 через верхнюю точку: две четверти
  const top = simplify('M0 0A1 1 0 0 1 2 0');
  assert.equal(top.o, 'MCC');
  assert.deepEqual(top.n.slice(6, 8), [1, -1]);
  assert.deepEqual(top.n.slice(-2), [2, 0]);
  // флаги дуги можно писать слитно: «01» — это два флага
  assert.deepEqual(simplify('M0 0a1 1 0 01 2 0'), top);
  // другой обход: через нижнюю точку
  assert.deepEqual(simplify('M0 0a1 1 0 1 0 2 0z').n.slice(6, 8), [1, 1]);
  // нулевой радиус — отрезок, совпавшие концы — ничего
  assert.deepEqual(simplify('M0 0A0 5 0 0 1 2 0'), { o: 'MC', n: [0, 0, 0, 0, 2, 0, 2, 0] });
  assert.deepEqual(simplify('M3 3A5 5 0 0 1 3 3'), { o: 'M', n: [3, 3] });
});

test('окружность и прямоугольник становятся путями', () => {
  const circle = circlePath(12, 12, 9);
  assert.equal(circle.o, 'MCCCCZ');
  assert.deepEqual(circle.n.slice(0, 2), [21, 12]);
  assert.deepEqual(circle.n.slice(6, 8), [12, 21]);
  assert.deepEqual(rectPath(2, 3, 10, 6, 0), { o: 'MLLLZ', n: [2, 3, 12, 3, 12, 9, 2, 9] });
  assert.equal(rectPath(2, 3, 10, 6, 2).o, 'MLCLCLCLCZ');
  // радиус не больше половины стороны
  assert.deepEqual(rectPath(0, 0, 4, 4, 9).n.slice(0, 2), [2, 0]);
});

test('то, чего перевод не умеет, останавливает скрипт, а не портит рисунок', () => {
  assert.throws(() => simplify('M0 0T5 5'), /не поддержана/);
  assert.throws(() => simplify('M0 0S1 1 2 2'), /не поддержана/);
  assert.throws(() => simplify('5 5'), /без команды/);
  assert.throws(() => simplify('M0 0L1'), /Ожидалось число/);
  assert.throws(() => simplify('M0 0A1 1 0 2 1 2 0'), /флаг дуги/);
});
