import Foundation

/// Когда не гасить экран.
public enum WakeLockMode: String, Codable, Sendable, CaseIterable {
    /// Пока идёт отдых.
    case rest
    /// Пока открыта тренировка.
    case workout
    case off
}

public enum ThemeMode: String, Codable, Sendable, CaseIterable {
    case auto, light, dark
}

/// Настройки приложения на этом телефоне. В таблицу они не попадают.
public struct AppSettings: Equatable, Sendable {
    /// Шаги веса, которые предлагает приложение, кг.
    public static let stepChoices: [Double] = [0.5, 1, 1.25, 2.5, 5, 10]
    public static let restMin = 30
    public static let restMax = 300
    public static let restStep = 15

    /// Отдых между парами, секунды.
    public var restSec = 90
    /// Запускать отдых, когда записан круг пары.
    public var autoTimer = true
    public var sound = true
    public var vibrate = true
    public var wakeLock: WakeLockMode = .rest
    /// Подсказка о прибавке веса по правилу программы.
    public var hints = true
    public var theme: ThemeMode = .auto
    /// Шаг кнопок «+» и «−», если для упражнения не выбран свой.
    public var defaultStep = 2.5
    /// Свой шаг по названию упражнения.
    public var steps: [String: Double] = [:]
    /// Пояснение о том, как записывать вес, уже показано.
    public var weightNoteSeen = false
    /// Упражнение, выбранное на экране «Прогресс».
    public var chartExercise = ""
    /// Записывать тренировку в «Здоровье» и включать её на часах.
    public var health = true
    /// Часы вибрируют в конце отдыха.
    public var watchSignal = true

    public init() {}

    /// Шаг веса для упражнения.
    public func step(for exercise: String) -> Double {
        steps[exercise] ?? defaultStep
    }

    public mutating func setStep(_ step: Double, for exercise: String) {
        if step == defaultStep {
            steps[exercise] = nil
        } else if AppSettings.isStep(step) {
            steps[exercise] = step
        }
    }

    static func isStep(_ value: Double) -> Bool {
        value.isFinite && value > 0 && value <= 50
    }

    /// Приводит значения к допустимым: то, что лежало в хранилище, могло устареть.
    public func normalized() -> AppSettings {
        var out = self
        out.restSec = Swift.min(AppSettings.restMax, Swift.max(AppSettings.restMin, restSec))
        if !AppSettings.isStep(defaultStep) { out.defaultStep = 2.5 }
        out.steps = steps.filter { !$0.key.isEmpty && $0.key.count <= 200 && AppSettings.isStep($0.value) }
        out.chartExercise = String(chartExercise.prefix(200))
        return out
    }
}

extension AppSettings: Codable {
    enum CodingKeys: String, CodingKey {
        case restSec, autoTimer, sound, vibrate, wakeLock, hints, theme, defaultStep, steps, weightNoteSeen, chartExercise, health, watchSignal
    }

    /// Незнакомые и испорченные поля заменяются значениями по умолчанию.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        var out = AppSettings()
        if let value = try? container.decode(Int.self, forKey: .restSec) { out.restSec = value }
        if let value = try? container.decode(Bool.self, forKey: .autoTimer) { out.autoTimer = value }
        if let value = try? container.decode(Bool.self, forKey: .sound) { out.sound = value }
        if let value = try? container.decode(Bool.self, forKey: .vibrate) { out.vibrate = value }
        if let value = try? container.decode(WakeLockMode.self, forKey: .wakeLock) { out.wakeLock = value }
        if let value = try? container.decode(Bool.self, forKey: .hints) { out.hints = value }
        if let value = try? container.decode(ThemeMode.self, forKey: .theme) { out.theme = value }
        if let value = try? container.decode(Double.self, forKey: .defaultStep) { out.defaultStep = value }
        if let value = try? container.decode([String: Double].self, forKey: .steps) { out.steps = value }
        if let value = try? container.decode(Bool.self, forKey: .weightNoteSeen) { out.weightNoteSeen = value }
        if let value = try? container.decode(String.self, forKey: .chartExercise) { out.chartExercise = value }
        if let value = try? container.decode(Bool.self, forKey: .health) { out.health = value }
        if let value = try? container.decode(Bool.self, forKey: .watchSignal) { out.watchSignal = value }
        self = out.normalized()
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(restSec, forKey: .restSec)
        try container.encode(autoTimer, forKey: .autoTimer)
        try container.encode(sound, forKey: .sound)
        try container.encode(vibrate, forKey: .vibrate)
        try container.encode(wakeLock, forKey: .wakeLock)
        try container.encode(hints, forKey: .hints)
        try container.encode(theme, forKey: .theme)
        try container.encode(defaultStep, forKey: .defaultStep)
        try container.encode(steps, forKey: .steps)
        try container.encode(weightNoteSeen, forKey: .weightNoteSeen)
        try container.encode(chartExercise, forKey: .chartExercise)
        try container.encode(health, forKey: .health)
        try container.encode(watchSignal, forKey: .watchSignal)
    }
}
