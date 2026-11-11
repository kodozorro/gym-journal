// Готовит данные для приложения на Swift из кода веб-приложения.
//
//   node ios/tools/generate.mjs          записать файлы
//   node ios/tools/generate.mjs --check  проверить, что файлы соответствуют коду (для тестов)
//
// Запускать после правки js/core, js/ui/art.js, js/ui/icons.js, apps-script/Code.gs или
// tools/fixture.mjs: рисунки, значки, учебный журнал и эталоны для тестов Swift берутся отсюда.

import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { exportArt, exportIcons } from './art.mjs';
import { buildBridgeCases, buildGolden, buildPull } from './golden.mjs';

export const ROOT = path.join(path.dirname(fileURLToPath(import.meta.url)), '..', '..');

const FIXTURES = 'ios/Core/Tests/GymJournalCoreTests/Fixtures';

/** Файлы, которые делает этот скрипт: путь от корня репозитория → содержимое. */
export function outputs() {
  const icons = fs.readFileSync(path.join(ROOT, 'js/ui/icons.js'), 'utf8');
  const json = (value) => `${JSON.stringify(value)}\n`;
  return {
    // учебный журнал: ответ настоящего скрипта на запрос pull поверх учебной таблицы
    'ios/Core/Sources/GymJournalCore/Resources/demo.json': json(buildPull()),
    'ios/App/Resources/art.json': json(exportArt()),
    'ios/App/Resources/icons.json': json(exportIcons(icons)),
    [`${FIXTURES}/golden.json`]: json(buildGolden()),
    [`${FIXTURES}/bridge.json`]: json(buildBridgeCases()),
  };
}

/** Файлы, которые разошлись с кодом. */
export function stale() {
  const out = [];
  for (const [rel, content] of Object.entries(outputs())) {
    const file = path.join(ROOT, rel);
    if (!fs.existsSync(file) || fs.readFileSync(file, 'utf8') !== content) out.push(rel);
  }
  return out;
}

function write() {
  for (const [rel, content] of Object.entries(outputs())) {
    const file = path.join(ROOT, rel);
    fs.mkdirSync(path.dirname(file), { recursive: true });
    const same = fs.existsSync(file) && fs.readFileSync(file, 'utf8') === content;
    if (!same) fs.writeFileSync(file, content);
    console.log(`${same ? 'без изменений' : 'записан'}: ${rel}`);
  }
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  if (process.argv.includes('--check')) {
    const list = stale();
    if (list.length) {
      console.error(`Устарели: ${list.join(', ')}. Запустите node ios/tools/generate.mjs`);
      process.exit(1);
    }
    console.log('Данные для приложения на Swift соответствуют коду.');
  } else {
    write();
  }
}
