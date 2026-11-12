import XCTest
@testable import GymJournalCore

/// Отрезок ходьбы, записанный вручную, как тренировка в «Здоровье».
final class WalkLogTests: XCTestCase {
    private let now = moment(1_800_000_000_000)

    /// Законченная тренировка: начало и конец в минутах от «сейчас».
    private func workout(
        from start: Double, to end: Double, kind: WorkoutKind = .walk, saved: Bool = true
    ) -> WorkoutSummary {
        WorkoutSummary(
            id: "w", kind: kind, date: Fixture.today, startedAt: now.addingTimeInterval(start * 60),
            endedAt: now.addingTimeInterval(end * 60), saved: saved
        )
    }

    private func entry(minutes: Double, km: Double? = 1.2, indoor: Bool = true) -> WalkEntry {
        WalkEntry(start: now.addingTimeInterval(-minutes * 60), end: now, km: km, indoor: indoor)
    }

    func testSegmentEndsWhenRecordedAndLastsItsMinutes() {
        XCTAssertEqual(WalkLog.outcome(km: 1.2, minutes: 15, end: now), .save(entry(minutes: 15)))
        XCTAssertEqual(WalkLog.outcome(km: 1.2, minutes: 15, end: now, last: nil), .save(entry(minutes: 15)))
        // дробные минуты не округляются
        XCTAssertEqual(WalkLog.outcome(km: 0.1, minutes: 1.5, end: now), .save(entry(minutes: 1.5, km: 0.1)))
        // дорожка или улица — как у тренировки этого дня
        XCTAssertEqual(
            WalkLog.outcome(km: 1.2, minutes: 15, end: now, indoor: false),
            .save(entry(minutes: 15, indoor: false))
        )
    }

    func testSegmentWithoutKilometresHasNoDistance() {
        let want = WalkLog.Outcome.save(entry(minutes: 10, km: nil))
        XCTAssertEqual(WalkLog.outcome(km: nil, minutes: 10, end: now), want)
        XCTAssertEqual(WalkLog.outcome(km: 0, minutes: 10, end: now), want)
        XCTAssertEqual(WalkLog.outcome(km: -1, minutes: 10, end: now), want)
    }

    func testSegmentWithoutMinutesIsNotAWorkout() {
        XCTAssertEqual(WalkLog.outcome(km: 1.2, minutes: nil, end: now), .noMinutes)
        XCTAssertEqual(WalkLog.outcome(km: 1.2, minutes: 0, end: now), .noMinutes)
        XCTAssertEqual(WalkLog.outcome(km: 1.2, minutes: -5, end: now), .noMinutes)
        // даже если ходьбу только что записала тренировка
        XCTAssertEqual(WalkLog.outcome(km: 1.2, minutes: nil, end: now, last: workout(from: -15, to: 0)), .noMinutes)
    }

    func testSegmentOfJustRecordedWalkIsNotRepeated() {
        // тренировка шла 15 минут и кончилась две минуты назад: отрезок на те же 15 минут — она же
        XCTAssertEqual(WalkLog.outcome(km: 1.2, minutes: 15, end: now, last: workout(from: -17, to: -2)), .covered)
        // числа в отрезке можно поправить: тренировка всё равно та же
        XCTAssertEqual(WalkLog.outcome(km: 1, minutes: 12, end: now, last: workout(from: -22, to: -2)), .covered)
        XCTAssertEqual(WalkLog.outcome(km: 2, minutes: 30, end: now, last: workout(from: -22, to: -2)), .covered)
    }

    func testSegmentOfAnotherWalkIsRecorded() {
        let want = WalkLog.Outcome.save(entry(minutes: 15))
        // ходьба до силовой записана тренировкой, отрезок — ходьба после силовой
        XCTAssertEqual(WalkLog.outcome(km: 1.2, minutes: 15, end: now, last: workout(from: -75, to: -60)), want)
        // прошлая ходьба кончилась, когда эта уже шла: общего времени меньше половины отрезка
        XCTAssertEqual(WalkLog.outcome(km: 1.2, minutes: 15, end: now, last: workout(from: -30, to: -10)), want)
        // ровно половина — ещё не она же
        XCTAssertEqual(WalkLog.outcome(km: 1.2, minutes: 15, end: now, last: workout(from: -30, to: -7.5)), want)
    }

    func testOnlySavedWalksHideTheSegment() {
        let want = WalkLog.Outcome.save(entry(minutes: 15))
        // силовая в то же время ходьбу не заменяет
        let strength = workout(from: -17, to: -2, kind: .strength)
        XCTAssertEqual(WalkLog.outcome(km: 1.2, minutes: 15, end: now, last: strength), want)
        // тренировка не сохранилась в «Здоровье»: её запишет отрезок
        let lost = workout(from: -17, to: -2, saved: false)
        XCTAssertEqual(WalkLog.outcome(km: 1.2, minutes: 15, end: now, last: lost), want)
    }

    func testBrokenClockDoesNotHideTheSegment() {
        let want = WalkLog.Outcome.save(entry(minutes: 15))
        // конец раньше начала или тренировка «из будущего»: общего времени нет
        XCTAssertEqual(WalkLog.outcome(km: 1.2, minutes: 15, end: now, last: workout(from: -2, to: -17)), want)
        XCTAssertEqual(WalkLog.outcome(km: 1.2, minutes: 15, end: now, last: workout(from: 5, to: 20)), want)
    }

    // MARK: Очередь

    func testQueueDropsWalksOlderThanADay() {
        let recent = entry(minutes: 15)
        var yesterday = recent
        yesterday.end = now.addingTimeInterval(-23 * 3600)
        yesterday.start = yesterday.end.addingTimeInterval(-900)
        var old = recent
        old.end = now.addingTimeInterval(-24 * 3600)
        old.start = old.end.addingTimeInterval(-900)
        XCTAssertEqual(WalkLog.fresh([old, yesterday, recent], now: now), [yesterday, recent])
        XCTAssertEqual(WalkLog.fresh([], now: now), [])
        // часы телефона перевели назад: запись «из будущего» остаётся
        XCTAssertEqual(WalkLog.fresh([recent], now: now.addingTimeInterval(-3600)), [recent])
    }

    func testQueueSurvivesStorage() throws {
        let storage = MemoryStorage()
        let queue = [entry(minutes: 15), entry(minutes: 22.5, km: nil, indoor: false)]
        XCTAssertTrue(storage.save(queue, for: "walks"))
        XCTAssertEqual(storage.load([WalkEntry].self, for: "walks"), queue)
    }
}
