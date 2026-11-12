import Foundation
import GymJournalCore

// Сиюминутное состояние экранов: где находимся, какой лист открыт, что набрано в форме.

/// Экран приложения.
enum Route: Equatable {
    case today
    case plan
    case progress
    case settings
    /// День журнала, открытый из плана.
    case day(String)

    /// Вкладка, которая подсвечена на этом экране. День относится к плану.
    var tab: AppTab {
        switch self {
        case .today: return .today
        case .plan, .day: return .plan
        case .progress: return .progress
        case .settings: return .settings
        }
    }

    /// Экран тренировки: «Сегодня» или день из плана.
    var isWorkout: Bool {
        switch self {
        case .today, .day: return true
        case .plan, .progress, .settings: return false
        }
    }
}

enum AppTab: String, CaseIterable, Identifiable {
    case today, plan, progress, settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .today: return "Сегодня"
        case .plan: return "План"
        case .progress: return "Прогресс"
        case .settings: return "Настройки"
        }
    }

    /// Имя значка совпадает с именем вкладки.
    var icon: String { rawValue }

    var route: Route {
        switch self {
        case .today: return .today
        case .plan: return .plan
        case .progress: return .progress
        case .settings: return .settings
        }
    }
}

/// Пара, с которой работают.
struct Focus: Equatable {
    var date: String
    var pair: Int
}

/// Тренировка не своего дня, которую делают сегодня.
struct LiveDay: Equatable, Codable {
    var date: String
    /// День, когда её отметили: назавтра отметка снимается.
    var on: String
}

struct ToastState: Equatable, Identifiable {
    var id: Int
    var text: String
}

/// Форма подключения таблицы.
struct ConnectForm: Equatable {
    var url = ""
    var key = ""
    var error = ""
    var busy = false
    var editing = false
}

enum FormField {
    case url, key
}

/// Что править в ходьбе: итог километров, итог минут или прибавить отрезок.
enum WalkFocus {
    case km, min, add
}

// MARK: Листы

/// Цифровая клавиатура.
struct KeypadState: Equatable {
    enum Target: Equatable {
        case weight(key: String)
        case reps(key: String, index: Int)
        case walk(key: String, add: Bool)
    }

    var target: Target
    var fields: [KeypadField]
    var active = 0
    var error = ""
    var canClear = false
    /// Упражнение, для которого под клавиатурой выбирается шаг веса.
    var stepsFor: String?
    /// Ходьбу из этого окна уже сохранила тренировка: вторую в «Здоровье» отрезок не создаёт.
    var tracked = false
}

struct NoteState: Equatable {
    /// Ключ строки журнала.
    var key: String
    var text: String
    var hadNote: Bool
    /// Готовые слова, которые можно добавить одним касанием.
    var chips: [String]
}

enum ConfirmAction: Equatable {
    /// Отключить таблицу.
    case reset
    /// Закончить тренировку в «Здоровье».
    case endWorkout
    /// Убрать с экрана тренировку, о которой часы не отвечают.
    case dropWorkout
}

struct ConfirmState: Equatable {
    var text: String
    var confirmLabel: String
    var danger = false
    var action: ConfirmAction
}

enum SheetContent: Equatable {
    case keypad(KeypadState)
    case note(NoteState)
    case sync
    case info(exercise: String, machine: String)
    case confirm(ConfirmState)
}

struct SheetState: Equatable, Identifiable {
    var id: Int
    var title: String
    var sub = ""
    /// Лист прижат к верху экрана: снизу его закрыла бы клавиатура телефона.
    var top = false
    var content: SheetContent
}

// MARK: «Здоровье» и часы

/// Разрешение записывать тренировки в «Здоровье».
enum HealthAccess: Equatable {
    /// Ещё не спрашивали.
    case unknown
    case granted
    case denied
    /// На этом устройстве «Здоровья» нет.
    case unavailable
}

/// То, что телефон помнит об обмене с часами.
struct WatchMemory: Equatable, Codable {
    /// Установка приложения на часах, от которой принимались действия.
    var epoch = ""
    /// Номер последнего принятого действия этой установки.
    var seq = 0
    /// Номер последнего отправленного состояния или просьбы.
    var stamp: Int64 = 0
}
