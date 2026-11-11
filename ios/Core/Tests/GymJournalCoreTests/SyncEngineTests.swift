import XCTest
@testable import GymJournalCore

/// Стенд: синхронизация поверх учебной таблицы, с часами и сетью под управлением теста.
@MainActor
private final class Rig {
    let clock = ManualClock()
    let storage = MemoryStorage()
    let secrets = MemoryStorage()
    let bridge: DemoBridge
    let transport: BridgeTransport
    var online = true
    var changes = 0
    private(set) var engine: SyncEngine!

    init(gated: Bool = false) throws {
        let table = try XCTUnwrap(DemoData.bridge())
        bridge = table
        transport = gated ? GateTransport(table) : table
        engine = make()
    }

    var gate: GateTransport? { transport as? GateTransport }

    /// Новый экземпляр на том же хранилище: как после перезапуска приложения.
    func make() -> SyncEngine {
        SyncEngine(
            storage: storage,
            secrets: secrets,
            transport: transport,
            now: { [unowned self] in self.clock.now },
            isOnline: { [unowned self] in self.online },
            schedule: clock.schedule,
            onChange: { [unowned self] in self.changes += 1 }
        )
    }

    func connect(file: StaticString = #filePath, line: UInt = #line) async {
        let result = await engine.connect(DemoData.connection)
        XCTAssertTrue(result.ok, result.message, file: file, line: line)
    }

    /// Ждёт конца обмена, который идёт сейчас.
    func settle() async {
        while let task = engine.running {
            _ = await task.value
        }
    }

    /// Проходит пауза перед отправкой, и обмен доходит до конца.
    func flush() async {
        clock.advance(SyncEngine.flushDelay)
        await settle()
    }

    /// Строка на экране: журнал с наложенными правками.
    func row(_ exercise: String, date: String = DemoData.today) throws -> JournalRow {
        let found = engine.state.journal.first { $0.date == date && $0.exercise == exercise }
        return try XCTUnwrap(found, "на экране нет строки «\(exercise)»")
    }

    /// Строка в таблице.
    func sheetRow(_ exercise: String, date: String = DemoData.today) throws -> JournalRow {
        let found = bridge.journal.first { $0.date == date && $0.exercise == exercise }
        return try XCTUnwrap(found, "в таблице нет строки «\(exercise)»")
    }

    func assertDelays(_ want: [TimeInterval], file: StaticString = #filePath, line: UInt = #line) {
        let got = clock.delays
        XCTAssertEqual(got.count, want.count, "отложено: \(got)", file: file, line: line)
        for (left, right) in zip(got, want) {
            XCTAssertEqual(left, right, accuracy: 0.001, "отложено: \(got)", file: file, line: line)
        }
    }
}

@MainActor
final class SyncEngineTests: XCTestCase {
    func testStartsWithoutConnection() async throws {
        let rig = try Rig()
        let state = rig.engine.state
        XCTAssertFalse(state.configured)
        XCTAssertEqual(state.phase, .unconfigured)
        XCTAssertTrue(state.journal.isEmpty)
        let result = await rig.engine.sync().value
        XCTAssertFalse(result.ok)
        XCTAssertEqual(result.code, "unconfigured")
        XCTAssertTrue(rig.bridge.requests.isEmpty)
    }

    func testConnectReadsJournalAndRemembersConnection() async throws {
        let rig = try Rig()
        await rig.connect()
        let state = rig.engine.state
        XCTAssertTrue(state.configured)
        XCTAssertEqual(state.phase, .idle)
        XCTAssertEqual(state.connection, DemoData.connection)
        XCTAssertEqual(state.journal.count, 269)
        XCTAssertEqual(state.snapshot?.start, "2026-11-09")
        XCTAssertEqual(state.snapshot?.walkGoalKm, 17)
        XCTAssertEqual(state.snapshot?.script, Bridge.expectedScript)
        XCTAssertEqual(state.snapshot?.fetchedAt, rig.clock.now)
        XCTAssertEqual(rig.secrets.load(Connection.self, for: "conn"), DemoData.connection)
        XCTAssertNotNil(rig.storage.data(for: "snapshot"))
        XCTAssertNil(rig.storage.data(for: "conn"), "ключ не лежит рядом с журналом")
        XCTAssertGreaterThan(rig.changes, 0)
        rig.assertDelays([])
    }

    func testWrongKeyIsNotSaved() async throws {
        let rig = try Rig()
        let result = await rig.engine.connect(Connection(url: DemoData.url, key: "не тот ключ"))
        XCTAssertFalse(result.ok)
        XCTAssertEqual(result.code, "unauthorized")
        XCTAssertFalse(rig.engine.state.configured)
        XCTAssertNil(rig.secrets.data(for: "conn"))

        let empty = await rig.engine.connect(Connection(url: "", key: ""))
        XCTAssertEqual(empty.code, "bad_request")
        XCTAssertEqual(rig.bridge.requests.count, 1)
    }

    func testEditIsShownAtOnceAndSentAfterPause() async throws {
        let rig = try Rig()
        await rig.connect()
        let before = rig.bridge.requests.count
        let revision = rig.engine.state.revision

        rig.engine.queue(try rig.row("Гакк-жим"), RowFields(weight: .set(22.5), sets: [12, nil, nil]))
        XCTAssertEqual(rig.engine.state.pending, 1)
        XCTAssertGreaterThan(rig.engine.state.revision, revision)
        let shown = try rig.row("Гакк-жим")
        XCTAssertEqual(shown.weight, 22.5)
        XCTAssertEqual(shown.sets, [12, nil, nil])
        XCTAssertTrue(shown.pending)
        XCTAssertNotNil(rig.storage.data(for: "outbox"))
        XCTAssertEqual(rig.bridge.requests.count, before, "запрос уходит не сразу")
        rig.assertDelays([SyncEngine.flushDelay])

        // соседняя правка до отправки: обе уйдут одним запросом
        rig.engine.queue(shown, RowFields(sets: [12, 11, nil]))
        rig.assertDelays([SyncEngine.flushDelay])
        rig.clock.advance(SyncEngine.flushDelay)
        XCTAssertEqual(rig.engine.state.phase, .syncing)
        await rig.settle()

        let state = rig.engine.state
        XCTAssertEqual(state.pending, 0)
        XCTAssertEqual(state.phase, .idle)
        XCTAssertEqual(rig.bridge.requests.count, before + 1)
        let request = try XCTUnwrap(rig.bridge.requests.last)
        XCTAssertEqual(request["action"]?.string, "push")
        XCTAssertEqual(request["pull"], .bool(true))
        XCTAssertEqual(request["entries"]?.array?.count, 1)

        let written = try rig.sheetRow("Гакк-жим")
        XCTAssertEqual(written.weight, 22.5)
        XCTAssertEqual(written.sets, [12, 11, nil])
        let after = try rig.row("Гакк-жим")
        XCTAssertFalse(after.pending)
        XCTAssertEqual(after.sets, [12, 11, nil])
        rig.assertDelays([])
    }

    func testEmptyEditIsIgnored() async throws {
        let rig = try Rig()
        await rig.connect()
        rig.engine.queue(try rig.row("Гакк-жим"), RowFields())
        XCTAssertEqual(rig.engine.state.pending, 0)
        rig.assertDelays([])
    }

    func testOfflineKeepsQueueAndSendsWhenNetworkReturns() async throws {
        let rig = try Rig()
        await rig.connect()
        rig.online = false
        rig.engine.queue(try rig.row("Гакк-жим"), RowFields(weight: .set(20)))
        rig.clock.advance(SyncEngine.flushDelay)

        var state = rig.engine.state
        XCTAssertEqual(state.phase, .waiting)
        XCTAssertEqual(state.error?.code, "offline")
        XCTAssertFalse(state.online)
        XCTAssertEqual(state.pending, 1)
        rig.assertDelays([30])
        XCTAssertNil(try rig.sheetRow("Гакк-жим").weight)

        rig.online = true
        rig.engine.wake()
        await rig.settle()
        state = rig.engine.state
        XCTAssertEqual(state.phase, .idle)
        XCTAssertNil(state.error)
        XCTAssertEqual(state.pending, 0)
        XCTAssertEqual(try rig.sheetRow("Гакк-жим").weight, 20)
        rig.assertDelays([])
    }

    func testLostConnectionIsRetriedWithGrowingPause() async throws {
        let rig = try Rig()
        await rig.connect()
        rig.bridge.setMode(.down)
        rig.engine.queue(try rig.row("Гакк-жим"), RowFields(weight: .set(20)))
        await rig.flush()

        var state = rig.engine.state
        XCTAssertEqual(state.phase, .waiting)
        XCTAssertEqual(state.error?.code, "network")
        XCTAssertEqual(state.retryAt, rig.clock.now.addingTimeInterval(5))
        XCTAssertEqual(state.pending, 1)
        rig.assertDelays([5])

        rig.clock.advance(5)
        await rig.settle()
        rig.assertDelays([15])
        rig.clock.advance(15)
        await rig.settle()
        rig.assertDelays([30])

        rig.bridge.setMode(.ok)
        rig.clock.advance(30)
        await rig.settle()
        state = rig.engine.state
        XCTAssertEqual(state.phase, .idle)
        XCTAssertEqual(state.pending, 0)
        XCTAssertNil(state.retryAt)
        XCTAssertNil(state.error)
        rig.assertDelays([])

        // после удачи счёт пауз начинается заново
        rig.bridge.setMode(.down)
        rig.engine.queue(try rig.row("Сведение рук"), RowFields(weight: .set(15)))
        await rig.flush()
        rig.assertDelays([5])
    }

    func testPageInsteadOfDataIsRetried() async throws {
        let rig = try Rig()
        await rig.connect()
        rig.bridge.setMode(.html)
        rig.engine.queue(try rig.row("Гакк-жим"), RowFields(weight: .set(20)))
        await rig.flush()
        XCTAssertEqual(rig.engine.state.phase, .waiting)
        XCTAssertEqual(rig.engine.state.error?.code, "not_json")
        rig.assertDelays([5])
    }

    func testBusySheetIsRetriedSoon() async throws {
        let rig = try Rig()
        await rig.connect()
        rig.bridge.setMode(.busy)
        rig.engine.queue(try rig.row("Гакк-жим"), RowFields(weight: .set(20)))
        await rig.flush()
        XCTAssertEqual(rig.engine.state.phase, .waiting)
        XCTAssertEqual(rig.engine.state.error?.code, "busy")
        rig.assertDelays([5])
        rig.clock.advance(5)
        await rig.settle()
        rig.assertDelays([5])

        rig.bridge.setMode(.ok)
        rig.clock.advance(5)
        await rig.settle()
        XCTAssertEqual(rig.engine.state.pending, 0)
        XCTAssertEqual(try rig.sheetRow("Гакк-жим").weight, 20)
    }

    func testWrongKeyStopsRetriesUntilUserActs() async throws {
        let rig = try Rig()
        await rig.connect()
        rig.bridge.setKey("другой ключ")
        rig.engine.queue(try rig.row("Гакк-жим"), RowFields(weight: .set(20)))
        await rig.flush()

        var state = rig.engine.state
        XCTAssertEqual(state.phase, .error)
        XCTAssertEqual(state.error?.code, "unauthorized")
        XCTAssertEqual(state.pending, 1, "запись остаётся в телефоне")
        rig.assertDelays([])

        rig.bridge.setKey(DemoData.key)
        rig.engine.wake()
        await rig.settle()
        state = rig.engine.state
        XCTAssertEqual(state.phase, .idle)
        XCTAssertEqual(state.pending, 0)
        XCTAssertEqual(try rig.sheetRow("Гакк-жим").weight, 20)
    }

    func testRejectedEntryIsShownAndCanBeRetried() async throws {
        let rig = try Rig()
        await rig.connect()
        let hack = try rig.row("Гакк-жим")
        // строку удалили из таблицы, пока приложение было закрыто
        rig.bridge.edit { rows in
            rows.removeAll { $0.key == hack.key }
        }
        rig.engine.queue(hack, RowFields(weight: .set(20)))
        rig.engine.queue(try rig.row("Сведение рук"), RowFields(weight: .set(15)))
        await rig.flush()

        var state = rig.engine.state
        XCTAssertEqual(state.phase, .idle)
        XCTAssertEqual(state.pending, 0)
        XCTAssertEqual(state.failed.count, 1)
        XCTAssertEqual(state.failed.first?.status, "not_found")
        XCTAssertEqual(state.failed.first?.item.key, hack.key)
        XCTAssertFalse(state.journal.contains { $0.key == hack.key })
        XCTAssertEqual(try rig.sheetRow("Сведение рук").weight, 15)

        // строку вернули: запись можно отправить снова
        rig.bridge.edit { rows in
            rows.append(hack)
        }
        rig.engine.retryFailed(0)
        XCTAssertEqual(rig.engine.state.pending, 1)
        XCTAssertTrue(rig.engine.state.failed.isEmpty)
        rig.assertDelays([0])
        rig.clock.advance(0)
        await rig.settle()
        state = rig.engine.state
        XCTAssertEqual(state.pending, 0)
        XCTAssertTrue(state.failed.isEmpty)
        XCTAssertEqual(try rig.sheetRow("Гакк-жим").weight, 20)
    }

    func testRejectedEntryCanBeDropped() async throws {
        let rig = try Rig()
        await rig.connect()
        let hack = try rig.row("Гакк-жим")
        rig.bridge.edit { rows in
            rows.removeAll { $0.key == hack.key }
        }
        rig.engine.queue(hack, RowFields(weight: .set(20)))
        await rig.flush()
        XCTAssertEqual(rig.engine.state.failed.count, 1)

        rig.engine.dropFailed(0)
        XCTAssertTrue(rig.engine.state.failed.isEmpty)
        let saved = try XCTUnwrap(rig.storage.load(Outbox.self, for: "outbox"))
        XCTAssertTrue(saved.failed.isEmpty)
        rig.assertDelays([])
    }

    func testEditMadeWhileRequestIsOnItsWayIsSentNext() async throws {
        let rig = try Rig(gated: true)
        let gate = try XCTUnwrap(rig.gate)
        await rig.connect()
        gate.close()
        rig.engine.queue(try rig.row("Гакк-жим"), RowFields(weight: .set(20)))
        rig.clock.advance(SyncEngine.flushDelay)
        await gate.arrival()
        XCTAssertEqual(gate.held, 1)
        let before = rig.bridge.requests.count

        // запрос в пути: ту же строку правят ещё раз
        rig.engine.queue(try rig.row("Гакк-жим"), RowFields(sets: [12, nil, nil]))
        rig.assertDelays([])
        gate.open()
        await rig.settle()

        XCTAssertEqual(rig.engine.state.pending, 0)
        XCTAssertEqual(rig.bridge.requests.count, before + 2, "вторая правка ушла следующим запросом")
        let written = try rig.sheetRow("Гакк-жим")
        XCTAssertEqual(written.weight, 20)
        XCTAssertEqual(written.sets, [12, nil, nil])
        XCTAssertFalse(try rig.row("Гакк-жим").pending)
    }

    func testAnswerForForgottenConnectionIsDropped() async throws {
        let rig = try Rig(gated: true)
        let gate = try XCTUnwrap(rig.gate)
        await rig.connect()
        gate.close()
        let task = rig.engine.sync()
        await gate.arrival()

        rig.engine.reset()
        gate.open()
        let result = await task.value
        XCTAssertFalse(result.ok)
        XCTAssertEqual(result.code, "superseded")

        let state = rig.engine.state
        XCTAssertFalse(state.configured)
        XCTAssertEqual(state.phase, .unconfigured)
        XCTAssertNil(state.snapshot)
        XCTAssertNil(rig.storage.data(for: "snapshot"))
    }

    func testSecondSyncJoinsTheRunningOne() async throws {
        let rig = try Rig(gated: true)
        let gate = try XCTUnwrap(rig.gate)
        await rig.connect()
        let before = rig.bridge.requests.count
        gate.close()
        let first = rig.engine.sync()
        await gate.arrival()
        let second = rig.engine.sync()
        gate.open()
        let results = [await first.value, await second.value]
        XCTAssertTrue(results.allSatisfy { $0.ok })
        // повторный вызов во время обмена просит ещё один круг после него
        XCTAssertEqual(rig.bridge.requests.count, before + 2)
    }

    func testQueueSurvivesRestart() async throws {
        let rig = try Rig()
        await rig.connect()
        rig.engine.queue(try rig.row("Гакк-жим"), RowFields(weight: .set(20)))
        rig.engine.stop()
        rig.assertDelays([])

        let second = rig.make()
        let state = second.state
        XCTAssertTrue(state.configured)
        XCTAssertEqual(state.phase, .idle)
        XCTAssertEqual(state.pending, 1)
        XCTAssertEqual(second.row(for: "\(DemoData.today)|Гакк-жим|0")?.weight, 20)

        // возврат в приложение отправляет очередь
        second.wake()
        while let task = second.running {
            _ = await task.value
        }
        XCTAssertEqual(second.state.pending, 0)
        XCTAssertEqual(try rig.sheetRow("Гакк-жим").weight, 20)
    }

    func testWakeRefreshesStaleJournalOnly() async throws {
        let rig = try Rig()
        await rig.connect()
        let before = rig.bridge.requests.count

        rig.engine.wake()
        XCTAssertNil(rig.engine.running, "свежий журнал не перечитывается")
        XCTAssertEqual(rig.bridge.requests.count, before)

        rig.clock.advance(61)
        // вес поправили в таблице с компьютера
        rig.bridge.edit { rows in
            if let index = rows.firstIndex(where: { $0.date == DemoData.today && $0.exercise == "Гакк-жим" }) {
                rows[index].weight = 30
            }
        }
        rig.engine.wake()
        await rig.settle()
        XCTAssertEqual(rig.bridge.requests.count, before + 1)
        XCTAssertEqual(rig.bridge.requests.last?["action"]?.string, "pull")
        XCTAssertEqual(try rig.row("Гакк-жим").weight, 30)
    }

    func testPhoneThatCannotSaveIsReported() async throws {
        let rig = try Rig()
        await rig.connect()
        rig.storage.writable = false
        rig.engine.queue(try rig.row("Гакк-жим"), RowFields(weight: .set(20)))
        XCTAssertFalse(rig.engine.state.outboxSaved)
        XCTAssertEqual(rig.engine.state.pending, 1, "правка есть хотя бы в памяти")

        rig.storage.writable = true
        rig.engine.queue(try rig.row("Сведение рук"), RowFields(weight: .set(15)))
        XCTAssertTrue(rig.engine.state.outboxSaved)
    }

    func testLongQueueGoesInSeveralRequests() async throws {
        let rig = try Rig()
        await rig.connect()
        let before = rig.bridge.requests.count
        let future = rig.engine.state.journal.filter { !$0.isWalk && $0.date > DemoData.today }.prefix(120)
        XCTAssertEqual(future.count, 120)
        for row in future {
            rig.engine.queue(row, RowFields(weight: .set(20)))
        }
        XCTAssertEqual(rig.engine.state.pending, 120)
        await rig.flush()
        XCTAssertEqual(rig.engine.state.pending, 0)
        XCTAssertEqual(rig.bridge.requests.count, before + 2)
        XCTAssertEqual(rig.bridge.journal.filter { $0.weight == 20 && $0.date > DemoData.today }.count, 120)
    }

    func testResetForgetsEverythingOnThePhone() async throws {
        let rig = try Rig()
        await rig.connect()
        rig.engine.queue(try rig.row("Гакк-жим"), RowFields(weight: .set(20)))
        rig.engine.reset()

        let state = rig.engine.state
        XCTAssertFalse(state.configured)
        XCTAssertEqual(state.phase, .unconfigured)
        XCTAssertTrue(state.journal.isEmpty)
        XCTAssertEqual(state.pending, 0)
        XCTAssertNil(rig.secrets.data(for: "conn"))
        XCTAssertNil(rig.storage.data(for: "snapshot"))
        XCTAssertNil(rig.storage.data(for: "outbox"))
        rig.assertDelays([])
        // таблицу сброс не трогает
        XCTAssertEqual(rig.bridge.journal, Fixture.journal)
    }

    func testRealScheduleFiresAndCancels() async throws {
        var fired = 0
        let first = SyncEngine.taskSchedule(0.01) { fired += 1 }
        let second = SyncEngine.taskSchedule(0.01) { fired += 10 }
        second.cancel()
        try await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertEqual(fired, 1)
        first.cancel()
    }

    func testSnapshotNeedsJournal() {
        let at = moment(0)
        XCTAssertNil(JournalSnapshot.from(["ok": .bool(true)], fetchedAt: at))
        let snapshot = JournalSnapshot.from(["journal": .array([]), "start": .string("скоро"), "tz": .number(3)], fetchedAt: at)
        XCTAssertEqual(snapshot?.journal, [])
        XCTAssertNil(snapshot?.start, "дата старта не похожа на дату")
        XCTAssertEqual(snapshot?.tz, "")
    }
}
