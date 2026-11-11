import Foundation

/// Таймер отдыха. Время считается по часам, а не по тикам: телефон может заблокироваться
/// или свернуть приложение, и после возврата остаток должен быть верным.
public struct RestTimer: Equatable, Codable, Sendable {
    public var startedAt: Date
    public var endsAt: Date
    /// Полная длительность отдыха в секундах.
    public var total: Double

    public init(startedAt: Date, endsAt: Date, total: Double) {
        self.startedAt = startedAt
        self.endsAt = endsAt
        self.total = total
    }

    public static func start(now: Date, seconds: Double) -> RestTimer {
        RestTimer(startedAt: now, endsAt: now.addingTimeInterval(seconds), total: seconds)
    }

    /// Сколько секунд осталось; 0 — отдых окончен.
    public func left(now: Date) -> Int {
        max(0, Numbers.int(endsAt.timeIntervalSince(now).rounded(.up)))
    }

    public func isOver(now: Date) -> Bool {
        now >= endsAt
    }

    /// Сколько секунд прошло после окончания отдыха.
    public func overtime(now: Date) -> Int {
        max(0, Numbers.int(now.timeIntervalSince(endsAt).rounded(.down)))
    }

    /// Доля прошедшего времени от 0 до 1.
    public func progress(now: Date) -> Double {
        let span = endsAt.timeIntervalSince(startedAt)
        if span <= 0 { return 1 }
        return min(1, max(0, now.timeIntervalSince(startedAt) / span))
    }

    /// Добавляет время. Если отдых уже кончился, отсчёт идёт от текущего момента.
    public func extended(now: Date, seconds: Double) -> RestTimer {
        let over = now >= endsAt
        return RestTimer(
            startedAt: over ? now : startedAt,
            endsAt: (over ? now : endsAt).addingTimeInterval(seconds),
            total: over ? seconds : total + seconds
        )
    }

    /// Проверка того, что лежало в хранилище или пришло с другого устройства.
    public var isValid: Bool {
        total.isFinite && endsAt >= startedAt
    }

    /// «1:30», «0:05», «12:00»
    public static func clock(_ seconds: Double) -> String {
        let value = max(0, Numbers.int(Numbers.roundHalfUp(seconds)))
        return "\(value / 60):\(Days.pad(value % 60, 2))"
    }

    public static func clock(_ seconds: Int) -> String {
        clock(Double(seconds))
    }
}
