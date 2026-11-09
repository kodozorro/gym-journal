// Локальный сервер для разработки и тестов в браузере.
//
//   node tools/dev-server.mjs            приложение на http://127.0.0.1:8080/gym-journal/
//   node tools/dev-server.mjs --mock     плюс учебный мостик: настоящий apps-script/Code.gs
//                                        поверх таблицы в памяти с выдуманными числами
//   node tools/dev-server.mjs --sw       отдавать сервис-воркер (по умолчанию он выключен,
//                                        чтобы правки были видны сразу)
//
// Приложение отдаётся из папки /gym-journal/, как на GitHub Pages. Учебный мостик слушает
// другой порт и отвечает так же, как Google: на POST — перенаправлением, по которому
// браузер уже получает JSON. С настоящей таблицей и Google сервер не связывается.

import crypto from 'node:crypto';
import fs from 'node:fs';
import http from 'node:http';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { createGasEnvironment, loadAppsScript } from './gas-fake.mjs';
import { buildSpreadsheet, fillHistory } from './fixture.mjs';

const ROOT = path.join(path.dirname(fileURLToPath(import.meta.url)), '..');
export const BASE = '/gym-journal/';
/** Ключ учебного мостика. Это не секрет: мостик существует только на вашем компьютере. */
export const MOCK_KEY = '0123456789abcdef0123456789abcdef01234567';

const TYPES = {
  '.html': 'text/html; charset=utf-8',
  '.js': 'text/javascript; charset=utf-8',
  '.mjs': 'text/javascript; charset=utf-8',
  '.css': 'text/css; charset=utf-8',
  '.json': 'application/json; charset=utf-8',
  '.webmanifest': 'application/manifest+json; charset=utf-8',
  '.svg': 'image/svg+xml',
  '.png': 'image/png',
  '.ico': 'image/x-icon',
};

// Только то, из чего состоит приложение: тесты, инструменты и .git наружу не отдаются.
const PUBLIC = /^(?:index\.html|manifest\.webmanifest|sw\.js|(?:css|js|icons)\/[A-Za-z0-9._/-]+)$/;

function listen(server, port) {
  return new Promise((resolve, reject) => {
    server.once('error', reject);
    server.listen(port, '127.0.0.1', () => resolve(server.address().port));
  });
}

function close(server) {
  return new Promise((resolve) => {
    server.closeAllConnections?.();
    server.close(() => resolve());
  });
}

function mondayOf(date) {
  const day = (date.getUTCDay() + 6) % 7;
  return new Date(Date.UTC(date.getUTCFullYear(), date.getUTCMonth(), date.getUTCDate() - day));
}

/** Учебный мостик: Code.gs поверх таблицы в памяти. */
export async function startMockBridge({ port = 0, spreadsheet, key = MOCK_KEY } = {}) {
  let sheet = spreadsheet;
  if (!sheet) {
    // программа «идёт» третью неделю, прошлые дни заполнены выдуманными числами
    const today = new Date();
    const iso = (d) => d.toISOString().slice(0, 10);
    const start = new Date(mondayOf(today).getTime() - 14 * 86400000);
    sheet = buildSpreadsheet({ start: iso(start), realLayout: false });
    fillHistory(sheet, { before: iso(new Date(Date.UTC(today.getFullYear(), today.getMonth(), today.getDate()))) });
  }
  const environment = createGasEnvironment({ spreadsheet: sheet, properties: { GJ_KEY: key } });
  const script = loadAppsScript(path.join(ROOT, 'apps-script', 'Code.gs'), environment);
  const answers = new Map();
  const cors = { 'Access-Control-Allow-Origin': '*' };

  const server = http.createServer((req, res) => {
    const url = new URL(req.url, 'http://mock');
    if (req.method === 'GET' && url.pathname === '/macros/echo') {
      const body = answers.get(url.searchParams.get('token'));
      answers.delete(url.searchParams.get('token'));
      if (body === undefined) {
        res.writeHead(404, { ...cors, 'Content-Type': 'text/html; charset=utf-8' }).end('<!doctype html><title>Не найдено</title>');
        return;
      }
      res.writeHead(200, { ...cors, 'Content-Type': 'application/json; charset=utf-8', 'Cache-Control': 'no-store' }).end(body);
      return;
    }
    if (!/^\/macros\/s\/[A-Za-z0-9_-]+\/exec$/.test(url.pathname)) {
      res.writeHead(404, { 'Content-Type': 'text/html; charset=utf-8' }).end('<!doctype html><title>Не найдено</title>');
      return;
    }
    if (req.method === 'GET') {
      res.writeHead(200, { ...cors, 'Content-Type': 'application/json; charset=utf-8' }).end(script.doGet().getContent());
      return;
    }
    if (req.method !== 'POST') {
      // на предварительный запрос OPTIONS Apps Script не отвечает: приложение не должно его вызывать
      res.writeHead(405, { 'Content-Type': 'text/html; charset=utf-8' }).end('<!doctype html><title>405</title>');
      return;
    }
    const chunks = [];
    req.on('data', (chunk) => chunks.push(chunk));
    req.on('end', () => {
      const out = script.doPost({ postData: { contents: Buffer.concat(chunks).toString('utf8'), type: req.headers['content-type'] || '' } });
      const token = crypto.randomUUID();
      answers.set(token, out.getContent());
      res.writeHead(302, { ...cors, Location: `/macros/echo?token=${token}` }).end();
    });
  });
  const actualPort = await listen(server, port);
  return {
    url: `http://127.0.0.1:${actualPort}/macros/s/MOCK_DEPLOYMENT/exec`,
    key,
    spreadsheet: sheet,
    state: environment.state,
    close: () => close(server),
  };
}

/**
 * Статический сервер приложения.
 * @param {object} [options]
 * @param {number} [options.port] 0 — любой свободный
 * @param {boolean} [options.sw] отдавать sw.js
 * @param {boolean} [options.localBridge] разрешить в политике безопасности страницы обращения к localhost (для учебного мостика)
 */
export async function startServer({ port = 0, sw = true, localBridge = false } = {}) {
  /** подмена содержимого файлов: так тесты «выпускают» новую версию приложения */
  const overrides = new Map();
  const server = http.createServer((req, res) => {
    const url = new URL(req.url, 'http://app');
    if (url.pathname === '/' || url.pathname === BASE.slice(0, -1)) {
      res.writeHead(302, { Location: BASE }).end();
      return;
    }
    if (!url.pathname.startsWith(BASE) || (req.method !== 'GET' && req.method !== 'HEAD')) {
      res.writeHead(404, { 'Content-Type': 'text/plain; charset=utf-8' }).end('Не найдено');
      return;
    }
    let rel;
    try {
      rel = decodeURIComponent(url.pathname.slice(BASE.length)) || 'index.html';
    } catch {
      rel = '';
    }
    if (!PUBLIC.test(rel) || rel.includes('..') || (rel === 'sw.js' && !sw)) {
      res.writeHead(404, { 'Content-Type': 'text/plain; charset=utf-8' }).end('Не найдено');
      return;
    }
    const send = (err, data) => {
      if (err) {
        res.writeHead(404, { 'Content-Type': 'text/plain; charset=utf-8' }).end('Не найдено');
        return;
      }
      let body = data;
      if (rel === 'index.html' && localBridge) {
        // только для разработки: настоящая страница обращается лишь к script.google.com
        body = Buffer.from(data.toString('utf8').replace("connect-src 'self'", "connect-src 'self' http://127.0.0.1:* http://localhost:*"));
      }
      res.writeHead(200, { 'Content-Type': TYPES[path.extname(rel)] || 'application/octet-stream', 'Cache-Control': 'no-store' });
      res.end(req.method === 'HEAD' ? undefined : body);
    };
    if (overrides.has(rel)) send(null, Buffer.from(overrides.get(rel)));
    else fs.readFile(path.join(ROOT, rel), send);
  });
  const actualPort = await listen(server, port);
  const origin = `http://127.0.0.1:${actualPort}`;
  return {
    origin,
    url: `${origin}${BASE}`,
    /** Отдавать вместо файла rel указанное содержимое; null — вернуть настоящий файл. */
    override(rel, content) {
      if (content === null) overrides.delete(rel);
      else overrides.set(rel, content);
    },
    close: () => close(server),
  };
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const args = process.argv.slice(2);
  const portIndex = args.indexOf('--port');
  const port = portIndex >= 0 ? Number(args[portIndex + 1]) : 8080;
  const mock = args.includes('--mock');
  const app = await startServer({ port, sw: args.includes('--sw'), localBridge: mock });
  console.log(`Приложение: ${app.url}`);
  if (mock) {
    const bridge = await startMockBridge({ port: port + 1 });
    console.log('Учебный мостик с выдуманными числами. Вставьте в настройках приложения:');
    console.log(`  адрес: ${bridge.url}`);
    console.log(`  ключ:  ${bridge.key}`);
  }
}
