import XCTest
@testable import GymJournalCore

/// Обмен телефона с часами: состояние дня, действия часов и их подтверждение.
final class WatchLinkTests: XCTestCase {
    private let rows = Fixture.journal
    private let today = Fixture.today
    private let at = moment(1_800_000_000_000)

    private func dayState(live: String? = nil, today: String = Fixture.today, settings: AppSettings = AppSettings()) -> WatchState {
        WatchLink.dayState(journal: rows, today: today, live: live, settings: settings, configured: true)
    }

    // MARK: Состояние дня

    func testStateOfWorkoutDay() {
        var settings = AppSettings()
        settings.restSec = 120
        settings.autoTimer = false
        settings.setStep(1.25, for: "Гакк-жим")
        let state = dayState(settings: settings)

        XCTAssertTrue(state.configured)
        XCTAssertEqual(state.today, today)
        XCTAssertEqual(state.date, today)
        XCTAssertEqual(state.title, "Силовая B и ходьба")
        XCTAssertEqual(state.week, 3)
        XCTAssertEqual(state.rows, Fixture.day(today))
        XCTAssertEqual(state.restSec, 120)
        XCTAssertFalse(state.autoTimer)
        XCTAssertTrue(state.health)
        XCTAssertEqual(state.next, "")

        // «прошлый раз» и шаг веса — только у силовых строк
        let strength = Fixture.day(today).filter { !$0.isWalk }
        XCTAssertEqual(Set(state.last.keys), Set(strength.map { $0.key }))
        XCTAssertEqual(Set(state.steps.keys), Set(strength.map { $0.key }))
        XCTAssertEqual(state.last["\(today)|Сгибание ног|0"]?.date, "2026-11-23")
        XCTAssertEqual(state.steps["\(today)|Гакк-жим|0"], 1.25)
        XCTAssertEqual(state.steps["\(today)|Сведение рук|0"], 2.5)
    }

    func testStateOfRestDay() {
        let state = dayState(today: "2026-11-28")
        XCTAssertNil(state.date)
        XCTAssertTrue(state.rows.isEmpty)
        XCTAssertEqual(state.title, "")
        XCTAssertEqual(state.next, "пн 30.11 · Силовая A и ходьба")
    }

    func testCatchUpDayIsShownInsteadOfToday() {
        let state = dayState(live: "2026-11-19")
        XCTAssertEqual(state.date, "2026-11-19")
        XCTAssertEqual(state.today, today)
        XCTAssertEqual(state.title, "Ходьба или интервалы")
        XCTAssertTrue(state.last.isEmpty)
        // дня, которого в журнале нет, часы не показывают: остаётся сегодняшний
        XCTAssertEqual(dayState(live: "2026-11-22").date, today)
    }

    func testStateTravelsAsData() throws {
        var state = dayState()
        state.stamp = WatchLink.nextStamp(after: 0, now: at)
        XCTAssertEqual(state.stamp, 1_800_000_000_000)
        XCTAssertEqual(WatchLink.nextStamp(after: state.stamp, now: at), 1_800_000_000_001)
        state.rest = RestTimer.start(now: at, seconds: 90)
        state.workout = LiveWorkout(id: "w1", kind: .strength, startedAt: at, date: today, onWatch: true)
        state.intent = WorkoutIntent(id: state.stamp, kind: .walk, date: today, indoor: false, at: at)
        state.ackEpoch = "часы-1"
        state.ackSeq = 7

        let data = try XCTUnwrap(WatchLink.encode(state))
        XCTAssertEqual(WatchLink.decode(WatchState.self, from: data), state)
        XCTAssertNil(WatchLink.decode(WatchState.self, from: Data("{}".utf8)))
        XCTAssertNil(WatchLink.decode(WatchState.self, from: nil))
    }

    func testPacketTravelsAsData() throws {
        let actions: [WatchAction] = [
            .reps(key: "k", index: 1, value: 12),
            .reps(key: "k", index: 2, value: nil),
            .weight(key: "k", value: 27.5),
            .weight(key: "k", value: nil),
            .walkAdd(key: "w", km: 1.5, min: nil),
            .rest(RestTimer.start(now: at, seconds: 90)),
            .rest(nil),
            .workoutStarted(LiveWorkout(id: "w1", kind: .walk, startedAt: at, date: today, onWatch: true, indoor: false)),
            .workoutEnded(WorkoutSummary(
                id: "w1", kind: .walk, date: today, startedAt: at, endedAt: at.addingTimeInterval(1790), km: 2.4, kcal: 150
            )),
        ]
        let ops = actions.enumerated().map { WatchOp(seq: $0.offset + 1, at: at, action: $0.element) }
        let packet = WatchPacket(epoch: "часы-1", ops: ops, intentDone: 1_800_000_000_123)
        let data = try XCTUnwrap(WatchLink.encode(packet))
        XCTAssertEqual(WatchLink.decode(WatchPacket.self, from: data), packet)
    }

    func testWorkoutMinutesAreRounded() {
        let summary = WorkoutSummary(id: "w", kind: .walk, date: today, startedAt: at, endedAt: at.addingTimeInterval(1790))
        XCTAssertEqual(summary.minutes, 30)
        let backwards = WorkoutSummary(id: "w", kind: .walk, date: today, startedAt: at, endedAt: at.addingTimeInterval(-60))
        XCTAssertEqual(backwards.minutes, 0)
        XCTAssertTrue(summary.saved)
    }

    // MARK: Телефон принимает действия

    func testPhoneAppliesEachActionOnce() {
        let ops = (1...4).map { WatchOp(seq: $0, at: at, action: .rest(nil)) }
        func seqs(_ list: [WatchOp]) -> [Int] { list.map { $0.seq } }

        var accepted = WatchLink.accept(WatchPacket(epoch: "a", ops: ops), epoch: "a", seq: 0)
        XCTAssertEqual(seqs(accepted.ops), [1, 2, 3, 4])
        XCTAssertEqual(accepted.seq, 4)

        // посылка пришла второй раз вместе с новым действием
        let more = ops + [WatchOp(seq: 5, at: at, action: .rest(nil))]
        accepted = WatchLink.accept(WatchPacket(epoch: "a", ops: more), epoch: "a", seq: 4)
        XCTAssertEqual(seqs(accepted.ops), [5])
        XCTAssertEqual(accepted.seq, 5)

        // порядок в посылке не важен, повтор внутри неё не применяется дважды
        let mixed = [ops[3], ops[1], ops[1], ops[2]]
        accepted = WatchLink.accept(WatchPacket(epoch: "a", ops: mixed), epoch: "a", seq: 1)
        XCTAssertEqual(seqs(accepted.ops), [2, 3, 4])
        XCTAssertEqual(accepted.seq, 4)

        // всё уже принято
        accepted = WatchLink.accept(WatchPacket(epoch: "a", ops: ops), epoch: "a", seq: 9)
        XCTAssertTrue(accepted.ops.isEmpty)
        XCTAssertEqual(accepted.seq, 9)

        // приложение на часах переустановили: счёт действий идёт заново
        accepted = WatchLink.accept(WatchPacket(epoch: "b", ops: Array(ops.prefix(2))), epoch: "a", seq: 9)
        XCTAssertEqual(seqs(accepted.ops), [1, 2])
        XCTAssertEqual(accepted.seq, 2)
        accepted = WatchLink.accept(WatchPacket(epoch: "b", ops: []), epoch: "a", seq: 9)
        XCTAssertEqual(accepted.seq, 0)
    }

    func testPatchFromWatchAction() throws {
        var hack = try Fixture.row(today, "Гакк-жим")
        let walk = try Fixture.row(today, "Ходьба до и после силовой")
        let key = hack.key
        var before = hack
        before.date = "2026-11-18"
        before.weight = 20

        // первый подход закрепляет вес, подставленный с прошлого раза
        XCTAssertEqual(
            WatchLink.patch(for: .reps(key: key, index: 0, value: 12), row: hack, last: before),
            RowFields(weight: .set(20), sets: [12, nil, nil])
        )
        XCTAssertEqual(
            WatchLink.patch(for: .reps(key: key, index: 1, value: 11), row: hack, last: nil),
            RowFields(sets: [nil, 11, nil])
        )

        hack.weight = 22.5
        hack.sets = [12, nil, nil]
        XCTAssertEqual(
            WatchLink.patch(for: .reps(key: key, index: 1, value: 11), row: hack, last: before),
            RowFields(sets: [12, 11, nil])
        )
        XCTAssertNil(WatchLink.patch(for: .reps(key: key, index: 0, value: 12), row: hack, last: before), "то же число")
        XCTAssertEqual(
            WatchLink.patch(for: .reps(key: key, index: 0, value: nil), row: hack, last: before),
            RowFields(sets: [nil, nil, nil])
        )
        XCTAssertNil(WatchLink.patch(for: .reps(key: key, index: 3, value: 5), row: hack, last: nil))
        XCTAssertNil(WatchLink.patch(for: .reps(key: key, index: -1, value: 5), row: hack, last: nil))
        XCTAssertNil(WatchLink.patch(for: .reps(key: walk.key, index: 0, value: 5), row: walk, last: nil))

        XCTAssertEqual(WatchLink.patch(for: .weight(key: key, value: 25), row: hack, last: nil), RowFields(weight: .set(25)))
        XCTAssertEqual(WatchLink.patch(for: .weight(key: key, value: nil), row: hack, last: nil), RowFields(weight: .set(nil)))
        XCTAssertNil(WatchLink.patch(for: .weight(key: key, value: 22.5), row: hack, last: nil))
        XCTAssertNil(WatchLink.patch(for: .weight(key: walk.key, value: 5), row: walk, last: nil))

        XCTAssertEqual(
            WatchLink.patch(for: .walkAdd(key: walk.key, km: 1.5, min: 18), row: walk, last: nil),
            RowFields(km: .set(1.5), min: .set(18))
        )
        var walked = walk
        walked.km = 1.5
        walked.min = 18
        XCTAssertEqual(
            WatchLink.patch(for: .walkAdd(key: walk.key, km: 1.25, min: 14.5), row: walked, last: nil),
            RowFields(km: .set(2.75), min: .set(32.5))
        )
        XCTAssertEqual(
            WatchLink.patch(for: .walkAdd(key: walk.key, km: 2, min: nil), row: walked, last: nil),
            RowFields(km: .set(3.5))
        )
        XCTAssertNil(WatchLink.patch(for: .walkAdd(key: walk.key, km: 0, min: nil), row: walked, last: nil))
        XCTAssertNil(WatchLink.patch(for: .walkAdd(key: walk.key, km: nil, min: -3), row: walked, last: nil))
        XCTAssertNil(WatchLink.patch(for: .walkAdd(key: key, km: 1, min: 10), row: hack, last: nil))

        XCTAssertNil(WatchLink.patch(for: .rest(nil), row: hack, last: nil))
        XCTAssertNil(WatchLink.rowKey(of: .rest(nil)))
        XCTAssertEqual(WatchLink.rowKey(of: .weight(key: "k", value: 1)), "k")
    }

    // MARK: Часы показывают свои действия

    func testWatchShowsOwnActionsUntilPhoneConfirms() throws {
        var state = dayState()
        state.ackEpoch = "a"
        state.ackSeq = 2
        let curl = try Fixture.row(today, "Сгибание ног")
        let timer = RestTimer.start(now: at, seconds: 90)
        let ops = [
            WatchOp(seq: 1, at: at, action: .weight(key: curl.key, value: 15)),
            WatchOp(seq: 2, at: at, action: .rest(nil)),
            WatchOp(seq: 3, at: at, action: .reps(key: curl.key, index: 0, value: 12)),
            WatchOp(seq: 4, at: at, action: .rest(timer)),
        ]

        let pending = WatchLink.pending(ops, state: state, epoch: "a")
        XCTAssertEqual(pending.map { $0.seq }, [3, 4])
        XCTAssertEqual(WatchLink.pending(ops, state: state, epoch: "b").count, 4, "телефон подтверждал другую установку")

        let shown = WatchLink.apply(pending, to: state.rows, last: state.last)
        let row = try XCTUnwrap(shown.first { $0.key == curl.key })
        XCTAssertEqual(row.sets, [12, nil, nil])
        XCTAssertEqual(row.weight, 17.5, "первый подход закрепляет прошлый вес")
        XCTAssertTrue(row.pending)
        XCTAssertEqual(shown.filter { $0.pending }.count, 1)

        // отдых: свой, пока телефон его не подтвердил
        XCTAssertEqual(WatchLink.rest(pending: pending, state: state), timer)
        state.rest = timer.extended(now: at, seconds: 30)
        XCTAssertEqual(WatchLink.rest(pending: [], state: state), state.rest)
        XCTAssertNil(WatchLink.rest(pending: [ops[1]], state: state), "отдых остановили на часах")
        XCTAssertEqual(WatchLink.apply([], to: state.rows, last: state.last), state.rows)
    }

    func testNextTargetFollowsThePair() {
        var day = Fixture.day(today)
        func target(_ pair: Int, _ row: Int, _ index: Int) -> String? {
            let pairs = Journal.splitDay(day).pairs
            return WatchLink.nextTarget(pairs: pairs, pair: pairs[pair], key: day[row].key, index: index)
        }

        // записан первый подход первого упражнения: дальше сосед по паре
        day[0].weight = 17.5
        day[0].sets = [12, nil, nil]
        XCTAssertEqual(target(0, 0, 0), day[1].key)

        // сосед записал свой: следующий подход начинает первое упражнение
        day[1].weight = 27.5
        day[1].sets = [12, nil, nil]
        XCTAssertEqual(target(0, 1, 0), day[0].key)

        // у первого два подхода по плану, у второго три: третий он делает один
        day[0].sets = [12, 11, nil]
        day[1].sets = [12, 11, nil]
        XCTAssertEqual(target(0, 1, 1), day[1].key)

        // пара закончена: следующая пара
        day[1].sets = [12, 11, 10]
        XCTAssertEqual(target(0, 1, 2), day[2].key)

        // весь день записан
        for index in day.indices where !day[index].isWalk {
            day[index].weight = 20
            day[index].sets = [12, 12, 12]
        }
        XCTAssertNil(target(2, 5, 1))
    }

    // MARK: Тренировка

    func testWorkoutKindsForDay() {
        XCTAssertEqual(WatchLink.kinds(for: Fixture.day(today)), [.strength, .walk])
        XCTAssertEqual(WatchLink.kinds(for: Fixture.day("2026-11-26")), [.walk])
        XCTAssertEqual(WatchLink.kinds(for: Fixture.day(today).filter { !$0.isWalk }), [.strength])
        XCTAssertEqual(WatchLink.kinds(for: []), [])
        XCTAssertEqual(WorkoutKind.strength.title, "Силовая")
        XCTAssertEqual(WorkoutKind.walk.title, "Ходьба")

        // дорожка — занятие в помещении, прогулка — на улице
        XCTAssertTrue(WatchLink.isIndoorWalk(Fixture.day(today)))
        var outdoor = Fixture.day("2026-11-26")
        outdoor[0].machine = "Парк"
        XCTAssertFalse(WatchLink.isIndoorWalk(outdoor))
        outdoor[0].machine = "  "
        XCTAssertTrue(WatchLink.isIndoorWalk(outdoor))
        XCTAssertTrue(WatchLink.isIndoorWalk([]))
    }

    func testStartRequestExpires() {
        let start = WorkoutIntent(id: 1, kind: .strength, date: today, at: at)
        XCTAssertTrue(start.isFresh(now: at.addingTimeInterval(60)))
        XCTAssertTrue(start.isFresh(now: at.addingTimeInterval(-30)), "часы немного отстают")
        XCTAssertFalse(start.isFresh(now: at.addingTimeInterval(121)))
        // закончить тренировку можно когда угодно
        let stop = WorkoutIntent(id: 2, kind: nil, date: today, at: at)
        XCTAssertTrue(stop.isFresh(now: at.addingTimeInterval(3600)))
    }
}

final class StorageTests: XCTestCase {
    func testMemoryStorage() {
        let storage = MemoryStorage()
        XCTAssertNil(storage.data(for: "a"))
        XCTAssertTrue(storage.save(["x": 1], for: "a"))
        XCTAssertEqual(storage.load([String: Int].self, for: "a"), ["x": 1])
        XCTAssertNil(storage.load([Int].self, for: "a"), "чужой формат не читается")
        storage.remove("a")
        XCTAssertNil(storage.data(for: "a"))

        storage.writable = false
        XCTAssertFalse(storage.save(["x": 2], for: "b"))
        XCTAssertNil(storage.data(for: "b"))
    }

    func testFilesKeepValuesBetweenLaunches() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("gym-journal-tests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let first = FileStorage(directory: directory)
        XCTAssertTrue(first.persistent)
        var settings = AppSettings()
        settings.restSec = 120
        XCTAssertTrue(first.save(settings, for: "settings"))

        let second = FileStorage(directory: directory)
        XCTAssertEqual(second.load(AppSettings.self, for: "settings"), settings)
        second.remove("settings")
        XCTAssertNil(first.data(for: "settings"))
        XCTAssertTrue(second.set(nil, for: "settings"), "повторное удаление не ошибка")
    }

    func testWithoutFolderValuesLiveInMemory() throws {
        // папку нельзя создать там, где уже лежит файл
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("gym-journal-tests-\(UUID().uuidString)")
        try Data("занято".utf8).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }

        let storage = FileStorage(directory: file.appendingPathComponent("inside", isDirectory: true))
        XCTAssertFalse(storage.persistent)
        XCTAssertFalse(storage.save(["x": 1], for: "a"), "сохранить на диск не удалось")
        XCTAssertEqual(storage.load([String: Int].self, for: "a"), ["x": 1])
    }
}

final class SettingsTests: XCTestCase {
    private func decode(_ text: String) throws -> AppSettings {
        try JSONDecoder().decode(AppSettings.self, from: Data(text.utf8))
    }

    func testDefaults() throws {
        let settings = AppSettings()
        XCTAssertEqual(settings.restSec, 90)
        XCTAssertTrue(settings.autoTimer)
        XCTAssertTrue(settings.sound)
        XCTAssertTrue(settings.vibrate)
        XCTAssertEqual(settings.wakeLock, .rest)
        XCTAssertTrue(settings.hints)
        XCTAssertEqual(settings.theme, .auto)
        XCTAssertEqual(settings.defaultStep, 2.5)
        XCTAssertTrue(settings.health)
        XCTAssertEqual(settings.step(for: "Гакк-жим"), 2.5)
        XCTAssertEqual(try decode("{}"), settings)
    }

    func testOwnStepForExercise() {
        var settings = AppSettings()
        settings.setStep(1.25, for: "Гакк-жим")
        XCTAssertEqual(settings.step(for: "Гакк-жим"), 1.25)
        XCTAssertEqual(settings.step(for: "Жим вверх"), 2.5)

        settings.setStep(-1, for: "Гакк-жим")
        settings.setStep(.nan, for: "Гакк-жим")
        settings.setStep(500, for: "Гакк-жим")
        XCTAssertEqual(settings.step(for: "Гакк-жим"), 1.25, "негодный шаг не принимается")

        // общий шаг отдельно не хранится
        settings.setStep(2.5, for: "Гакк-жим")
        XCTAssertTrue(settings.steps.isEmpty)
    }

    func testBrokenStoredValuesAreReplaced() throws {
        let raw = #"{"restSec":5,"autoTimer":"да","wakeLock":"always","theme":"dark","defaultStep":-2,"# +
            #""steps":{"Гакк-жим":1.25,"":5,"Жим вверх":0},"health":false,"chartExercise":"Гакк-жим","лишнее":1}"#
        let settings = try decode(raw)
        XCTAssertEqual(settings.restSec, 30)
        XCTAssertTrue(settings.autoTimer)
        XCTAssertEqual(settings.wakeLock, .rest)
        XCTAssertEqual(settings.theme, .dark)
        XCTAssertEqual(settings.defaultStep, 2.5)
        XCTAssertEqual(settings.steps, ["Гакк-жим": 1.25])
        XCTAssertFalse(settings.health)
        XCTAssertEqual(settings.chartExercise, "Гакк-жим")
        XCTAssertEqual(try decode(#"{"restSec":900}"#).restSec, 300)
    }

    func testSettingsSurviveStorage() throws {
        var settings = AppSettings()
        settings.restSec = 135
        settings.autoTimer = false
        settings.sound = false
        settings.wakeLock = .workout
        settings.theme = .light
        settings.defaultStep = 1.25
        settings.setStep(5, for: "Жим ногами")
        settings.weightNoteSeen = true
        settings.health = false
        let data = try JSONEncoder().encode(settings)
        XCTAssertEqual(try JSONDecoder().decode(AppSettings.self, from: data), settings)
    }
}
