import Foundation

/// Лучший рабочий вес за неделю.
public struct WeeklyBest: Equatable, Sendable {
    public var week: Int
    public var best: Double
}

/// Ходьба за неделю: сумма километров и минут.
public struct WeeklyWalk: Equatable, Sendable {
    public var week: Int
    public var km: Double
    public var min: Double
}

/// Неделя журнала: номер и дни.
public struct JournalWeek: Equatable, Sendable, Identifiable {
    public var week: Int?
    public var days: [JournalDay]

    public var id: Int { week ?? 0 }
}

/// Недельная статистика. Повторяет формулы листа «Прогресс»:
/// лучший рабочий вес за неделю по упражнению и сумма километров и минут ходьбы за неделю.
public enum Stats {
    /// Понедельник недели программы с номером week.
    public static func weekStart(start: String?, week: Int?) -> String? {
        guard let start, let week else { return nil }
        return Days.addDays(start, (week - 1) * 7)
    }

    private struct Rank {
        var workout: String
        var position: Int
    }

    private static let russian = Locale(identifier: "ru")

    private static func before(_ a: Rank, _ b: Rank) -> Bool {
        switch a.workout.compare(b.workout, options: [], range: nil, locale: russian) {
        case .orderedAscending: return true
        case .orderedDescending: return false
        case .orderedSame: return a.position < b.position
        }
    }

    /// Силовые упражнения в устойчивом порядке: по тренировке (A, B, C), затем по месту в дне.
    public static func exerciseList(_ journal: [JournalRow]) -> [String] {
        var order: [String] = []
        var seen: [String: Rank] = [:]
        for day in Journal.groupDays(journal) {
            var position = 0
            for row in day.rows where !row.isWalk {
                let rank = Rank(workout: row.workout, position: position)
                if let known = seen[row.exercise] {
                    if before(rank, known) { seen[row.exercise] = rank }
                } else {
                    seen[row.exercise] = rank
                    order.append(row.exercise)
                }
                position += 1
            }
        }
        // сортировка устойчивая: при равном месте сохраняется порядок первого появления
        let indexed = order.enumerated().map { (offset: $0.offset, name: $0.element) }
        return indexed.sorted { a, b in
            guard let first = seen[a.name], let second = seen[b.name] else { return a.offset < b.offset }
            if before(first, second) { return true }
            if before(second, first) { return false }
            return a.offset < b.offset
        }.map { $0.name }
    }

    /// Лучший рабочий вес за неделю, как MAXIFS в таблице. Нулевой вес таблица считает пустым.
    public static func weeklyBest(_ journal: [JournalRow], exercise: String, start: String?) -> [WeeklyBest] {
        var best: [Int: Double] = [:]
        for row in journal where row.exercise == exercise && !row.isWalk {
            guard let weight = row.weight, weight > 0, let week = Journal.weekOf(row, start: start) else { continue }
            best[week] = Swift.max(best[week] ?? 0, weight)
        }
        return best.keys.sorted().map { WeeklyBest(week: $0, best: best[$0] ?? 0) }
    }

    /// Ходьба по неделям: сумма километров и минут. В список попадают недели,
    /// где записан хотя бы один вес или километраж — как в столбце A сводной таблицы.
    public static func weeklyWalk(_ journal: [JournalRow], start: String?) -> [WeeklyWalk] {
        struct Sum {
            var km = 0.0
            var min = 0.0
            var active = false
        }
        var weeks: [Int: Sum] = [:]
        for row in journal {
            guard let week = Journal.weekOf(row, start: start) else { continue }
            var item = weeks[week] ?? Sum()
            if row.weight != nil || row.km != nil { item.active = true }
            if let km = row.km { item.km += km }
            if let min = row.min { item.min += min }
            weeks[week] = item
        }
        return weeks.keys.sorted().compactMap { week in
            guard let item = weeks[week], item.active else { return nil }
            return WeeklyWalk(
                week: week,
                km: Numbers.roundHalfUp(item.km * 100) / 100,
                min: Numbers.roundHalfUp(item.min * 100) / 100
            )
        }
    }

    /// Записи по упражнению, новые сверху.
    public static func exerciseHistory(_ journal: [JournalRow], exercise: String) -> [JournalRow] {
        let rows = journal.enumerated().filter { $0.element.exercise == exercise && $0.element.hasData }
        return rows.sorted { a, b in
            if a.element.date != b.element.date { return a.element.date > b.element.date }
            return a.offset < b.offset
        }.map { $0.element }
    }

    /// Недели журнала: номер, даты и дни.
    public static func weeks(_ journal: [JournalRow], start: String?) -> [JournalWeek] {
        var order: [Int] = []
        var byId: [Int: JournalWeek] = [:]
        for day in Journal.groupDays(journal) {
            let week = day.week ?? day.rows.first.flatMap { Journal.weekOf($0, start: start) }
            let id = week ?? 0
            if byId[id] == nil {
                byId[id] = JournalWeek(week: week, days: [])
                order.append(id)
            }
            byId[id]?.days.append(day)
        }
        let indexed = order.enumerated().map { (offset: $0.offset, id: $0.element) }
        return indexed.sorted { a, b in a.id != b.id ? a.id < b.id : a.offset < b.offset }.compactMap { byId[$0.id] }
    }

    /// Номер недели программы, на которую приходится дата, или nil.
    public static func weekOfDate(_ weeks: [JournalWeek], date: String) -> Int? {
        var found: Int?
        for week in weeks {
            if let first = week.days.first, first.date <= date { found = week.week }
        }
        return found
    }
}
