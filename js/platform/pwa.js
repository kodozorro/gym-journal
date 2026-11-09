// Установка на экран телефона и обновление приложения.
//
// Новая версия скачивается в фоне и ждёт. Если она дождалась следующего запуска,
// то применяется сразу; если появилась, пока приложение открыто, — показывается плашка
// «Вышла новая версия», и человек сам выбирает момент.

const CHECK_EVERY_MS = 30 * 60 * 1000;

/**
 * @param {object} deps
 * @param {() => void} deps.onChange
 * @param {() => number} [deps.now]
 */
export function createPwa({ onChange, now = () => Date.now() }) {
  const supported = typeof navigator !== 'undefined' && 'serviceWorker' in navigator && globalThis.isSecureContext !== false;
  const hadController = supported && Boolean(navigator.serviceWorker.controller);

  const state = {
    supported,
    /** приложение уже сохранено на телефоне и откроется без сети */
    offlineReady: hadController,
    /** скачана новая версия, ждёт перезапуска */
    updateReady: false,
    checking: false,
    error: '',
    /** браузер готов показать системное окно установки (Android, компьютер) */
    canPrompt: false,
  };

  let registration = null;
  let installEvent = null;
  let reloading = false;
  let lastCheck = 0;

  function watch(worker) {
    if (!worker) return;
    worker.addEventListener('statechange', () => {
      if (worker.state !== 'installed') return;
      if (navigator.serviceWorker.controller) state.updateReady = true;
      else state.offlineReady = true;
      onChange();
    });
  }

  function activateWaiting() {
    if (registration && registration.waiting) registration.waiting.postMessage({ type: 'SKIP_WAITING' });
  }

  if (typeof window !== 'undefined') {
    window.addEventListener('beforeinstallprompt', (event) => {
      event.preventDefault();
      installEvent = event;
      state.canPrompt = true;
      onChange();
    });
    window.addEventListener('appinstalled', () => {
      installEvent = null;
      state.canPrompt = false;
      onChange();
    });
  }

  return {
    state,

    async register() {
      if (!supported) return;
      navigator.serviceWorker.addEventListener('controllerchange', () => {
        // первая установка тоже меняет контроллер, но перезагружать страницу тогда незачем
        if (!hadController || reloading) return;
        reloading = true;
        window.location.reload();
      });
      try {
        registration = await navigator.serviceWorker.register('sw.js');
      } catch (err) {
        state.error = err && err.message ? String(err.message) : 'Не удалось включить работу без сети.';
        onChange();
        return;
      }
      lastCheck = now();
      if (registration.waiting && navigator.serviceWorker.controller) {
        // версия скачана в прошлый раз и ждала запуска
        activateWaiting();
        return;
      }
      if (registration.active && !navigator.serviceWorker.controller) {
        // страницу открыли с принудительной перезагрузкой: кэш на месте, просто эта вкладка идёт мимо него
        state.offlineReady = true;
        onChange();
      }
      watch(registration.installing);
      registration.addEventListener('updatefound', () => watch(registration.installing));
    },

    /** Проверяет, не вышла ли новая версия. force — не смотреть на время прошлой проверки. */
    async check({ force = false } = {}) {
      if (!registration || state.checking) return;
      if (!force && now() - lastCheck < CHECK_EVERY_MS) return;
      lastCheck = now();
      state.checking = true;
      onChange();
      try {
        await registration.update();
      } catch {
        // нет сети — проверим в другой раз
      } finally {
        state.checking = false;
        onChange();
      }
    },

    applyUpdate() {
      if (registration && registration.waiting) activateWaiting();
      else window.location.reload();
    },

    async promptInstall() {
      if (!installEvent) return;
      const event = installEvent;
      installEvent = null;
      state.canPrompt = false;
      try {
        await event.prompt();
      } catch {
        // окно уже показывали
      }
      onChange();
    },

    /** Запущено со значка на экране телефона, а не во вкладке браузера. */
    isStandalone() {
      if (typeof window === 'undefined') return false;
      return window.matchMedia('(display-mode: standalone)').matches || navigator.standalone === true;
    },

    isIOS() {
      if (typeof navigator === 'undefined') return false;
      return /iphone|ipad|ipod/i.test(navigator.userAgent) || (navigator.platform === 'MacIntel' && navigator.maxTouchPoints > 1);
    },
  };
}
