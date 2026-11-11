import Foundation
import GymJournalCore

/// Показ приложения с учебным журналом: выдуманные числа, без таблицы, «Здоровья» и часов.
///
/// Включается параметрами запуска и нужен для снимков экрана и проверки в симуляторе:
/// `-demo YES -demoToday 2026-11-25 -demoScene round`. С настоящей таблицей и Google приложение
/// в этом режиме не связывается: вместо скрипта отвечает учебная таблица в памяти.
///
/// С параметром `-demoDevices YES` журнал остаётся учебным, а часы и «Здоровье» — настоящие: так
/// на паре симуляторов проверяют обмен с часами и запуск тренировки.
struct DemoMode {
    /// День, который приложение считает сегодняшним.
    var today: String
    /// Что показать сразу после запуска: today, round, weight, note, info, walk, offline, day,
    /// workout, sync, plan, progress, settings, connect, welcome.
    var scene: String
    var bridge: DemoBridge?
    /// Учебный журнал, но настоящие часы и «Здоровье».
    var devices = false

    /// Таблица уже подключена. В сценах «connect» и «welcome» приложение запускается как новое.
    var connected: Bool {
        scene != "connect" && scene != "welcome"
    }

    static func fromLaunch(_ defaults: UserDefaults = .standard) -> DemoMode? {
        guard defaults.bool(forKey: "demo") else { return nil }
        var today = DemoData.today
        if let value = defaults.string(forKey: "demoToday"), Days.isISODate(value) { today = value }
        return DemoMode(
            today: today, scene: defaults.string(forKey: "demoScene") ?? "today", bridge: DemoData.bridge(),
            devices: defaults.bool(forKey: "demoDevices")
        )
    }
}
