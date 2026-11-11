import Foundation

/// Изменение одного поля строки.
public enum Change<Value: Equatable & Sendable>: Equatable, Sendable {
    /// Поля в правке нет: в таблице оно остаётся как было.
    case keep
    /// Новое состояние поля; nil — стереть.
    case set(Value?)

    public var isKeep: Bool {
        if case .keep = self { return true }
        return false
    }
}

/// Правка строки журнала: состояние полей, а не изменение. «Вес 30, подходы 15 и 14».
/// Повторная отправка ничего не портит, поэтому очередь можно слать сколько угодно раз.
public struct RowFields: Equatable, Sendable {
    public var weight: Change<Double> = .keep
    /// Все три ячейки подходов разом.
    public var sets: [Double?]?
    public var km: Change<Double> = .keep
    public var min: Change<Double> = .keep
    public var note: String?

    public init(
        weight: Change<Double> = .keep, sets: [Double?]? = nil, km: Change<Double> = .keep,
        min: Change<Double> = .keep, note: String? = nil
    ) {
        self.weight = weight
        self.sets = sets.map { Journal.threeSets($0) }
        self.km = km
        self.min = min
        self.note = note
    }

    public var isEmpty: Bool {
        weight.isKeep && sets == nil && km.isKeep && min.isKeep && note == nil
    }

    /// Эта правка поверх прежней: поля, которых в новой нет, остаются как были.
    public func merged(over previous: RowFields) -> RowFields {
        RowFields(
            weight: weight.isKeep ? previous.weight : weight,
            sets: sets ?? previous.sets,
            km: km.isKeep ? previous.km : km,
            min: min.isKeep ? previous.min : min,
            note: note ?? previous.note
        )
    }

    /// Запись для запроса push.
    func entry(date: String, exercise: String, occ: Int) -> JSONValue {
        var out: [String: JSONValue] = ["date": .string(date), "exercise": .string(exercise)]
        if case .set(let value) = weight { out["weight"] = JSONValue.optional(value) }
        if let sets { out["sets"] = .array(sets.map { JSONValue.optional($0) }) }
        if case .set(let value) = km { out["km"] = JSONValue.optional(value) }
        if case .set(let value) = min { out["min"] = JSONValue.optional(value) }
        if let note { out["note"] = .string(note) }
        if occ > 0 { out["occ"] = .number(Double(occ)) }
        return .object(out)
    }
}

extension RowFields: Codable {
    enum CodingKeys: String, CodingKey {
        case weight, sets, km, min, note
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init()
        if container.contains(.weight) { weight = .set(try container.decodeIfPresent(Double.self, forKey: .weight)) }
        if container.contains(.sets) {
            sets = Journal.threeSets((try? container.decode([Double?].self, forKey: .sets)) ?? [])
        }
        if container.contains(.km) { km = .set(try container.decodeIfPresent(Double.self, forKey: .km)) }
        if container.contains(.min) { min = .set(try container.decodeIfPresent(Double.self, forKey: .min)) }
        if container.contains(.note) { note = (try? container.decodeIfPresent(String.self, forKey: .note)) ?? "" }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        func put(_ change: Change<Double>, _ key: CodingKeys) throws {
            guard case .set(let value) = change else { return }
            if let value { try container.encode(value, forKey: key) } else { try container.encodeNil(forKey: key) }
        }
        try put(weight, .weight)
        if let sets { try container.encode(sets, forKey: .sets) }
        try put(km, .km)
        try put(min, .min)
        if let note { try container.encode(note, forKey: .note) }
    }
}

/// Запись в очереди: по одной строке журнала лежит одна запись, новые правки вливаются в неё.
public struct OutboxItem: Equatable, Codable, Sendable {
    public var date: String
    public var exercise: String
    public var occ: Int
    public var fields: RowFields
    /// Номер правки: по нему видно, успели ли запись поправить, пока запрос был в пути.
    public var rev: Int
    public var at: Date

    public var key: String { "\(date)|\(exercise)|\(occ)" }
}

/// Запись, которую таблица не приняла.
public struct FailedItem: Equatable, Codable, Sendable, Identifiable {
    public var item: OutboxItem
    /// «not_found» — строки нет в журнале, «rejected» — таблица отклонила запись.
    public var status: String
    public var reason: String
    public var failedAt: Date

    public var id: String { "\(item.key)|\(item.rev)" }
}

public struct Outbox: Equatable, Codable, Sendable {
    public var seq: Int
    public var items: [String: OutboxItem]
    public var failed: [FailedItem]

    public init(seq: Int = 0, items: [String: OutboxItem] = [:], failed: [FailedItem] = []) {
        self.seq = seq
        self.items = items
        self.failed = failed
    }

    public var pendingCount: Int { items.count }
}

/// Отметка, какая версия записи ушла в запросе.
public struct SentMark: Equatable, Sendable {
    public var key: String
    public var rev: Int
}

public struct PushRequest: Equatable, Sendable {
    public var entries: [JSONValue]
    public var sent: [SentMark]
}

public struct OutboxMismatch: Error, Equatable {
    public var message = "Ответ скрипта не совпал с запросом по числу записей"
}

/// Очередь неотправленных записей. Чистые функции: состояние приходит и возвращается значением,
/// хранение и сеть — снаружи.
public enum OutboxLogic {
    /// Кладёт правку строки в очередь. Поля, которых в правке нет, остаются как были.
    public static func queue(_ outbox: Outbox, row: JournalRow, fields: RowFields, now: Date) -> Outbox {
        queue(outbox, date: row.date, exercise: row.exercise, occ: row.occ, fields: fields, now: now)
    }

    public static func queue(
        _ outbox: Outbox, date: String, exercise: String, occ: Int, fields: RowFields, now: Date
    ) -> Outbox {
        if fields.isEmpty { return outbox }
        let seq = outbox.seq + 1
        var item = OutboxItem(date: date, exercise: exercise, occ: occ, fields: fields, rev: seq, at: now)
        let key = item.key
        if let previous = outbox.items[key] { item.fields = fields.merged(over: previous.fields) }
        var next = outbox
        next.seq = seq
        next.items[key] = item
        // новая правка той же строки заменяет прежнюю отклонённую
        next.failed = outbox.failed.filter { $0.item.key != key }
        return next
    }

    /// Готовит запрос push: записи в порядке появления и отметку, какая версия каждой ушла.
    public static func buildPush(_ outbox: Outbox, limit: Int = 100) -> PushRequest {
        let list = outbox.items.values.sorted { $0.rev < $1.rev }.prefix(limit)
        return PushRequest(
            entries: list.map { $0.fields.entry(date: $0.date, exercise: $0.exercise, occ: $0.occ) },
            sent: list.map { SentMark(key: $0.key, rev: $0.rev) }
        )
    }

    /// Разбирает ответ скрипта. Принятые записи уходят из очереди; отклонённые и ненайденные
    /// переезжают в список ошибок, чтобы их увидел пользователь. Запись, которую успели поправить,
    /// пока запрос был в пути, остаётся в очереди и уйдёт в следующий раз.
    public static func ack(_ outbox: Outbox, sent: [SentMark], results: JSONValue?, now: Date) throws -> Outbox {
        guard let results = results?.array, results.count == sent.count else { throw OutboxMismatch() }
        var next = outbox
        for (index, mark) in sent.enumerated() {
            guard let item = next.items[mark.key], item.rev == mark.rev else { continue }
            let result = results[index].object
            let status = result?["status"]?.string
            next.items[mark.key] = nil
            if status == "written" || status == "unchanged" { continue }
            next.failed.append(FailedItem(
                item: item,
                status: status == "not_found" ? "not_found" : "rejected",
                reason: result?["reason"]?.string ?? "",
                failedAt: now
            ))
        }
        return next
    }

    /// Журнал с наложенными неотправленными правками: то, что пользователь видит на экране.
    public static func apply(_ journal: [JournalRow], _ outbox: Outbox) -> [JournalRow] {
        if outbox.items.isEmpty { return journal }
        return journal.map { row in
            guard let item = outbox.items[row.key] else { return row }
            return patched(row, with: item.fields)
        }
    }

    /// Строка с наложенной правкой.
    public static func patched(_ row: JournalRow, with fields: RowFields) -> JournalRow {
        var next = row
        if case .set(let value) = fields.weight { next.weight = value }
        if let sets = fields.sets { next.sets = Journal.threeSets(sets) }
        if case .set(let value) = fields.km { next.km = value }
        if case .set(let value) = fields.min { next.min = value }
        if let note = fields.note { next.note = note }
        next.pending = true
        return next
    }

    /// Возвращает отклонённую запись в очередь: например, после того как строку вернули в таблицу.
    public static func retryFailed(_ outbox: Outbox, index: Int, now: Date) -> Outbox {
        guard outbox.failed.indices.contains(index) else { return outbox }
        let failed = outbox.failed[index]
        var rest = outbox
        rest.failed.remove(at: index)
        // если по строке уже есть более свежая правка, она важнее
        var fields = failed.item.fields
        if let pending = rest.items[failed.item.key] { fields = pending.fields.merged(over: fields) }
        return queue(
            rest, date: failed.item.date, exercise: failed.item.exercise, occ: failed.item.occ, fields: fields, now: now
        )
    }

    public static func dropFailed(_ outbox: Outbox, index: Int) -> Outbox {
        guard outbox.failed.indices.contains(index) else { return outbox }
        var next = outbox
        next.failed.remove(at: index)
        return next
    }
}
