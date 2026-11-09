// Хранилище на телефоне: настройки, последний снимок журнала и очередь записей.
// Запись в localStorage синхронная, поэтому правка переживает мгновенное закрытие приложения.
//
// Сайт живёт на общем адресе kodozorro.github.io вместе с другими страницами владельца,
// так что все ключи идут с приставкой, чтобы ни с кем не пересечься.

export const PREFIX = 'gj:1:';

function memoryBackend() {
  const map = new Map();
  return {
    getItem: (key) => (map.has(key) ? map.get(key) : null),
    setItem: (key, value) => {
      map.set(key, String(value));
    },
    removeItem: (key) => {
      map.delete(key);
    },
    key: (i) => [...map.keys()][i] ?? null,
    get length() {
      return map.size;
    },
  };
}

function usable(backend) {
  try {
    const probe = `${PREFIX}__probe`;
    backend.setItem(probe, '1');
    backend.removeItem(probe);
    return true;
  } catch {
    return false;
  }
}

/**
 * @param {Storage} [backend] localStorage или его подмена; без него данные живут только в памяти
 */
export function createStorage(backend) {
  const persistent = Boolean(backend) && usable(backend);
  const store = persistent ? backend : memoryBackend();

  return {
    /** false — браузер не дал постоянное хранилище (например, приватный режим). */
    persistent,

    get(name, fallback = null) {
      try {
        const raw = store.getItem(PREFIX + name);
        return raw === null ? fallback : JSON.parse(raw);
      } catch {
        return fallback;
      }
    },

    /** @returns {boolean} удалось ли сохранить */
    set(name, value) {
      try {
        store.setItem(PREFIX + name, JSON.stringify(value));
        return true;
      } catch {
        return false;
      }
    },

    remove(name) {
      try {
        store.removeItem(PREFIX + name);
      } catch {
        // нечего удалять
      }
    },

    /** Удаляет только ключи приложения; чужие данные на том же адресе не трогает. */
    clear() {
      try {
        const keys = [];
        for (let i = 0; i < store.length; i += 1) {
          const key = store.key(i);
          if (key && key.startsWith(PREFIX)) keys.push(key);
        }
        keys.forEach((key) => store.removeItem(key));
      } catch {
        // хранилище недоступно
      }
    },
  };
}
