import XCTest
@testable import GymJournalCore

/// Подписи и небольшие решения экранов: те же слова, что в веб-приложении.
final class TextsTests: XCTestCase {
    private let rows = Fixture.journal
    private let today = Fixture.today

    private func state(
        configured: Bool = true, phase: SyncPhase = .idle, error: SyncError? = nil, pending: Int = 0,
        online: Bool = true, retryAt: Date? = nil, failed: Int = 0
    ) -> SyncState {
        let item = OutboxItem(date: today, exercise: "Гакк-жим", occ: 0, fields: RowFields(weight: .set(20)), rev: 1, at: moment(0))
        let rejected = FailedItem(item: item, status: "rejected", reason: "", failedAt: moment(0))
        return SyncState(
            configured: configured, connection: nil, snapshot: nil, journal: [], pending: pending,
            failed: Array(repeating: rejected, count: failed), phase: phase, error: error, retryAt: retryAt,
            online: online, outboxSaved: true, revision: 0
        )
    }

    func testErrorTexts() throws {
        let cases = try Fixture.section("texts")["errors"].list
        XCTAssertFalse(cases.isEmpty)
        for item in cases {
            let code = item["code"].text
            let got = Present.errorText(code: code, message: item["message"].text)
            XCTAssertEqual(got.title, item["out"]["title"].text, code)
            XCTAssertEqual(got.text, item["out"]["text"].text, code)
        }
    }

    func testSyncLine() throws {
        let texts = try Fixture.section("texts")
        let now = moment(try XCTUnwrap(texts["now"].number))
        let cases = texts["sync"].list
        XCTAssertGreaterThan(cases.count, 10)
        for (index, item) in cases.enumerated() {
            var error: SyncError?
            if item["error"] != .null {
                error = SyncError(code: item["error"]["code"].text, message: item["error"]["message"].text, at: now)
            }
            let current = state(
                configured: item["configured"].flag,
                phase: try XCTUnwrap(SyncPhase(rawValue: item["phase"].text)),
                error: error,
                pending: item["pending"].whole,
                online: item["online"].flag,
                retryAt: item["retryIn"].number.map { now.addingTimeInterval($0) },
                failed: item["failed"].whole
            )
            XCTAssertEqual(Present.syncText(current, now: now), item["text"].text, "состояние \(index)")
        }
    }

    func testRejectedFields() throws {
        for item in try Fixture.section("texts")["fields"].list {
            let fields = try item["fields"].decoded(RowFields.self)
            XCTAssertEqual(Present.describe(fields), item["text"].text)
        }
    }

    func testPill() {
        func pill(_ state: SyncState) -> String {
            let info = Present.pill(state)
            return "\(info.tone.rawValue) \(info.icon) \(info.text)"
        }
        let failure = SyncError(code: "unauthorized", message: "Неверный ключ.", at: moment(0))
        XCTAssertEqual(pill(state(configured: false)), "plain info Не подключено")
        XCTAssertEqual(pill(state(phase: .error, error: failure)), "bad alert Нужна настройка")
        XCTAssertEqual(pill(state(failed: 2)), "bad alert Не записано: 2")
        XCTAssertEqual(pill(state(phase: .syncing)), "busy sync Обновление…")
        XCTAssertEqual(pill(state(phase: .syncing, pending: 1)), "busy sync Отправка…")
        XCTAssertEqual(pill(state(pending: 3)), "busy sync Отправка…")
        XCTAssertEqual(pill(state(phase: .waiting, pending: 3)), "wait cloudUp В очереди: 3")
        XCTAssertEqual(pill(state(pending: 3, online: false)), "wait cloudOff В очереди: 3")
        XCTAssertEqual(pill(state(online: false)), "wait cloudOff Нет сети")
        XCTAssertEqual(pill(state(phase: .waiting)), "wait cloudOff Нет связи")
        XCTAssertEqual(pill(state()), "plain check Сохранено")
    }

    func testSmallTexts() {
        XCTAssertEqual(Present.connectError(code: "unauthorized", message: "Неверный ключ."),
                       "Ключ не подошёл. Скопируйте его заново из журнала выполнения функции setup.")
        XCTAssertEqual(Present.connectError(code: "no_journal", message: "В таблице нет листа «Журнал»."),
                       "В таблице нет листа «Журнал».")
        XCTAssertEqual(Present.shortURL(DemoData.url), "…TESTD…6789/exec")
        XCTAssertEqual(Present.shortURL("http://127.0.0.1:8080/bridge"), "127.0.0.1:8080/bridge")
        XCTAssertEqual(Present.capitalized("среда, 25 ноября"), "Среда, 25 ноября")
        XCTAssertEqual(Present.capitalized(""), "")
        XCTAssertEqual(Present.doneMark(today: today), "сделано 25.11")
        XCTAssertEqual(Present.weekKm(walked: 8.5, goal: 17, started: true), "8,5 из 17 км")
        XCTAssertEqual(Present.weekKm(walked: nil, goal: 17, started: true), "0 из 17 км")
        XCTAssertEqual(Present.weekKm(walked: nil, goal: 17, started: false), "")
        XCTAssertEqual(Present.weekKm(walked: 4, goal: nil, started: true), "4 км")
        XCTAssertEqual(Present.weekKm(walked: nil, goal: nil, started: true), "")

        let item = OutboxItem(date: today, exercise: "Гакк-жим", occ: 0, fields: RowFields(), rev: 1, at: moment(0))
        XCTAssertEqual(Present.failedReason(FailedItem(item: item, status: "not_found", reason: "", failedAt: moment(0))),
                       "В журнале нет такой строки.")
        XCTAssertEqual(Present.failedReason(FailedItem(item: item, status: "rejected", reason: "", failedAt: moment(0))),
                       "Таблица отклонила запись.")
    }

    func testCardTexts() throws {
        let curl = try Fixture.row(today, "Сгибание ног")
        XCTAssertEqual(Present.meta(curl), "Kneeling Leg Curl Machine · на ногу")
        XCTAssertEqual(Present.planChip(curl), "2 × 10–12")
        let last = Journal.lastTime(rows, for: curl)
        XCTAssertEqual(last?.date, "2026-11-23")
        XCTAssertEqual(Present.closedText(curl, last: last), "2 × 10–12 · прошлый раз 17,5 кг")
        XCTAssertEqual(Present.closedText(curl, last: nil), "2 × 10–12")

        var done = curl
        done.weight = 17.5
        done.sets = [12, 11, nil]
        XCTAssertEqual(Present.closedText(done, last: last), "17,5 кг · 12, 11")

        var odd = curl
        odd.plan = "как получится"
        odd.machine = ""
        XCTAssertEqual(Present.meta(odd), "как получится")
        XCTAssertEqual(Present.planChip(odd), "как получится")
    }

    func testRepsStrip() {
        let plan = Plans.strength("3 × 10–12")
        XCTAssertEqual(Present.reps(plan: plan, current: nil, last: nil), RepsChoice(low: 5, high: 17, anchor: 12))
        XCTAssertEqual(Present.reps(plan: plan, current: nil, last: 11).anchor, 11)
        XCTAssertEqual(Present.reps(plan: plan, current: nil, last: 14).anchor, 12, "прошлое число вне плана: с верха диапазона")
        XCTAssertEqual(Present.reps(plan: plan, current: 9, last: 11).anchor, 9)
        XCTAssertEqual(Present.reps(plan: Plans.strength("3 × 3–5"), current: nil, last: nil).low, 1)
        let unknown = Plans.strength("как получится")
        XCTAssertEqual(Present.reps(plan: unknown, current: nil, last: nil), RepsChoice(low: 1, high: 30, anchor: 10))
        XCTAssertEqual(Present.reps(plan: unknown, current: nil, last: 20).anchor, 20)
    }

    func testRestAfterRound() throws {
        var day = Fixture.day(today)
        let split = { Journal.splitDay(day) }
        // первый подход первого упражнения пары: сосед ещё не сделал свой
        day[0].sets = [12, nil, nil]
        var pairs = split().pairs
        XCTAssertFalse(Present.restAfterSet(pairs: pairs, pair: pairs[0], key: day[0].key, index: 0))
        // сосед сделал: круг закончен
        day[1].sets = [12, nil, nil]
        pairs = split().pairs
        XCTAssertTrue(Present.restAfterSet(pairs: pairs, pair: pairs[0], key: day[1].key, index: 0))
        XCTAssertEqual(Present.activePair(focus: nil, pairs: pairs), 0)
        XCTAssertEqual(Present.activePair(focus: 2, pairs: pairs), 2)
        XCTAssertEqual(Present.activePair(focus: 7, pairs: pairs), 0)

        // весь день записан: отдыхать уже незачем
        for index in day.indices where !day[index].isWalk {
            day[index].weight = 20
            day[index].sets = [12, 12, 12]
        }
        pairs = split().pairs
        XCTAssertFalse(Present.restAfterSet(pairs: pairs, pair: pairs[2], key: day[5].key, index: 1))
        XCTAssertNil(Present.activePair(focus: 1, pairs: pairs))
    }

    func testFreeDayAndCatchUp() throws {
        let days = Journal.groupDays(rows)
        XCTAssertNil(Present.freeDay(days: [], today: today))

        let rest = try XCTUnwrap(Present.freeDay(days: days, today: "2026-11-28"))
        XCTAssertEqual(rest.title, "Сегодня тренировки нет")
        XCTAssertEqual(rest.text, "По плану день отдыха.")
        XCTAssertEqual(rest.next?.date, "2026-11-30")

        let early = try XCTUnwrap(Present.freeDay(days: days, today: "2026-11-01"))
        XCTAssertEqual(early.title, "Программа ещё не началась")
        XCTAssertEqual(early.text, "Первая тренировка: вторник, 10 ноября.")
        XCTAssertEqual(early.next?.date, "2026-11-10")

        let late = try XCTUnwrap(Present.freeDay(days: days, today: "2027-02-10"))
        XCTAssertEqual(late.title, "Программа закончилась")
        XCTAssertEqual(late.text, "Последняя тренировка была пятница, 29 января. Чтобы продолжить, добавьте недели в таблицу.")
        XCTAssertNil(late.next)

        XCTAssertEqual(Present.nextWorkout(days: days, today: today), "чт 26.11 · Ходьба или интервалы")
        XCTAssertEqual(Present.nextWorkout(days: days, today: "2026-11-28"), "пн 30.11 · Силовая A и ходьба")
        XCTAssertEqual(Present.nextWorkout(days: days, today: "2027-02-10"), "")

        // за две недели пропущена одна тренировка
        let missed: [String] = Present.catchUp(days: days, today: today).map { $0.date }
        XCTAssertEqual(missed, ["2026-11-19"])
        // позже пропущенных больше: новые сверху, не больше шести
        let later: [String] = Present.catchUp(days: days, today: "2026-12-12").map { $0.date }
        XCTAssertEqual(later, ["2026-12-11", "2026-12-10", "2026-12-09", "2026-12-08", "2026-12-07", "2026-12-04"])
    }
}
