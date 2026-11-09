// Сигнал конца отдыха и удержание экрана включённым.
//
// На iPhone нет вибрации из браузера, а звук разрешён только после касания экрана.
// Поэтому prime() вызывается из обработчиков нажатий, а конец отдыха всегда виден на экране:
// звук и вибрация — дополнение, на которое нельзя полагаться.

export function createFeedback() {
  const hasNavigator = typeof navigator !== 'undefined';
  const canVibrate = hasNavigator && typeof navigator.vibrate === 'function';
  const canWakeLock = hasNavigator && 'wakeLock' in navigator;
  const AudioCtor = globalThis.AudioContext || globalThis.webkitAudioContext || null;

  let audio = null;
  let lock = null;
  let lockWanted = false;
  let lockPending = false;

  function context() {
    if (!AudioCtor) return null;
    if (!audio) {
      try {
        audio = new AudioCtor();
      } catch {
        audio = null;
      }
    }
    return audio;
  }

  async function acquire() {
    if (!canWakeLock || !lockWanted || lock || lockPending) return;
    if (typeof document !== 'undefined' && document.visibilityState !== 'visible') return;
    lockPending = true;
    try {
      const sentinel = await navigator.wakeLock.request('screen');
      if (!lockWanted) {
        sentinel.release().catch(() => {});
      } else {
        lock = sentinel;
        sentinel.addEventListener('release', () => {
          if (lock === sentinel) lock = null;
        });
      }
    } catch {
      // телефон отказал: режим экономии энергии или запрет в настройках
    } finally {
      lockPending = false;
    }
  }

  return {
    canVibrate,
    canWakeLock,
    canSound: Boolean(AudioCtor),

    /** Готовит звук. Вызывать из обработчика нажатия. */
    prime() {
      const ctx = context();
      if (ctx && ctx.state !== 'running' && typeof ctx.resume === 'function') ctx.resume().catch(() => {});
    },

    /** Три коротких сигнала. @returns {boolean} получилось ли запустить звук */
    beep() {
      const ctx = context();
      if (!ctx || ctx.state !== 'running') return false;
      const start = ctx.currentTime + 0.02;
      [0, 0.24, 0.48].forEach((offset, i) => {
        const osc = ctx.createOscillator();
        const gain = ctx.createGain();
        osc.type = 'sine';
        osc.frequency.value = i === 2 ? 1175 : 880;
        gain.gain.setValueAtTime(0.0001, start + offset);
        gain.gain.exponentialRampToValueAtTime(0.6, start + offset + 0.02);
        gain.gain.exponentialRampToValueAtTime(0.0001, start + offset + 0.2);
        osc.connect(gain);
        gain.connect(ctx.destination);
        osc.start(start + offset);
        osc.stop(start + offset + 0.22);
      });
      return true;
    },

    vibrate() {
      if (!canVibrate) return false;
      try {
        return navigator.vibrate([220, 120, 220]);
      } catch {
        return false;
      }
    },

    /** Просит телефон не гасить экран или отпускает его. */
    keepAwake(wanted) {
      lockWanted = Boolean(wanted);
      if (lockWanted) {
        acquire();
      } else if (lock) {
        const sentinel = lock;
        lock = null;
        sentinel.release().catch(() => {});
      }
    },

    /** Система сама отпускает экран, когда приложение свёрнуто: после возврата просим снова. */
    onVisible() {
      acquire();
    },

    isAwake: () => Boolean(lock),
  };
}
