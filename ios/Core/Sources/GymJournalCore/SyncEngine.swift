import Foundation

/// Снимок журнала из таблицы.
public struct JournalSnapshot: Equatable, Codable, Sendable {
    public var journal: [JournalRow]
    /// Понедельник первой недели программы.
    public var start: String?
    /// Цель по ходьбе, километров в неделю.
    public var walkGoalKm: Double?
    public var tz: String
    /// Версия кода скрипта в таблице.
    public var script: Int?
    public var fetchedAt: Date

    public init(
        journal: [JournalRow], start: String? = nil, walkGoalKm: Double? = nil, tz: String = "",
        script: Int? = nil, fetchedAt: Date
    ) {
        self.journal = journal
        self.start = start
        self.walkGoalKm = walkGoalKm
        self.tz = tz
        self.script = script
        self.fetchedAt = fetchedAt
    }

    /// Снимок из ответа скрипта; nil, если журнала в ответе нет.
    public static func from(_ data: [String: JSONValue], fetchedAt: Date) -> JournalSnapshot? {
        guard data["journal"]?.array != nil else { return nil }
        var start = data["start"]?.string
        if let value = start, !Days.isISODate(value) { start = nil }
        return JournalSnapshot(
            journal: Journal.normalize(data["journal"]),
            start: start,
            walkGoalKm: data["walkGoalKm"]?.number,
            tz: data["tz"]?.string ?? "",
            script: data["script"]?.integer,
            fetchedAt: fetchedAt
        )
    }
}

public enum SyncPhase: String, Sendable {
    case unconfigured, idle, syncing, waiting, error
}

public struct SyncError: Equatable, Sendable {
    public var code: String
    public var message: String
    public var at: Date
}

public struct SyncResult: Equatable, Sendable {
    public var ok: Bool
    public var code: String
    public var message: String

    static let success = SyncResult(ok: true, code: "", message: "")
    static let superseded = SyncResult(ok: false, code: "superseded", message: "Подключение изменилось.")

    static func failure(_ code: String, _ message: String) -> SyncResult {
        SyncResult(ok: false, code: code, message: message)
    }
}

/// То, что видят экраны: журнал с наложенными правками и состояние обмена.
public struct SyncState: Sendable {
    public var configured: Bool
    public var connection: Connection?
    public var snapshot: JournalSnapshot?
    /// Журнал с наложенными неотправленными правками.
    public var journal: [JournalRow]
    public var pending: Int
    public var failed: [FailedItem]
    public var phase: SyncPhase
    public var error: SyncError?
    public var retryAt: Date?
    public var online: Bool
    /// false — телефон не дал сохранить очередь: записи пропадут, если закрыть приложение.
    public var outboxSaved: Bool
    /// Растёт, когда меняется журнал или очередь: по нему видно, что пора пересчитать производные данные.
    public var revision: Int
}

/// Отложенное действие, которое можно отменить.
public final class SyncTimer {
    private let onCancel: () -> Void

    public init(onCancel: @escaping () -> Void) {
        self.onCancel = onCancel
    }

    public func cancel() {
        onCancel()
    }
}

public typealias SyncSchedule = @MainActor (_ delay: TimeInterval, _ action: @escaping @MainActor () -> Void) -> SyncTimer

/// Синхронизация с таблицей: снимок журнала, очередь записей, повторы.
///
/// Очередь уходит в трёх случаях: сразу после правки, при возврате в приложение и при появлении
/// сети. Пока приложение открыто, неудачные попытки повторяются сами, с растущей паузой.
@MainActor
public final class SyncEngine {
    /// Паузы между повторами, секунды.
    public static let retrySteps: [TimeInterval] = [5, 15, 30, 60, 120, 300]
    /// Пауза перед отправкой, секунды: соседние правки (вес и подход) уходят одним запросом.
    public static let flushDelay: TimeInterval = 1.2
    static let pushLimit = 100
    static let maxRounds = 4

    // Ошибки, которые повтор не вылечит: нужен человек (ключ, развёртывание, структура таблицы).
    static let needsUser: Set<String> = [
        "unauthorized", "no_key", "layout_changed", "no_journal", "no_spreadsheet", "api_mismatch",
        "bad_request", "bad_json", "unknown_action", "too_large", "too_many",
    ]

    /// Отложенный запуск на главном потоке через Task.sleep.
    public static let taskSchedule: SyncSchedule = { delay, action in
        let task = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(max(0, delay) * 1_000_000_000))
            if Task.isCancelled { return }
            action()
        }
        return SyncTimer { task.cancel() }
    }

    private let storage: StateStorage
    private let secrets: StateStorage
    private let transport: BridgeTransport
    private let now: () -> Date
    private let isOnline: () -> Bool
    private let schedule: SyncSchedule
    /// Вызывается после любого изменения состояния.
    public var onChange: () -> Void

    private var conn: Connection?
    private var snapshot: JournalSnapshot?
    private var outbox: Outbox
    private var phase: SyncPhase
    private var error: SyncError?
    private var retryAt: Date?
    private var attempt = 0
    /// Растёт при смене подключения: ответы старого подключения не принимаются.
    private var generation = 0
    private var inFlight: Task<SyncResult, Never>?
    private var again = false
    private var flushTimer: SyncTimer?
    private var retryTimer: SyncTimer?
    private var outboxSaved = true
    private var view: [JournalRow]?
    private var revision = 0

    /// - Parameters:
    ///   - storage: снимок журнала и очередь записей.
    ///   - secrets: адрес и ключ; в приложении это связка ключей.
    public init(
        storage: StateStorage,
        secrets: StateStorage,
        transport: BridgeTransport,
        now: @escaping () -> Date = { Date() },
        isOnline: @escaping () -> Bool = { true },
        schedule: @escaping SyncSchedule = SyncEngine.taskSchedule,
        onChange: @escaping () -> Void = {}
    ) {
        self.storage = storage
        self.secrets = secrets
        self.transport = transport
        self.now = now
        self.isOnline = isOnline
        self.schedule = schedule
        self.onChange = onChange

        let saved = secrets.load(Connection.self, for: "conn")
        conn = (saved.map { !$0.url.isEmpty && !$0.key.isEmpty } ?? false) ? saved : nil
        snapshot = storage.load(JournalSnapshot.self, for: "snapshot")
        outbox = storage.load(Outbox.self, for: "outbox") ?? Outbox()
        phase = conn == nil ? .unconfigured : .idle
    }

    // MARK: Состояние

    public var state: SyncState {
        let journal: [JournalRow]
        if let view {
            journal = view
        } else {
            journal = snapshot.map { OutboxLogic.apply($0.journal, outbox) } ?? []
            view = journal
        }
        return SyncState(
            configured: conn != nil,
            connection: conn,
            snapshot: snapshot,
            journal: journal,
            pending: outbox.pendingCount,
            failed: outbox.failed,
            phase: phase,
            error: error,
            retryAt: retryAt,
            online: isOnline(),
            outboxSaved: outboxSaved,
            revision: revision
        )
    }

    /// Обмен, который идёт сейчас. Тесты ждут его конца.
    var running: Task<SyncResult, Never>? { inFlight }

    /// Строка журнала с наложенными правками по её ключу.
    public func row(for key: String) -> JournalRow? {
        state.journal.first { $0.key == key }
    }

    private func emit() {
        onChange()
    }

    private func touch() {
        view = nil
        revision += 1
    }

    private func saveOutbox() {
        outboxSaved = storage.save(outbox, for: "outbox")
        touch()
    }

    private func clearTimers() {
        flushTimer?.cancel()
        retryTimer?.cancel()
        flushTimer = nil
        retryTimer = nil
        retryAt = nil
    }

    private func acceptSnapshot(_ data: [String: JSONValue]) {
        guard let next = JournalSnapshot.from(data, fetchedAt: now()) else { return }
        snapshot = next
        storage.save(next, for: "snapshot")
        touch()
    }

    private func scheduleRetry(_ seconds: TimeInterval? = nil) {
        let delay = seconds ?? Self.retrySteps[min(attempt, Self.retrySteps.count - 1)]
        attempt += 1
        retryTimer?.cancel()
        retryAt = now().addingTimeInterval(delay)
        retryTimer = schedule(delay) { [weak self] in
            guard let self else { return }
            self.retryTimer = nil
            self.retryAt = nil
            self.sync()
        }
    }

    private func scheduleFlush(_ delay: TimeInterval = SyncEngine.flushDelay) {
        flushTimer?.cancel()
        flushTimer = schedule(delay) { [weak self] in
            guard let self else { return }
            self.flushTimer = nil
            self.sync()
        }
    }

    private static func describe(_ failure: Error) -> (code: String, message: String) {
        if let bridge = failure as? BridgeError { return (bridge.code, bridge.message) }
        if let mismatch = failure as? OutboxMismatch { return ("internal", mismatch.message) }
        return ("internal", "Неизвестная ошибка.")
    }

    // MARK: Обмен

    private func exchange(_ current: Connection, _ mine: Int) async throws -> Bool {
        for _ in 0..<Self.maxRounds {
            again = false
            let push = OutboxLogic.buildPush(outbox, limit: Self.pushLimit)
            let data: [String: JSONValue]
            if push.entries.isEmpty {
                data = try await Bridge.call(current, action: "pull", transport: transport)
            } else {
                data = try await Bridge.call(
                    current, action: "push",
                    payload: ["entries": .array(push.entries), "pull": .bool(true)],
                    transport: transport
                )
            }
            if mine != generation { return false } // подключение сменили, пока запрос был в пути
            if !push.entries.isEmpty {
                outbox = try OutboxLogic.ack(outbox, sent: push.sent, results: data["results"], now: now())
                saveOutbox()
            }
            acceptSnapshot(data)
            if outbox.pendingCount == 0 && !again { break }
            emit()
        }
        return true
    }

    private func run(_ current: Connection, _ mine: Int) async -> SyncResult {
        let result: SyncResult
        do {
            let accepted = try await exchange(current, mine)
            if accepted {
                phase = .idle
                error = nil
                attempt = 0
                if outbox.pendingCount > 0 { scheduleFlush() }
                result = .success
            } else {
                result = .superseded
            }
        } catch let failure {
            if mine != generation {
                result = .superseded
            } else {
                let info = Self.describe(failure)
                error = SyncError(code: info.code, message: info.message, at: now())
                if Self.needsUser.contains(info.code) {
                    phase = .error
                } else {
                    phase = .waiting
                    scheduleRetry(info.code == "busy" ? 5 : nil)
                }
                result = .failure(info.code, info.message)
            }
        }
        inFlight = nil
        // Подключение сменили, пока запрос был в пути: очередь уходит уже по новому подключению.
        if mine != generation, conn != nil, outbox.pendingCount > 0 { scheduleFlush(0) }
        emit()
        return result
    }

    /// Отправляет очередь и перечитывает журнал. Одновременно идёт только один обмен:
    /// повторный вызов во время обмена просит ещё один круг после него.
    @discardableResult
    public func sync() -> Task<SyncResult, Never> {
        guard let current = conn else {
            phase = .unconfigured
            emit()
            return Task { SyncResult.failure("unconfigured", "Таблица не подключена.") }
        }
        if let inFlight {
            again = true
            return inFlight
        }
        clearTimers()
        if !isOnline() {
            phase = .waiting
            error = SyncError(code: "offline", message: "Нет сети.", at: now())
            scheduleRetry(30)
            emit()
            return Task { SyncResult.failure("offline", "Нет сети.") }
        }
        let mine = generation
        phase = .syncing
        emit()
        let task = Task { @MainActor [weak self] () -> SyncResult in
            guard let self else { return SyncResult.superseded }
            return await self.run(current, mine)
        }
        inFlight = task
        return task
    }

    // MARK: Действия

    /// Правка строки журнала: сразу видна на экране, сохранена на телефоне и поставлена в очередь.
    public func queue(_ row: JournalRow, _ fields: RowFields) {
        let next = OutboxLogic.queue(outbox, row: row, fields: fields, now: now())
        if next == outbox { return }
        outbox = next
        saveOutbox()
        if inFlight != nil {
            again = true
        } else if conn != nil {
            scheduleFlush()
        }
        emit()
    }

    /// Возврат в приложение или появление сети: отправить очередь сейчас, не дожидаясь паузы.
    public func wake(staleAfter: TimeInterval = 60) {
        guard conn != nil, inFlight == nil else { return }
        let stale = snapshot.map { now().timeIntervalSince($0.fetchedAt) > staleAfter } ?? true
        if phase == .error && outbox.pendingCount == 0 && !stale { return }
        if outbox.pendingCount > 0 || stale || phase == .waiting {
            attempt = 0
            sync()
        }
    }

    /// Проверяет адрес и ключ чтением журнала. Подключение сохраняется, только если чтение удалось.
    public func connect(_ candidate: Connection) async -> SyncResult {
        guard !candidate.url.isEmpty, !candidate.key.isEmpty else {
            return .failure("bad_request", "Нужны адрес и ключ.")
        }
        let data: [String: JSONValue]
        do {
            data = try await Bridge.call(candidate, action: "pull", transport: transport)
        } catch let failure {
            let info = Self.describe(failure)
            return .failure(info.code, info.message)
        }
        generation += 1
        clearTimers()
        conn = candidate
        secrets.save(candidate, for: "conn")
        acceptSnapshot(data)
        phase = .idle
        error = nil
        attempt = 0
        if outbox.pendingCount > 0 { scheduleFlush(0) }
        emit()
        return .success
    }

    public func retryFailed(_ index: Int) {
        outbox = OutboxLogic.retryFailed(outbox, index: index, now: now())
        saveOutbox()
        if conn != nil { scheduleFlush(0) }
        emit()
    }

    public func dropFailed(_ index: Int) {
        outbox = OutboxLogic.dropFailed(outbox, index: index)
        saveOutbox()
        emit()
    }

    /// Забывает подключение, снимок и очередь на этом телефоне. Таблицу не трогает.
    public func reset() {
        generation += 1
        clearTimers()
        conn = nil
        snapshot = nil
        outbox = Outbox()
        secrets.remove("conn")
        storage.remove("snapshot")
        storage.remove("outbox")
        phase = .unconfigured
        error = nil
        attempt = 0
        outboxSaved = true
        touch()
        emit()
    }

    /// Останавливает таймеры: для тестов и закрытия приложения.
    public func stop() {
        clearTimers()
    }
}
