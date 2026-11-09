// Настройки приложения на этом телефоне. В таблицу они не попадают.

/** Шаги веса, которые предлагает приложение, кг. */
export const STEP_CHOICES = [0.5, 1, 1.25, 2.5, 5, 10];
export const REST_MIN = 30;
export const REST_MAX = 300;
export const REST_STEP = 15;

export const DEFAULTS = Object.freeze({
  /** отдых между парами, секунды */
  restSec: 90,
  /** запускать отдых, когда записан круг пары */
  autoTimer: true,
  sound: true,
  vibrate: true,
  /** 'rest' — экран не гаснет, пока идёт отдых; 'workout' — пока открыта тренировка; 'off' */
  wakeLock: 'rest',
  /** подсказка о прибавке веса по правилу программы */
  hints: true,
  /** 'auto' | 'light' | 'dark' */
  theme: 'auto',
  /** шаг кнопок «+» и «−», если для упражнения не выбран свой */
  defaultStep: 2.5,
  /** свой шаг по названию упражнения */
  steps: {},
  /** пояснение о том, как записывать вес, уже показано */
  weightNoteSeen: false,
  /** упражнение, выбранное на экране «Прогресс» */
  chartExercise: '',
});

const isStep = (value) => typeof value === 'number' && Number.isFinite(value) && value > 0 && value <= 50;

export function normalizeSettings(value) {
  const src = value && typeof value === 'object' ? value : {};
  const out = { ...DEFAULTS, steps: {} };
  if (Number.isFinite(src.restSec)) out.restSec = Math.min(REST_MAX, Math.max(REST_MIN, Math.round(src.restSec)));
  for (const name of ['autoTimer', 'sound', 'vibrate', 'hints', 'weightNoteSeen']) {
    if (typeof src[name] === 'boolean') out[name] = src[name];
  }
  if (['rest', 'workout', 'off'].includes(src.wakeLock)) out.wakeLock = src.wakeLock;
  if (['auto', 'light', 'dark'].includes(src.theme)) out.theme = src.theme;
  if (isStep(src.defaultStep)) out.defaultStep = src.defaultStep;
  if (src.steps && typeof src.steps === 'object') {
    for (const [name, step] of Object.entries(src.steps)) {
      if (name && name.length <= 200 && isStep(step)) out.steps[name] = step;
    }
  }
  if (typeof src.chartExercise === 'string') out.chartExercise = src.chartExercise.slice(0, 200);
  return out;
}

/**
 * @param {ReturnType<import('./storage.js').createStorage>} storage
 * @param {() => void} [onChange]
 */
export function createStore(storage, onChange = () => {}) {
  let settings = normalizeSettings(storage.get('settings'));

  function save(next) {
    settings = normalizeSettings(next);
    storage.set('settings', settings);
    onChange();
  }

  return {
    get: () => settings,

    set(patch) {
      save({ ...settings, ...patch });
    },

    /** Шаг веса для упражнения. */
    stepFor(exercise) {
      return settings.steps[exercise] ?? settings.defaultStep;
    },

    setStep(exercise, step) {
      const steps = { ...settings.steps };
      if (step === settings.defaultStep) delete steps[exercise];
      else steps[exercise] = step;
      save({ ...settings, steps });
    },

    reset() {
      storage.remove('settings');
      settings = normalizeSettings(null);
      onChange();
    },
  };
}
