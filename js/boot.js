// Тема ставится до первой отрисовки, чтобы экран не мигал светлым в тёмной теме.
// Обычный скрипт, а не модуль: модули выполняются уже после разбора страницы.
(function () {
  try {
    var raw = window.localStorage.getItem('gj:1:settings');
    var theme = raw ? JSON.parse(raw).theme : null;
    if (theme === 'light' || theme === 'dark') document.documentElement.setAttribute('data-theme', theme);
  } catch (err) {
    // хранилище недоступно: остаётся тема телефона
  }
})();
