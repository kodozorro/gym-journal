// Точка входа: собирает хранилище, синхронизацию и экран.

import { createStorage } from './data/storage.js';
import { createStore } from './data/store.js';
import { createSync } from './data/sync.js';
import { createFeedback } from './platform/feedback.js';
import { createPwa } from './platform/pwa.js';
import { createApp } from './ui/app.js';

function localStorageOrNull() {
  try {
    return window.localStorage;
  } catch {
    return null; // хранилище запрещено настройками браузера
  }
}

let app = null;
const redraw = () => {
  if (app) app.invalidate();
};

const storage = createStorage(localStorageOrNull());
const store = createStore(storage, redraw);
const sync = createSync({
  storage,
  fetch: (url, init) => window.fetch(url, init),
  isOnline: () => navigator.onLine !== false,
  onChange: redraw,
});
const feedback = createFeedback();
const pwa = createPwa({ onChange: redraw });
const host = window.location.hostname;

app = createApp({
  root: document.getElementById('app'),
  storage,
  store,
  sync,
  feedback,
  pwa,
  // учебный мостик на этом же компьютере разрешён только при разработке
  env: { local: host === 'localhost' || host === '127.0.0.1' },
});

app.start();
pwa.register();
