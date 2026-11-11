import Foundation
import XCTest
@testable import GymJournalCore

// Общее для тестов: эталоны и учебный журнал.
//
// Эталоны в папке Fixtures делает ios/tools/generate.mjs из кода веб-приложения и настоящего
// скрипта таблицы. Тесты сверяют с ними перенос этой логики на Swift: на одних и тех же данных
// оба приложения обязаны давать одно и то же. Все числа в эталонах выдуманные.

struct FixtureMissing: Error, CustomStringConvertible {
    var name: String
    var description: String { "Нет эталона «\(name)». Запустите node ios/tools/generate.mjs" }
}

enum Fixture {
    static func data(_ name: String) throws -> Data {
        guard let url = Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures") else {
            throw FixtureMissing(name: "\(name).json")
        }
        return try Data(contentsOf: url)
    }

    static func json(_ name: String) throws -> JSONValue {
        try JSONDecoder().decode(JSONValue.self, from: data(name))
    }

    private static let golden: JSONValue = (try? json("golden")) ?? .null

    /// Раздел эталонов логики веб-приложения.
    static func section(_ name: String) throws -> JSONValue {
        let value = golden[name]
        if value == .null { throw FixtureMissing(name: "golden.json: \(name)") }
        return value
    }

    /// Запросы к настоящему скрипту и его ответы, по порядку.
    static func bridgeCases() throws -> [JSONValue] {
        let list = try json("bridge").list
        if list.isEmpty { throw FixtureMissing(name: "bridge.json") }
        return list
    }

    /// «Сегодня» учебного журнала.
    static let today = DemoData.today

    /// Ответ скрипта на запрос pull: учебный журнал приложения.
    static let pull: [String: JSONValue] = {
        guard let data = DemoData.pullResponse,
              let value = try? JSONDecoder().decode(JSONValue.self, from: data) else { return [:] }
        return value.object ?? [:]
    }()

    static let journal: [JournalRow] = Journal.normalize(pull["journal"])
    static let start: String? = pull["start"]?.string

    static func row(_ date: String, _ exercise: String) throws -> JournalRow {
        guard let row = journal.first(where: { $0.date == date && $0.exercise == exercise }) else {
            throw FixtureMissing(name: "строка \(date) \(exercise)")
        }
        return row
    }

    static func day(_ date: String) -> [JournalRow] {
        journal.filter { $0.date == date }
    }
}

extension JSONValue {
    subscript(key: String) -> JSONValue {
        object?[key] ?? .null
    }

    subscript(index: Int) -> JSONValue {
        guard let items = array, items.indices.contains(index) else { return .null }
        return items[index]
    }

    var list: [JSONValue] { array ?? [] }
    var text: String { string ?? "" }
    var flag: Bool { self == .bool(true) }
    var whole: Int { integer ?? 0 }
    var texts: [String] { list.map { $0.text } }
    var numbers: [Double?] { list.map { $0.number } }

    /// Число из поля ввода в записи эталона: { kind: value | empty | invalid, value }.
    var parsedNumber: ParsedNumber {
        switch self["kind"].text {
        case "value": return .value(self["value"].number ?? .nan)
        case "empty": return .empty
        default: return .invalid
        }
    }

    func decoded<T: Decodable>(_ type: T.Type) throws -> T {
        try JSONDecoder().decode(type, from: JSONEncoder().encode(self))
    }

    /// Первое расхождение двух значений: путь и оба значения. nil — значения равны.
    func difference(from other: JSONValue, path: String = "") -> String? {
        switch (self, other) {
        case (.object(let mine), .object(let theirs)):
            for key in Set(mine.keys).union(theirs.keys).sorted() {
                guard let left = mine[key] else { return "\(path)/\(key): нет в ответе" }
                guard let right = theirs[key] else { return "\(path)/\(key): нет в эталоне" }
                if let found = left.difference(from: right, path: "\(path)/\(key)") { return found }
            }
            return nil
        case (.array(let mine), .array(let theirs)):
            if mine.count != theirs.count { return "\(path): \(mine.count) элементов, в эталоне \(theirs.count)" }
            for (index, pair) in zip(mine, theirs).enumerated() {
                if let found = pair.0.difference(from: pair.1, path: "\(path)/\(index)") { return found }
            }
            return nil
        default:
            return self == other ? nil : "\(path): \(self.brief), в эталоне \(other.brief)"
        }
    }

    private var brief: String {
        guard let data = try? JSONEncoder().encode(self), let text = String(data: data, encoding: .utf8) else { return "?" }
        return text.count > 200 ? String(text.prefix(200)) + "…" : text
    }
}

/// Момент времени в миллисекундах от 1970 года, как в веб-приложении.
func moment(_ milliseconds: Double) -> Date {
    Date(timeIntervalSince1970: milliseconds / 1000)
}

/// Часы и отложенные действия под управлением теста.
@MainActor
final class ManualClock {
    private struct Planned {
        var id: Int
        var at: Date
        var action: @MainActor () -> Void
    }

    var now: Date
    private var planned: [Planned] = []
    private var nextID = 0

    init(_ start: Date = Date(timeIntervalSince1970: 1_800_000_000)) {
        now = start
    }

    /// Расписание для SyncEngine: действие запоминается и выполняется, когда тест переведёт часы.
    var schedule: SyncSchedule {
        { [unowned self] delay, action in
            self.nextID += 1
            let id = self.nextID
            self.planned.append(Planned(id: id, at: self.now.addingTimeInterval(delay), action: action))
            return SyncTimer { [weak self] in
                self?.planned.removeAll { $0.id == id }
            }
        }
    }

    /// Паузы отложенных действий, которые ещё не выполнены, по возрастанию.
    var delays: [TimeInterval] {
        planned.map { $0.at.timeIntervalSince(now) }.sorted()
    }

    /// Переводит часы вперёд и выполняет всё, чему пришло время.
    func advance(_ seconds: TimeInterval) {
        now = now.addingTimeInterval(seconds)
        // запас в микросекунду: сумма двух шагов может на волосок не дойти до нужного момента
        let limit = now.addingTimeInterval(0.000_001)
        while let index = planned.indices.filter({ planned[$0].at <= limit }).min(by: { planned[$0].at < planned[$1].at }) {
            let item = planned.remove(at: index)
            item.action()
        }
    }
}

/// Мостик, который можно придержать: запрос ждёт, пока тест его не отпустит.
final class GateTransport: BridgeTransport, @unchecked Sendable {
    private let inner: BridgeTransport
    private let lock = NSLock()
    private var closed = false
    private var waiting: [CheckedContinuation<Void, Never>] = []

    init(_ inner: BridgeTransport) {
        self.inner = inner
    }

    func close() {
        lock.lock()
        closed = true
        lock.unlock()
    }

    func open() {
        lock.lock()
        closed = false
        let list = waiting
        waiting = []
        lock.unlock()
        for continuation in list { continuation.resume() }
    }

    /// Сколько запросов стоит у закрытых ворот.
    var held: Int {
        lock.lock()
        defer { lock.unlock() }
        return waiting.count
    }

    private func pass(_ continuation: CheckedContinuation<Void, Never>) {
        lock.lock()
        if closed {
            waiting.append(continuation)
            lock.unlock()
        } else {
            lock.unlock()
            continuation.resume()
        }
    }

    func post(url: URL, body: Data, timeout: TimeInterval) async throws -> TransportResponse {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            pass(continuation)
        }
        return try await inner.post(url: url, body: body, timeout: timeout)
    }

    /// Ждёт, пока запрос дойдёт до закрытых ворот; не дольше пяти секунд.
    func arrival() async {
        for _ in 0..<2500 where held == 0 {
            try? await Task.sleep(nanoseconds: 2_000_000)
        }
    }
}
