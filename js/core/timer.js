// Таймер отдыха. Время считается по часам, а не по тикам: телефон может заблокироваться
// или свернуть приложение, и после возврата остаток должен быть верным.

/** @returns {{startedAt:number, endsAt:number, total:number}} total — в секундах */
export function startRest(now, seconds) {
  return { startedAt: now, endsAt: now + seconds * 1000, total: seconds };
}

/** Сколько секунд осталось; 0 — отдых окончен. */
export function restLeft(timer, now) {
  return Math.max(0, Math.ceil((timer.endsAt - now) / 1000));
}

export function restOver(timer, now) {
  return now >= timer.endsAt;
}

/** Сколько секунд прошло после окончания отдыха. */
export function restOvertime(timer, now) {
  return Math.max(0, Math.floor((now - timer.endsAt) / 1000));
}

/** Доля прошедшего времени от 0 до 1. */
export function restProgress(timer, now) {
  const span = timer.endsAt - timer.startedAt;
  if (span <= 0) return 1;
  return Math.min(1, Math.max(0, (now - timer.startedAt) / span));
}

/** Добавляет время. Если отдых уже кончился, отсчёт идёт от текущего момента. */
export function extendRest(timer, now, seconds) {
  const over = now >= timer.endsAt;
  return {
    startedAt: over ? now : timer.startedAt,
    endsAt: (over ? now : timer.endsAt) + seconds * 1000,
    total: over ? seconds : timer.total + seconds,
  };
}

/** Проверка того, что лежало в хранилище. */
export function validRest(value) {
  return Boolean(
    value && Number.isFinite(value.startedAt) && Number.isFinite(value.endsAt) && Number.isFinite(value.total) &&
    value.endsAt >= value.startedAt,
  );
}

/** «1:30», «0:05», «12:00» */
export function formatClock(seconds) {
  const s = Math.max(0, Math.round(seconds));
  return `${Math.floor(s / 60)}:${String(s % 60).padStart(2, '0')}`;
}
