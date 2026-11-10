// Сервис-воркер: хранит файлы приложения в телефоне, чтобы оно открывалось без сети.
//
// Сайт живёт на общем адресе с другими страницами владельца, поэтому воркер отвечает
// только за свою папку, а имена кэшей начинаются с «gj-». Обращения к таблице
// (POST на script.google.com) он не трогает: их очередь ведёт само приложение.
//
// Новая версия ставится рядом со старой и ждёт: страница сама решает, когда перейти.

/* stamp:begin — блок пишет tools/stamp.mjs, руками не править */
const VERSION = "1.0.0+11ecc4df4f";
const FILES = [
  "./",
  "css/app.css",
  "icons/apple-touch-icon.png",
  "icons/icon-192.png",
  "icons/icon-512.png",
  "icons/icon-maskable-512.png",
  "icons/icon.svg",
  "img/machines/chest-press.webp",
  "img/machines/hack-press.webp",
  "img/machines/lateral-raise.webp",
  "img/machines/leg-curl.webp",
  "img/machines/leg-press.webp",
  "img/machines/low-pulley.webp",
  "img/machines/pec-deck.webp",
  "img/machines/seated-leg-press.webp",
  "img/machines/shoulder-press.webp",
  "js/boot.js",
  "js/core/dates.js",
  "js/core/guide.js",
  "js/core/journal.js",
  "js/core/keypad.js",
  "js/core/numbers.js",
  "js/core/outbox.js",
  "js/core/plan.js",
  "js/core/scale.js",
  "js/core/stats.js",
  "js/core/timer.js",
  "js/data/api.js",
  "js/data/storage.js",
  "js/data/store.js",
  "js/data/sync.js",
  "js/main.js",
  "js/platform/feedback.js",
  "js/platform/pwa.js",
  "js/ui/app.js",
  "js/ui/art.js",
  "js/ui/chart.js",
  "js/ui/day.js",
  "js/ui/icons.js",
  "js/ui/parts.js",
  "js/ui/plan.js",
  "js/ui/progress.js",
  "js/ui/settings.js",
  "js/ui/sheets.js",
  "js/ui/vdom.js",
  "js/version.js",
  "manifest.webmanifest"
];
/* stamp:end */

const PREFIX = 'gj-';
const CACHE = `${PREFIX}${VERSION}`;
const SHELL = './';

self.addEventListener('install', (event) => {
  event.waitUntil(
    (async () => {
      const cache = await caches.open(CACHE);
      // cache: 'reload' — мимо кэша браузера, иначе можно сохранить старые файлы под новой версией
      await cache.addAll(FILES.map((path) => new Request(path, { cache: 'reload' })));
    })(),
  );
});

self.addEventListener('activate', (event) => {
  event.waitUntil(
    (async () => {
      const names = await caches.keys();
      await Promise.all(names.filter((name) => name.startsWith(PREFIX) && name !== CACHE).map((name) => caches.delete(name)));
      await self.clients.claim();
    })(),
  );
});

self.addEventListener('message', (event) => {
  if (event.data && event.data.type === 'SKIP_WAITING') self.skipWaiting();
});

self.addEventListener('fetch', (event) => {
  const request = event.request;
  if (request.method !== 'GET') return;
  const url = new URL(request.url);
  if (url.origin !== self.location.origin) return;

  const scope = new URL(self.registration.scope).pathname;
  const isShell = request.mode === 'navigate' && (url.pathname === scope || url.pathname === `${scope}index.html`);

  event.respondWith(
    (async () => {
      const cache = await caches.open(CACHE);
      const cached = await cache.match(isShell ? SHELL : request);
      if (cached) return cached;
      return fetch(request);
    })(),
  );
});
