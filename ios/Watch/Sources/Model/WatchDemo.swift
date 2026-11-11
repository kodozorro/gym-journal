import Foundation
import GymJournalCore

/// Показ приложения на часах с учебным журналом: выдуманные числа, без телефона и «Здоровья».
///
/// Включается параметрами запуска и нужен для снимков экрана и проверки в симуляторе:
/// `-demo YES -demoToday 2026-11-25 -demoScene exercise`.
struct WatchDemo {
    /// День, который приложение считает сегодняшним.
    var today: String
    /// Что показать сразу после запуска: today, exercise, rest, sets, list, weight, walk, segment,
    /// workout, live, connect, first.
    var scene: String

    static func fromLaunch(_ defaults: UserDefaults = .standard) -> WatchDemo? {
        guard defaults.bool(forKey: "demo") else { return nil }
        var today = DemoData.today
        if let value = defaults.string(forKey: "demoToday"), Days.isISODate(value) { today = value }
        return WatchDemo(today: today, scene: defaults.string(forKey: "demoScene") ?? "today")
    }

    /// Состояние дня, каким его прислал бы телефон с учебным журналом.
    func state() -> WatchState {
        // часы, которые ещё ничего не получали от телефона
        if scene == "first" { return WatchState(today: today) }
        // таблица в приложении на телефоне не подключена
        if scene == "connect" { return WatchState(stamp: 1, today: today) }
        guard let journal = DemoData.bridge()?.journal else { return WatchState(stamp: 1, today: today) }
        var state = WatchLink.dayState(
            journal: journal, today: today, live: nil, settings: AppSettings(), configured: true
        )
        state.stamp = 1
        return state
    }
}
