import Foundation

/// Строка листа «Журнал»: одно упражнение одного дня.
public struct JournalRow: Equatable, Codable, Sendable, Identifiable {
    public var date: String
    public var workout: String
    public var exercise: String
    public var plan: String
    public var machine: String
    public var week: Int?
    public var weight: Double?
    /// Повторы по подходам, всегда три ячейки.
    public var sets: [Double?]
    public var km: Double?
    public var min: Double?
    public var note: String
    /// Номер строки-повтора: вторая и следующие строки с той же датой и названием.
    public var occ: Int
    /// По строке есть неотправленная правка. Только для показа, в таблицу не уходит.
    public var pending: Bool

    public init(
        date: String, workout: String = "", exercise: String, plan: String = "", machine: String = "",
        week: Int? = nil, weight: Double? = nil, sets: [Double?] = [nil, nil, nil], km: Double? = nil,
        min: Double? = nil, note: String = "", occ: Int = 0, pending: Bool = false
    ) {
        self.date = date
        self.workout = workout
        self.exercise = exercise
        self.plan = plan
        self.machine = machine
        self.week = week
        self.weight = weight
        self.sets = Journal.threeSets(sets)
        self.km = km
        self.min = min
        self.note = note
        self.occ = occ
        self.pending = pending
    }

    /// Ключ строки: по нему строка ищется в таблице.
    public var key: String { "\(date)|\(exercise)|\(occ)" }
    public var id: String { key }

    /// Таблица считает строку ходьбой по тому же правилу: столбец «Тренировка» равен «Ходьба».
    public var isWalk: Bool {
        workout.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == Journal.walkWorkout
    }

    public var strengthPlan: StrengthPlan { Plans.strength(plan) }

    /// Сколько ячеек подходов показывать: по плану, но не меньше уже заполненных.
    public var slotCount: Int {
        var lastFilled = -1
        for (index, value) in sets.enumerated() where value != nil { lastFilled = index }
        return Swift.min(Plans.maxSets, Swift.max(strengthPlan.sets, lastFilled + 1))
    }

    /// Первый незаполненный подход плана или -1, если все записаны.
    public var nextSetIndex: Int {
        let count = strengthPlan.sets
        for index in 0..<count where sets[index] == nil { return index }
        return -1
    }

    public var hasData: Bool {
        if isWalk { return km != nil || min != nil }
        return weight != nil || sets.contains { $0 != nil }
    }

    /// Отметки «сделано» в таблице нет. Силовая строка готова, когда заполнены вес
    /// и все подходы плана; ходьба — когда заполнены километры.
    public var isDone: Bool {
        if isWalk { return km != nil }
        if weight == nil { return false }
        let plan = strengthPlan
        if plan.unknown { return sets.contains { $0 != nil } }
        return sets.prefix(plan.sets).allSatisfy { $0 != nil }
    }

    /// Километры из плана ходьбы: «3 км, наклон 1–3 %» → 3.
    public var plannedKm: Double? {
        if case .cardio(let plan) = Plans.parse(self.plan) { return plan.km }
        return nil
    }

    /// Краткая запись сделанного: «60 кг · 15, 14».
    public var summary: String {
        var parts: [String] = []
        if isWalk {
            if let km { parts.append("\(Numbers.format(km)) км") }
            if let min { parts.append("\(Numbers.format(min)) мин") }
            return parts.joined(separator: " · ")
        }
        if let weight { parts.append("\(Numbers.format(weight)) кг") }
        let done = sets.compactMap { $0 }
        if !done.isEmpty { parts.append(done.map { Numbers.plain($0) }.joined(separator: ", ")) }
        return parts.joined(separator: " · ")
    }
}

/// День журнала: строки одной даты в порядке таблицы.
public struct JournalDay: Equatable, Sendable, Identifiable {
    public var date: String
    public var week: Int?
    public var rows: [JournalRow]

    public var id: String { date }
}

public enum DayStatus: String, Sendable {
    case done, partial, missed, today, planned
}

public struct DayProgress: Equatable, Sendable {
    public var done: Int
    public var touched: Int
    public var total: Int
}

/// Силовые упражнения дня парами и ходьба отдельно.
public struct DaySplit: Equatable, Sendable {
    public var pairs: [[JournalRow]]
    public var walks: [JournalRow]
}

/// Подсказка о прибавке веса по правилу программы.
public struct Progression: Equatable, Sendable {
    public var from: Double
    public var weight: Double
    public var reps: Int
    public var date: String
}

/// Темп и скорость ходьбы.
public struct Pace: Equatable, Sendable {
    /// «12:30» — минут на километр.
    public var pace: String
    /// Километров в час.
    public var speed: Double
}

/// Модель журнала: строки таблицы → дни, пары упражнений, «прошлый раз», готовность.
public enum Journal {
    public static let walkWorkout = "ходьба"

    static func threeSets(_ sets: [Double?]) -> [Double?] {
        (0..<Plans.maxSets).map { index in index < sets.count ? sets[index] : nil }
    }

    /// Приводит журнал из ответа скрипта к виду, на который рассчитывает приложение.
    /// Строки без даты или названия отбрасываются, лишние поля не переносятся.
    public static func normalize(_ list: JSONValue?) -> [JournalRow] {
        guard let items = list?.array else { return [] }
        var out: [JournalRow] = []
        for item in items {
            guard let raw = item.object, let date = raw["date"]?.string, Days.isISODate(date) else { continue }
            let exercise = (raw["exercise"]?.string ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if exercise.isEmpty { continue }
            let sets = raw["sets"]?.array ?? []
            var row = JournalRow(
                date: date,
                workout: raw["workout"]?.string ?? "",
                exercise: exercise,
                plan: raw["plan"]?.string ?? "",
                machine: raw["machine"]?.string ?? "",
                week: raw["week"]?.integer,
                weight: raw["weight"]?.number,
                sets: (0..<Plans.maxSets).map { index in index < sets.count ? sets[index].number : nil },
                km: raw["km"]?.number,
                min: raw["min"]?.number,
                note: raw["note"]?.string ?? ""
            )
            if let occ = raw["occ"]?.integer, occ > 0 { row.occ = occ }
            out.append(row)
        }
        return out
    }

    /// Дни журнала по порядку дат; строки внутри дня идут как в таблице.
    public static func groupDays(_ journal: [JournalRow]) -> [JournalDay] {
        var order: [String] = []
        var byDate: [String: JournalDay] = [:]
        for row in journal {
            if byDate[row.date] == nil {
                byDate[row.date] = JournalDay(date: row.date, week: row.week, rows: [])
                order.append(row.date)
            }
            byDate[row.date]?.rows.append(row)
            if byDate[row.date]?.week == nil, let week = row.week { byDate[row.date]?.week = week }
        }
        return order.sorted().compactMap { byDate[$0] }
    }

    /// Номер недели программы: из таблицы, а если его нет — от даты старта.
    public static func weekOf(_ row: JournalRow, start: String?) -> Int? {
        if let week = row.week { return week }
        guard let start, Days.isISODate(start), Days.isISODate(row.date) else { return nil }
        let days = Days.diffDays(row.date, start)
        return Int((Double(days) / 7).rounded(.down)) + 1
    }

    public static func dayProgress(_ rows: [JournalRow]) -> DayProgress {
        var done = 0
        var touched = 0
        for row in rows {
            if row.isDone { done += 1 }
            if row.hasData { touched += 1 }
        }
        return DayProgress(done: done, touched: touched, total: rows.count)
    }

    public static func dayStatus(_ rows: [JournalRow], date: String, today: String) -> DayStatus {
        let progress = dayProgress(rows)
        if progress.total > 0 && progress.done == progress.total { return .done }
        if progress.touched > 0 { return .partial }
        if date < today { return .missed }
        if date == today { return .today }
        return .planned
    }

    /// Силовые упражнения дня идут парами в порядке строк: 1–2, 3–4, 5–6.
    /// Ходьба — отдельными карточками.
    public static func splitDay(_ rows: [JournalRow]) -> DaySplit {
        let strength = rows.filter { !$0.isWalk }
        let walks = rows.filter { $0.isWalk }
        var pairs: [[JournalRow]] = []
        var index = 0
        while index < strength.count {
            pairs.append(Array(strength[index..<Swift.min(index + 2, strength.count)]))
            index += 2
        }
        return DaySplit(pairs: pairs, walks: walks)
    }

    /// Круг пары закончен, когда этот же по счёту подход записан у соседа или соседу он не положен.
    public static func roundComplete(_ pair: [JournalRow], key: String, setIndex: Int) -> Bool {
        pair.filter { $0.key != key }.allSatisfy { other in
            setIndex >= other.strengthPlan.sets || (setIndex < other.sets.count && other.sets[setIndex] != nil)
        }
    }

    /// «Прошлый раз» ищется по названию упражнения во всём журнале: одно упражнение
    /// встречается в двух тренировках недели на одном тренажёре.
    public static func lastTime(_ journal: [JournalRow], for row: JournalRow) -> JournalRow? {
        var best: JournalRow?
        for candidate in journal {
            if candidate.exercise != row.exercise || candidate.date >= row.date || !candidate.hasData { continue }
            if let current = best, candidate.date < current.date { continue }
            best = candidate
        }
        return best
    }

    /// Правило программы: когда во всех подходах получилась верхняя граница повторов,
    /// добавляется минимальный шаг веса. Возвращает подсказку или nil.
    public static func progression(last: JournalRow?, step: Double) -> Progression? {
        guard let last, let weight = last.weight, step > 0 else { return nil }
        let plan = last.strengthPlan
        guard !plan.unknown, let high = plan.high else { return nil }
        let sets = Array(last.sets.prefix(plan.sets))
        for value in sets {
            guard let value, value >= Double(high) else { return nil }
        }
        return Progression(from: weight, weight: Numbers.roundTo(weight + step, 2), reps: high, date: last.date)
    }

    private static func unique(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.filter { seen.insert($0).inserted }
    }

    /// «Силовая B и ходьба», «Ходьба ровным темпом»
    public static func workoutTitle(_ rows: [JournalRow]) -> String {
        let strength = unique(
            rows.filter { !$0.isWalk }
                .map { $0.workout.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        )
        let walks = rows.filter { $0.isWalk }
        if !strength.isEmpty && !walks.isEmpty { return "\(strength.joined(separator: ", ")) и ходьба" }
        if !strength.isEmpty { return strength.joined(separator: ", ") }
        if !walks.isEmpty { return unique(walks.map { $0.exercise }).joined(separator: ", ") }
        return ""
    }

    /// Короткая метка дня для списка недель: «A», «B», «Ходьба».
    public static func workoutBadge(_ rows: [JournalRow]) -> String {
        guard let strength = rows.first(where: { !$0.isWalk }) else { return rows.isEmpty ? "" : "Ходьба" }
        let name = strength.workout.trimmingCharacters(in: .whitespacesAndNewlines)
        let lastWord = name.split(whereSeparator: { $0.isWhitespace }).last.map(String.init) ?? name
        return lastWord.count <= 3 ? lastWord : name
    }

    /// Темп и скорость ходьбы для подписи под итогом.
    public static func pace(km: Double?, min: Double?) -> Pace? {
        guard let km, let min, km > 0, min > 0 else { return nil }
        let perKm = min / km
        var whole = Numbers.int(perKm.rounded(.down))
        var seconds = Numbers.int(Numbers.roundHalfUp((perKm - Double(whole)) * 60))
        if seconds == 60 {
            whole += 1
            seconds = 0
        }
        return Pace(pace: "\(whole):\(Days.pad(seconds, 2))", speed: Numbers.roundTo(km / (min / 60), 1))
    }
}
