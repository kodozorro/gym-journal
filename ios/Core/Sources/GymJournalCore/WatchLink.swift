import Foundation

// Обмен между телефоном и часами.
//
// В таблицу пишет только телефон. Он присылает часам состояние дня целиком, а часы возвращают
// действия пользователя по одному, каждое со своим номером. Телефон применяет действие один раз,
// сколько бы раз оно ни пришло, и в следующем состоянии сообщает номер последнего принятого.
// Пока подтверждения нет, часы показывают свои действия поверх присланного состояния.

/// Какую тренировку записывать в «Здоровье».
public enum WorkoutKind: String, Codable, Sendable {
    /// Тренажёры: силовая тренировка.
    case strength
    /// Ходьба.
    case walk

    public var title: String {
        switch self {
        case .strength: return "Силовая"
        case .walk: return "Ходьба"
        }
    }
}

/// Тренировка, которая идёт сейчас.
public struct LiveWorkout: Equatable, Codable, Sendable, Identifiable {
    public var id: String
    public var kind: WorkoutKind
    public var startedAt: Date
    /// День журнала, к которому относится тренировка.
    public var date: String
    /// Тренировку ведут часы; иначе её записывает телефон.
    public var onWatch: Bool
    /// Ходьба по дорожке: в помещении, без маршрута.
    public var indoor: Bool

    public init(id: String, kind: WorkoutKind, startedAt: Date, date: String, onWatch: Bool, indoor: Bool = true) {
        self.id = id
        self.kind = kind
        self.startedAt = startedAt
        self.date = date
        self.onWatch = onWatch
        self.indoor = indoor
    }
}

/// Итог законченной тренировки.
public struct WorkoutSummary: Equatable, Codable, Sendable {
    public var id: String
    public var kind: WorkoutKind
    public var date: String
    public var startedAt: Date
    public var endedAt: Date
    /// Километры по датчикам часов; у дорожки на табло число точнее.
    public var km: Double?
    public var kcal: Double?
    /// Тренировка сохранена в «Здоровье».
    public var saved: Bool

    public init(
        id: String, kind: WorkoutKind, date: String, startedAt: Date, endedAt: Date,
        km: Double? = nil, kcal: Double? = nil, saved: Bool = true
    ) {
        self.id = id
        self.kind = kind
        self.date = date
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.km = km
        self.kcal = kcal
        self.saved = saved
    }

    /// Длительность в минутах, округлённая до целых.
    public var minutes: Double {
        Swift.max(0, Numbers.roundHalfUp(endedAt.timeIntervalSince(startedAt) / 60))
    }
}

/// Просьба телефона к часам: начать или закончить тренировку.
public struct WorkoutIntent: Equatable, Codable, Sendable {
    /// Растёт с каждой новой просьбой: часы выполняют просьбу один раз.
    /// 64 бита: в номере миллисекунды, а Int на часах занимает 32 бита.
    public var id: Int64
    /// nil — закончить тренировку.
    public var kind: WorkoutKind?
    public var date: String
    public var indoor: Bool
    /// Когда просьба создана.
    public var at: Date

    /// Сколько секунд просьба начать тренировку остаётся в силе. Часы, которые открыли позже,
    /// тренировку сами не начнут: к этому времени её уже записывает телефон или она не нужна.
    public static let startLifetime: TimeInterval = 120

    public init(id: Int64, kind: WorkoutKind?, date: String, indoor: Bool = true, at: Date) {
        self.id = id
        self.kind = kind
        self.date = date
        self.indoor = indoor
        self.at = at
    }

    /// Просьбу ещё нужно выполнять. Закончить тренировку можно когда угодно, начать — только сразу.
    public func isFresh(now: Date) -> Bool {
        kind == nil || now.timeIntervalSince(at) <= WorkoutIntent.startLifetime
    }
}

/// Состояние дня, которое телефон присылает часам.
public struct WatchState: Equatable, Codable, Sendable {
    /// Растёт с каждой отправкой: более старое состояние часы не принимают.
    public var stamp: Int64
    /// Таблица подключена и журнал загружен.
    public var configured: Bool
    /// «Сегодня» по часам телефона.
    public var today: String
    /// День, который показывают часы: сегодняшний или тот, что делают сегодня.
    public var date: String?
    public var title: String
    public var week: Int?
    /// Строки дня в порядке таблицы, с наложенными неотправленными правками.
    public var rows: [JournalRow]
    /// «Прошлый раз» по ключу строки.
    public var last: [String: JournalRow]
    /// Шаг веса по ключу строки.
    public var steps: [String: Double]
    public var restSec: Int
    public var autoTimer: Bool
    public var rest: RestTimer?
    public var workout: LiveWorkout?
    public var intent: WorkoutIntent?
    /// Записывать тренировки в «Здоровье».
    public var health: Bool
    /// Установка часов, к которой относится ackSeq.
    public var ackEpoch: String
    /// Номер последнего действия часов, которое телефон принял.
    public var ackSeq: Int
    /// Когда следующая тренировка, если сегодня её нет: «пт 27.11 · Силовая C и ходьба».
    public var next: String

    public init(
        stamp: Int64 = 0, configured: Bool = false, today: String = "", date: String? = nil, title: String = "",
        week: Int? = nil, rows: [JournalRow] = [], last: [String: JournalRow] = [:], steps: [String: Double] = [:],
        restSec: Int = 90, autoTimer: Bool = true, rest: RestTimer? = nil, workout: LiveWorkout? = nil,
        intent: WorkoutIntent? = nil, health: Bool = true, ackEpoch: String = "", ackSeq: Int = 0, next: String = ""
    ) {
        self.stamp = stamp
        self.configured = configured
        self.today = today
        self.date = date
        self.title = title
        self.week = week
        self.rows = rows
        self.last = last
        self.steps = steps
        self.restSec = restSec
        self.autoTimer = autoTimer
        self.rest = rest
        self.workout = workout
        self.intent = intent
        self.health = health
        self.ackEpoch = ackEpoch
        self.ackSeq = ackSeq
        self.next = next
    }
}

/// Действие пользователя на часах.
public enum WatchAction: Equatable, Codable, Sendable {
    /// Повторы в подходе; nil стирает подход.
    case reps(key: String, index: Int, value: Double?)
    case weight(key: String, value: Double?)
    /// Прибавить отрезок ходьбы к уже записанному.
    case walkAdd(key: String, km: Double?, min: Double?)
    /// Отдых запущен, продлён или остановлен (nil).
    case rest(RestTimer?)
    case workoutStarted(LiveWorkout)
    case workoutEnded(WorkoutSummary)
}

public struct WatchOp: Equatable, Codable, Sendable, Identifiable {
    /// Порядковый номер действия на этих часах.
    public var seq: Int
    public var at: Date
    public var action: WatchAction

    public var id: Int { seq }

    public init(seq: Int, at: Date, action: WatchAction) {
        self.seq = seq
        self.at = at
        self.action = action
    }
}

/// Посылка от часов телефону.
public struct WatchPacket: Equatable, Codable, Sendable {
    /// Идентификатор установки приложения на часах: после переустановки номера действий идут заново.
    public var epoch: String
    public var ops: [WatchOp]
    /// Номер последней просьбы телефона, которую часы выполнили.
    public var intentDone: Int64

    public init(epoch: String, ops: [WatchOp], intentDone: Int64 = 0) {
        self.epoch = epoch
        self.ops = ops
        self.intentDone = intentDone
    }
}

public enum WatchLink {
    /// Ключи словаря, в котором посылки едут через WatchConnectivity.
    public static let stateKey = "state"
    public static let packetKey = "packet"

    public static func encode<T: Encodable>(_ value: T) -> Data? {
        try? JSONEncoder().encode(value)
    }

    public static func decode<T: Decodable>(_ type: T.Type, from data: Data?) -> T? {
        guard let data else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    /// Номер для нового состояния или новой просьбы: больше прежнего и не меньше времени в
    /// миллисекундах. После переустановки приложения счёт не начинается с нуля, поэтому часы
    /// не примут новое состояние за устаревшее.
    public static func nextStamp(after last: Int64, now: Date) -> Int64 {
        Swift.max(last + 1, Int64((now.timeIntervalSince1970 * 1000).rounded()))
    }

    // MARK: Телефон

    /// Состояние дня для часов: строки с наложенной очередью, «прошлый раз» и шаг веса силовых строк.
    /// Отдых, тренировку, просьбу и подтверждение действий добавляет приложение.
    /// - Parameters:
    ///   - journal: журнал с наложенными неотправленными правками.
    ///   - live: день, который делают сегодня, если это не сегодняшний.
    public static func dayState(
        journal: [JournalRow], today: String, live: String?, settings: AppSettings, configured: Bool
    ) -> WatchState {
        var state = WatchState(
            configured: configured, today: today, restSec: settings.restSec, autoTimer: settings.autoTimer,
            health: settings.health
        )
        let days = Journal.groupDays(journal)
        let shown = days.first { $0.date == live } ?? days.first { $0.date == today }
        guard let day = shown else {
            state.next = Present.nextWorkout(days: days, today: today)
            return state
        }
        state.date = day.date
        state.title = Journal.workoutTitle(day.rows)
        state.week = day.week
        state.rows = day.rows
        for row in day.rows where !row.isWalk {
            if let last = Journal.lastTime(journal, for: row) { state.last[row.key] = last }
            state.steps[row.key] = settings.step(for: row.exercise)
        }
        return state
    }

    /// Какие действия из посылки часов телефон ещё не применял.
    /// - Parameters:
    ///   - epoch: установка часов, от которой телефон принимал действия в прошлый раз.
    ///   - seq: номер последнего принятого действия этой установки.
    /// - Returns: новые действия по порядку и номер, который теперь нужно запомнить.
    public static func accept(_ packet: WatchPacket, epoch: String, seq: Int) -> (ops: [WatchOp], seq: Int) {
        var last = packet.epoch == epoch ? seq : 0
        var fresh: [WatchOp] = []
        for op in packet.ops.sorted(by: { $0.seq < $1.seq }) where op.seq > last {
            fresh.append(op)
            last = op.seq
        }
        return (fresh, last)
    }

    // MARK: Часы

    /// Действия часов, которые телефон ещё не подтвердил в присланном состоянии.
    public static func pending(_ ops: [WatchOp], state: WatchState, epoch: String) -> [WatchOp] {
        guard state.ackEpoch == epoch else { return ops }
        return ops.filter { $0.seq > state.ackSeq }
    }

    /// Отдых, который показывают часы: свой, пока телефон не подтвердил последнее действие
    /// с таймером, иначе тот, что прислал телефон.
    public static func rest(pending: [WatchOp], state: WatchState) -> RestTimer? {
        for op in pending.reversed() {
            if case .rest(let timer) = op.action { return timer }
        }
        return state.rest
    }

    /// Правка строки, которая получается из действия на часах; nil — править нечего.
    public static func patch(for action: WatchAction, row: JournalRow, last: JournalRow?) -> RowFields? {
        switch action {
        case .reps(_, let index, let value):
            guard !row.isWalk, index >= 0, index < Plans.maxSets else { return nil }
            var sets = row.sets
            if sets[index] == value { return nil }
            sets[index] = value
            var fields = RowFields(sets: sets)
            // первый подход закрепляет вес, подставленный с прошлого раза
            if row.weight == nil, value != nil, let weight = last?.weight { fields.weight = .set(weight) }
            return fields
        case .weight(_, let value):
            guard !row.isWalk, row.weight != value else { return nil }
            return RowFields(weight: .set(value))
        case .walkAdd(_, let km, let min):
            guard row.isWalk else { return nil }
            var fields = RowFields()
            if let km, km > 0 { fields.km = .set(Numbers.roundTo((row.km ?? 0) + km, 2)) }
            if let min, min > 0 { fields.min = .set(Numbers.roundTo((row.min ?? 0) + min, 1)) }
            return fields.isEmpty ? nil : fields
        case .rest, .workoutStarted, .workoutEnded:
            return nil
        }
    }

    /// Ключ строки, к которой относится действие.
    public static func rowKey(of action: WatchAction) -> String? {
        switch action {
        case .reps(let key, _, _), .weight(let key, _), .walkAdd(let key, _, _):
            return key
        case .rest, .workoutStarted, .workoutEnded:
            return nil
        }
    }

    /// Строки дня с наложенными действиями часов, которые телефон ещё не подтвердил.
    public static func apply(_ ops: [WatchOp], to rows: [JournalRow], last: [String: JournalRow]) -> [JournalRow] {
        var out = rows
        for op in ops {
            guard let key = rowKey(of: op.action), let index = out.firstIndex(where: { $0.key == key }),
                  let fields = patch(for: op.action, row: out[index], last: last[key]) else { continue }
            out[index] = OutboxLogic.patched(out[index], with: fields)
        }
        return out
    }

    /// Куда перейти после записи подхода: к соседу по паре, к следующему подходу, к следующей паре.
    public static func nextTarget(pairs: [[JournalRow]], pair: [JournalRow], key: String, index: Int) -> String? {
        if let partner = pair.first(where: {
            $0.key != key && index < $0.strengthPlan.sets && $0.sets[index] == nil
        }) {
            return partner.key
        }
        if let inPair = pair.first(where: { $0.nextSetIndex != -1 }) { return inPair.key }
        for other in pairs {
            if let row = other.first(where: { !$0.isDone }) { return row.key }
        }
        return nil
    }

    /// Какие тренировки предложить для дня: силовую, если в нём есть тренажёры, и ходьбу, если есть ходьба.
    /// Силовая идёт первой: в смешанный день она главная.
    public static func kinds(for rows: [JournalRow]) -> [WorkoutKind] {
        var out: [WorkoutKind] = []
        if rows.contains(where: { !$0.isWalk }) { out.append(.strength) }
        if rows.contains(where: { $0.isWalk }) { out.append(.walk) }
        return out
    }

    /// Ходьба идёт по дорожке: тренировка записывается как занятие в помещении.
    public static func isIndoorWalk(_ rows: [JournalRow]) -> Bool {
        let walks = rows.filter { $0.isWalk }
        if walks.isEmpty { return true }
        return walks.allSatisfy { row in
            let machine = row.machine.trimmingCharacters(in: .whitespacesAndNewlines)
            return machine.isEmpty || Guide.machineType(machine) == "treadmill"
        }
    }
}
