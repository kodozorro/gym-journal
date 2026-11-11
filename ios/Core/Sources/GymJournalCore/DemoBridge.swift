import Foundation

/// Учебная таблица в памяти: отвечает на запросы так же, как скрипт в настоящей таблице.
///
/// Нужна тестам и показу приложения с выдуманными числами: с настоящей таблицей и Google
/// она не связывается. Правила проверки записей повторяют apps-script/Code.gs.
public final class DemoBridge: BridgeTransport, @unchecked Sendable {
    public enum Mode: Sendable {
        /// Мостик работает.
        case ok
        /// Страница входа вместо данных.
        case html
        /// Нет связи.
        case down
        /// Таблица занята другой записью.
        case busy
    }

    private let lock = NSLock()
    private var rows: [JournalRow]
    private var key: String
    private var start: String?
    private var walkGoalKm: Double?
    private var tz: String
    private var mode: Mode = .ok
    private var log: [[String: JSONValue]] = []

    static let limits = (entries: 400, weight: 1000.0, reps: 500.0, km: 200.0, min: 1440.0, note: 500, name: 200, occ: 50)

    public init(rows: [JournalRow], key: String, start: String? = nil, walkGoalKm: Double? = nil, tz: String = "Etc/GMT") {
        self.rows = rows
        self.key = key
        self.start = start
        self.walkGoalKm = walkGoalKm
        self.tz = tz
    }

    /// Таблица из сохранённого ответа скрипта на запрос pull.
    public convenience init?(pullResponse data: Data, key: String) {
        guard let parsed = try? JSONDecoder().decode(JSONValue.self, from: data), let object = parsed.object,
              let snapshot = JournalSnapshot.from(object, fetchedAt: Date(timeIntervalSince1970: 0)) else { return nil }
        self.init(rows: snapshot.journal, key: key, start: snapshot.start, walkGoalKm: snapshot.walkGoalKm, tz: snapshot.tz)
    }

    // MARK: Управление из тестов

    public func setMode(_ mode: Mode) {
        lock.lock()
        defer { lock.unlock() }
        self.mode = mode
    }

    public func setKey(_ key: String) {
        lock.lock()
        defer { lock.unlock() }
        self.key = key
    }

    /// Строки таблицы как они есть сейчас.
    public var journal: [JournalRow] {
        lock.lock()
        defer { lock.unlock() }
        return rows
    }

    /// Ручная правка в таблице, мимо приложения.
    public func edit(_ change: (inout [JournalRow]) -> Void) {
        lock.lock()
        defer { lock.unlock() }
        change(&rows)
    }

    /// Тела всех пришедших запросов.
    public var requests: [[String: JSONValue]] {
        lock.lock()
        defer { lock.unlock() }
        return log
    }

    // MARK: Запрос

    public func post(url: URL, body: Data, timeout: TimeInterval) async throws -> TransportResponse {
        let answer = try handle(body)
        return TransportResponse(status: 200, body: answer)
    }

    /// Разбирает тело запроса и возвращает тело ответа.
    public func handle(_ body: Data) throws -> Data {
        lock.lock()
        defer { lock.unlock() }
        let request = (try? JSONDecoder().decode(JSONValue.self, from: body))?.object
        if let request { log.append(request) }
        switch mode {
        case .down:
            throw TransportFailure.network
        case .html:
            return Data("<!doctype html><title>Вход</title>".utf8)
        case .busy, .ok:
            break
        }
        let response = respond(raw: body, request: request)
        return (try? JSONEncoder().encode(JSONValue.object(response))) ?? Data("{}".utf8)
    }

    private func ok(_ extra: [String: JSONValue] = [:]) -> [String: JSONValue] {
        var out: [String: JSONValue] = [
            "ok": .bool(true), "api": .number(Double(Bridge.apiVersion)), "script": .number(Double(Bridge.expectedScript)),
        ]
        for (name, value) in extra { out[name] = value }
        return out
    }

    private func fail(_ code: String, _ message: String) -> [String: JSONValue] {
        [
            "ok": .bool(false), "api": .number(Double(Bridge.apiVersion)), "script": .number(Double(Bridge.expectedScript)),
            "error": .string(code), "message": .string(message),
        ]
    }

    private func respond(raw: Data, request: [String: JSONValue]?) -> [String: JSONValue] {
        if raw.isEmpty { return fail("bad_request", "Пустой запрос.") }
        guard let request else {
            let parsed = try? JSONDecoder().decode(JSONValue.self, from: raw)
            return parsed == nil ? fail("bad_json", "Запрос не разобран как JSON.") : fail("bad_request", "Ожидается объект JSON.")
        }
        if key.isEmpty {
            return fail("no_key", "Ключ ещё не создан: запустите функцию setup в редакторе скрипта.")
        }
        guard request["key"]?.string == key else { return fail("unauthorized", "Неверный ключ.") }

        switch request["action"]?.string {
        case "ping":
            return ok()
        case "pull":
            return ok(snapshot())
        case "push":
            return push(request)
        default:
            return fail("unknown_action", "Неизвестное действие.")
        }
    }

    private func snapshot() -> [String: JSONValue] {
        [
            "tz": .string(tz),
            "start": start.map { JSONValue.string($0) } ?? .null,
            "walkGoalKm": JSONValue.optional(walkGoalKm),
            "journal": .array(rows.map(serialize)),
        ]
    }

    private func serialize(_ row: JournalRow) -> JSONValue {
        var out: [String: JSONValue] = [
            "date": .string(row.date),
            "workout": .string(row.workout),
            "exercise": .string(row.exercise),
            "plan": .string(row.plan),
            "machine": .string(row.machine),
            "week": row.week.map { JSONValue.number(Double($0)) } ?? .null,
            "weight": JSONValue.optional(row.weight),
            "sets": .array(row.sets.map { JSONValue.optional($0) }),
            "km": JSONValue.optional(row.km),
            "min": JSONValue.optional(row.min),
            "note": .string(row.note),
        ]
        if row.occ > 0 { out["occ"] = .number(Double(row.occ)) }
        return .object(out)
    }

    private func push(_ request: [String: JSONValue]) -> [String: JSONValue] {
        guard let entries = request["entries"]?.array else {
            return fail("bad_request", "Поле entries должно быть списком.")
        }
        if entries.count > Self.limits.entries { return fail("too_many", "Слишком много записей в одном запросе.") }
        if mode == .busy { return fail("busy", "Таблица занята другой записью. Повторите позже.") }
        var results: [JSONValue] = []
        for entry in entries { results.append(write(entry)) }
        var out = ok(["results": .array(results)])
        if request["pull"] == .bool(true) {
            for (name, value) in snapshot() { out[name] = value }
        }
        return out
    }

    private func result(date: JSONValue?, exercise: JSONValue?, occ: Int, status: String, reason: String = "") -> JSONValue {
        var out: [String: JSONValue] = [
            "date": date?.string.map { JSONValue.string($0) } ?? .null,
            "exercise": exercise?.string.map { JSONValue.string($0) } ?? .null,
            "status": .string(status),
        ]
        if occ > 0 { out["occ"] = .number(Double(occ)) }
        if !reason.isEmpty { out["reason"] = .string(reason) }
        return .object(out)
    }

    /// null — очистить ячейку; число в границах, округлённое до digits знаков; иначе ошибка.
    private func bounded(_ value: JSONValue, max: Double, digits: Int) -> Change<Double>? {
        if value == .null { return .set(nil) }
        guard let number = value.number, number >= 0, number <= max else { return nil }
        let k = pow(10.0, Double(digits))
        return .set(Numbers.roundHalfUp(number * k) / k)
    }

    private static let controls = Rx("[\\u0000-\\u0008\\u000B\\u000C\\u000E-\\u001F\\u007F]")

    private func write(_ entry: JSONValue) -> JSONValue {
        guard let object = entry.object else {
            return result(date: nil, exercise: nil, occ: 0, status: "rejected", reason: "Запись должна быть объектом.")
        }
        let date = object["date"]
        let exercise = object["exercise"]
        // у отклонённой при разборе записи номер строки-повтора в ответ попадает как есть
        let rawOcc = object["occ"]?.integer ?? 0
        func rejected(_ reason: String) -> JSONValue {
            result(date: date, exercise: exercise, occ: rawOcc, status: "rejected", reason: reason)
        }

        guard let dateText = date?.string, Days.isISODate(dateText) else { return rejected("Неверная дата записи.") }
        guard let name = exercise?.string, !name.isEmpty, name.utf16.count <= Self.limits.name else {
            return rejected("Не указано упражнение.")
        }
        var occ = 0
        if let value = object["occ"], value != .null {
            guard let number = value.integer, number >= 0, number <= Self.limits.occ else {
                return rejected("Неверный номер строки-повтора.")
            }
            occ = number
        }

        var patch = RowFields()
        if let value = object["weight"] {
            guard let weight = bounded(value, max: Self.limits.weight, digits: 2) else {
                return rejected("Вес должен быть числом от 0 до 1000.")
            }
            patch.weight = weight
        }
        if let value = object["sets"] {
            guard let list = value.array, list.count <= 3 else { return rejected("Подходы должны быть списком до трёх чисел.") }
            var sets: [Double?] = [nil, nil, nil]
            for (index, reps) in list.enumerated() {
                if reps == .null { continue }
                guard let number = reps.number, number == number.rounded(.down), number >= 0, number <= Self.limits.reps else {
                    return rejected("Повторы должны быть целым числом от 0 до 500.")
                }
                sets[index] = number
            }
            patch.sets = sets
        }
        if let value = object["km"] {
            guard let km = bounded(value, max: Self.limits.km, digits: 2) else {
                return rejected("Километры должны быть числом от 0 до 200.")
            }
            patch.km = km
        }
        if let value = object["min"] {
            guard let min = bounded(value, max: Self.limits.min, digits: 1) else {
                return rejected("Минуты должны быть числом от 0 до 1440.")
            }
            patch.min = min
        }
        if let value = object["note"] {
            guard let text = value.string else { return rejected("Заметка должна быть текстом.") }
            let note = Self.controls.replace(text, with: "").trimmingCharacters(in: .whitespacesAndNewlines)
            if note.utf16.count > Self.limits.note { return rejected("Заметка длиннее 500 символов.") }
            patch.note = note
        }

        func answer(_ status: String, _ reason: String = "") -> JSONValue {
            result(date: date, exercise: exercise, occ: occ, status: status, reason: reason)
        }
        guard let index = rows.firstIndex(where: { $0.date == dateText && $0.exercise == name && $0.occ == occ }) else {
            return answer("not_found", "В журнале нет строки с такой датой и упражнением.")
        }
        let walk = rows[index].isWalk
        if walk && (!patch.weight.isKeep || patch.sets != nil) {
            return answer("rejected", "Это строка ходьбы: вес и подходы в неё не пишутся.")
        }
        if !walk && (!patch.km.isKeep || !patch.min.isKeep) {
            return answer("rejected", "Это силовая строка: километры и минуты в неё не пишутся.")
        }

        var next = OutboxLogic.patched(rows[index], with: patch)
        next.pending = false
        let changed = next != rows[index]
        rows[index] = next
        return answer(changed ? "written" : "unchanged")
    }
}
