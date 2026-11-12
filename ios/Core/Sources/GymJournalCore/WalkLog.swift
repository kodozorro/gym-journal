import Foundation

// Отрезок ходьбы, записанный вручную, попадает в «Здоровье» как тренировка «Ходьба».
//
// У отрезка есть только километры и минуты, поэтому время тренировки условное: она кончается в
// момент записи и длится столько минут, сколько в отрезке. Шаги, пульс и калории приложение не
// выдумывает. Записывает тренировку телефон: отрезок сначала попадает в очередь и ждёт в ней,
// пока «Здоровье» недоступно.

/// Ходьба, которую нужно записать в «Здоровье».
public struct WalkEntry: Equatable, Codable, Sendable {
    public var start: Date
    public var end: Date
    /// Километры отрезка; nil — расстояние не записывали.
    public var km: Double?
    /// Ходьба по дорожке: в помещении, без маршрута.
    public var indoor: Bool

    public init(start: Date, end: Date, km: Double? = nil, indoor: Bool = true) {
        self.start = start
        self.end = end
        self.km = km
        self.indoor = indoor
    }
}

public enum WalkLog {
    /// Сколько отрезок ждёт в очереди. Ходьбу старше суток в «Здоровье» уже не записывают.
    public static let keep: TimeInterval = 24 * 3600

    /// Что делать с отрезком, записанным вручную.
    public enum Outcome: Equatable, Sendable {
        /// Записать тренировку.
        case save(WalkEntry)
        /// У отрезка нет минут: длительность тренировки неизвестна.
        case noMinutes
        /// Эту ходьбу уже записала тренировка, которая только что закончилась.
        case covered
    }

    /// Тренировка для отрезка, записанного вручную.
    /// - Parameters:
    ///   - km: километры отрезка.
    ///   - minutes: минуты отрезка.
    ///   - end: момент записи: им тренировка кончается.
    ///   - indoor: ходьба по дорожке.
    ///   - last: последняя законченная тренировка. Если это сохранённая ходьба и она занимает
    ///     больше половины времени отрезка, отрезок описывает её же: вторая тренировка не нужна.
    public static func outcome(
        km: Double?, minutes: Double?, end: Date, indoor: Bool = true, last: WorkoutSummary? = nil
    ) -> Outcome {
        guard let minutes, minutes > 0 else { return .noMinutes }
        let length = minutes * 60
        let start = end.addingTimeInterval(-length)
        if let last, last.kind == .walk, last.saved {
            let shared = min(end, last.endedAt).timeIntervalSince(max(start, last.startedAt))
            if shared * 2 > length { return .covered }
        }
        var distance: Double?
        if let km, km > 0 { distance = km }
        return .save(WalkEntry(start: start, end: end, km: distance, indoor: indoor))
    }

    /// Отрезки из очереди, которые ещё стоит записывать: без тех, что ждут дольше суток.
    public static func fresh(_ queue: [WalkEntry], now: Date) -> [WalkEntry] {
        queue.filter { now.timeIntervalSince($0.end) < keep }
    }
}
