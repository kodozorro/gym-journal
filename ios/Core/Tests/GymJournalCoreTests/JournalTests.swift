import XCTest
@testable import GymJournalCore

/// План, строки журнала, дни и недельная статистика совпадают с веб-приложением.
final class PlanTests: XCTestCase {
    private func check(_ plan: StrengthPlan, _ want: JSONValue, _ text: String) {
        XCTAssertEqual(plan.sets, want["sets"].whole, text)
        XCTAssertEqual(plan.low, want["low"].integer, text)
        XCTAssertEqual(plan.high, want["high"].integer, text)
        XCTAssertEqual(plan.tail, want["tail"].text, text)
        XCTAssertEqual(plan.perSide, want["perSide"].flag, text)
        XCTAssertEqual(plan.text, want["text"].text, text)
        XCTAssertEqual(plan.unknown, want["unknown"].flag, text)
    }

    func testPlanTexts() throws {
        let cases = try Fixture.section("plans").list
        XCTAssertGreaterThan(cases.count, 15)
        for item in cases {
            let text = item["text"].text
            let want = item["plan"]
            switch Plans.parse(text) {
            case .strength(let plan):
                XCTAssertEqual(want["kind"].text, "strength", text)
                check(plan, want, text)
            case .cardio(let plan):
                XCTAssertEqual(want["kind"].text, "cardio", text)
                XCTAssertEqual(plan.km, want["km"].number, text)
                XCTAssertEqual(plan.kmHigh, want["kmHigh"].number, text)
                XCTAssertEqual(plan.text, want["text"].text, text)
            }
            check(Plans.strength(text), item["strength"], text)
        }
    }

    func testRangeText() {
        XCTAssertEqual(Plans.strength("3 × 10–12").rangeText, "10–12")
        XCTAssertEqual(Plans.strength("3x10").rangeText, "10")
        XCTAssertEqual(Plans.strength("как получится").rangeText, "")
    }
}

final class JournalTests: XCTestCase {
    private let rows = Fixture.journal
    private let today = Fixture.today

    func testDemoJournalIsLoaded() {
        XCTAssertEqual(rows.count, 269)
        XCTAssertEqual(Fixture.start, "2026-11-09")
        XCTAssertEqual(Fixture.pull["walkGoalKm"]?.number, 17)
    }

    func testRows() throws {
        let expected = try Fixture.section("journal")["rows"].list
        XCTAssertEqual(rows.count, expected.count)
        for (row, want) in zip(rows, expected) {
            let key = want["key"].text
            XCTAssertEqual(row.key, key)
            XCTAssertEqual(row.isWalk, want["walk"].flag, key)
            XCTAssertEqual(row.isDone, want["done"].flag, key)
            XCTAssertEqual(row.hasData, want["data"].flag, key)
            XCTAssertEqual(row.nextSetIndex, want["next"].whole, key)
            XCTAssertEqual(row.slotCount, want["slots"].whole, key)
            XCTAssertEqual(row.summary, want["summary"].text, key)
            XCTAssertEqual(row.plannedKm, want["plannedKm"].number, key)

            var bare = row
            bare.week = nil
            XCTAssertEqual(Journal.weekOf(bare, start: Fixture.start), want["week"].integer, key)

            let last = Journal.lastTime(rows, for: row)
            XCTAssertEqual(last?.key, want["last"].string, key)

            let progression = Journal.progression(last: last, step: 2.5)
            let wantProgression = want["progression"]
            XCTAssertEqual(progression == nil, wantProgression == .null, key)
            if let progression {
                XCTAssertEqual(progression.from, wantProgression["from"].number, key)
                XCTAssertEqual(progression.weight, wantProgression["weight"].number, key)
                XCTAssertEqual(progression.reps, wantProgression["reps"].whole, key)
                XCTAssertEqual(progression.date, wantProgression["date"].text, key)
            }

            let pace = Journal.pace(km: row.km, min: row.min)
            let wantPace = want["pace"]
            XCTAssertEqual(pace == nil, wantPace == .null, key)
            if let pace {
                XCTAssertEqual(pace.pace, wantPace["pace"].text, key)
                XCTAssertEqual(pace.speed, wantPace["speed"].number, key)
            }
        }
    }

    func testDays() throws {
        let expected = try Fixture.section("journal")["days"].list
        let days = Journal.groupDays(rows)
        XCTAssertEqual(days.count, expected.count)
        for (day, want) in zip(days, expected) {
            let date = want["date"].text
            XCTAssertEqual(day.date, date)
            XCTAssertEqual(day.week, want["week"].integer, date)
            XCTAssertEqual(day.rows.count, want["count"].whole, date)
            XCTAssertEqual(Journal.workoutTitle(day.rows), want["title"].text, date)
            XCTAssertEqual(Journal.workoutBadge(day.rows), want["badge"].text, date)
            XCTAssertEqual(Journal.dayStatus(day.rows, date: day.date, today: today).rawValue, want["status"].text, date)

            let progress = Journal.dayProgress(day.rows)
            XCTAssertEqual(progress.done, want["progress"]["done"].whole, date)
            XCTAssertEqual(progress.touched, want["progress"]["touched"].whole, date)
            XCTAssertEqual(progress.total, want["progress"]["total"].whole, date)
            XCTAssertEqual(Present.daySummary(day.rows), want["summary"].text, date)

            let split = Journal.splitDay(day.rows)
            let pairs: [[String]] = split.pairs.map { pair in pair.map { $0.key } }
            let wantPairs: [[String]] = want["pairs"].list.map { $0.texts }
            XCTAssertEqual(pairs, wantPairs, date)
            let walks: [String] = split.walks.map { $0.key }
            XCTAssertEqual(walks, want["walks"].texts, date)
        }
    }

    func testStats() throws {
        let stats = try Fixture.section("journal")["stats"]
        let start = Fixture.start

        let names = Stats.exerciseList(rows)
        XCTAssertEqual(names, stats["exercises"].texts)

        for item in stats["best"].list {
            let name = item["name"].text
            let got = Stats.weeklyBest(rows, exercise: name, start: start)
            let weeks: [Int] = got.map { $0.week }
            let best: [Double?] = got.map { $0.best }
            let wantWeeks: [Int] = item["weeks"].list.map { $0["week"].whole }
            let wantBest: [Double?] = item["weeks"].list.map { $0["best"].number }
            XCTAssertEqual(weeks, wantWeeks, name)
            XCTAssertEqual(best, wantBest, name)
        }

        let walk = Stats.weeklyWalk(rows, start: start)
        let wantWalk = stats["walk"].list
        XCTAssertEqual(walk.count, wantWalk.count)
        for (item, want) in zip(walk, wantWalk) {
            XCTAssertEqual(item.week, want["week"].whole)
            XCTAssertEqual(item.km, want["km"].number)
            XCTAssertEqual(item.min, want["min"].number)
        }

        let weeks = Stats.weeks(rows, start: start)
        let numbers: [Int?] = weeks.map { $0.week }
        let wantNumbers: [Int?] = stats["weeks"].list.map { $0["week"].integer }
        XCTAssertEqual(numbers, wantNumbers)
        let dates: [[String]] = weeks.map { week in week.days.map { $0.date } }
        let wantDates: [[String]] = stats["weeks"].list.map { $0["dates"].texts }
        XCTAssertEqual(dates, wantDates)

        for item in stats["history"].list {
            let name = item["name"].text
            let keys: [String] = Stats.exerciseHistory(rows, exercise: name).map { $0.key }
            XCTAssertEqual(keys, item["keys"].texts, name)
        }

        XCTAssertEqual(Stats.weekOfDate(weeks, date: today), stats["weekOfToday"].integer)
        XCTAssertEqual(Stats.weekStart(start: start, week: 3), stats["weekStart3"].string)
        XCTAssertNil(Stats.weekStart(start: nil, week: 3))
        XCTAssertNil(Stats.weekOfDate(weeks, date: "2026-01-01"))
    }

    // MARK: Случаи, которых нет в учебном журнале

    private func strength(_ plan: String, weight: Double?, sets: [Double?], date: String = "2026-11-23") -> JournalRow {
        JournalRow(date: date, workout: "Силовая A", exercise: "Жим от груди", plan: plan, weight: weight, sets: sets)
    }

    func testProgressionNeedsTopOfRangeInEverySet() throws {
        let top = strength("3 × 10–12", weight: 22.5, sets: [12, 12, 12])
        let hint = try XCTUnwrap(Journal.progression(last: top, step: 2.5))
        XCTAssertEqual(hint.from, 22.5)
        XCTAssertEqual(hint.weight, 25)
        XCTAssertEqual(hint.reps, 12)
        XCTAssertEqual(hint.date, "2026-11-23")

        XCTAssertEqual(Journal.progression(last: strength("3 × 10–12", weight: 22.5, sets: [13, 12, 14]), step: 1.25)?.weight, 23.75)
        XCTAssertNil(Journal.progression(last: strength("3 × 10–12", weight: 22.5, sets: [12, 12, 11]), step: 2.5))
        XCTAssertNil(Journal.progression(last: strength("3 × 10–12", weight: 22.5, sets: [12, 12, nil]), step: 2.5))
        XCTAssertNil(Journal.progression(last: strength("3 × 10–12", weight: nil, sets: [12, 12, 12]), step: 2.5))
        XCTAssertNil(Journal.progression(last: strength("как получится", weight: 20, sets: [12, 12, 12]), step: 2.5))
        XCTAssertNil(Journal.progression(last: top, step: 0))
        XCTAssertNil(Journal.progression(last: nil, step: 2.5))
        // два подхода по плану: третья ячейка не нужна
        XCTAssertNotNil(Journal.progression(last: strength("2 × 12–15", weight: 10, sets: [15, 15, nil]), step: 2.5))
    }

    func testPartialDay() {
        var day = Fixture.day(today)
        XCTAssertEqual(day.count, 7)
        day[0].weight = 17.5
        day[0].sets = [12, nil, nil]
        XCTAssertEqual(Journal.dayStatus(day, date: today, today: today), .partial)
        XCTAssertEqual(Journal.dayStatus(day, date: today, today: "2026-11-27"), .partial)
        XCTAssertEqual(Present.daySummary(day), "записано 0 из 7")
        day[0].sets = [12, 11, nil]
        XCTAssertEqual(Present.daySummary(day), "записано 1 из 7")
        XCTAssertEqual(Journal.dayStatus([], date: today, today: today), .today)
    }

    func testRowReadiness() {
        var row = strength("2 × 10–12 на ногу", weight: nil, sets: [nil, nil, nil])
        XCTAssertFalse(row.hasData)
        XCTAssertEqual(row.slotCount, 2)
        XCTAssertEqual(row.nextSetIndex, 0)
        row.sets = [12, nil, nil]
        XCTAssertTrue(row.hasData)
        XCTAssertFalse(row.isDone)
        XCTAssertEqual(row.nextSetIndex, 1)
        row.sets = [12, 11, nil]
        XCTAssertFalse(row.isDone, "без веса строка не готова")
        row.weight = 17.5
        XCTAssertTrue(row.isDone)
        XCTAssertEqual(row.nextSetIndex, -1)
        row.sets = [12, 11, 9]
        XCTAssertEqual(row.slotCount, 3, "лишний подход остаётся на экране")
        XCTAssertEqual(row.summary, "17,5 кг · 12, 11, 9")
    }

    func testRoundOfPair() {
        let first = strength("3 × 10–12", weight: 20, sets: [12, nil, nil])
        var second = JournalRow(date: "2026-11-23", workout: "Силовая A", exercise: "Жим вверх", plan: "2 × 10–12")
        let pair = [first, second]
        XCTAssertFalse(Journal.roundComplete(pair, key: first.key, setIndex: 0))
        second.sets = [10, nil, nil]
        XCTAssertTrue(Journal.roundComplete([first, second], key: first.key, setIndex: 0))
        // третий подход соседу не положен
        XCTAssertTrue(Journal.roundComplete([first, second], key: first.key, setIndex: 2))
        XCTAssertTrue(Journal.roundComplete([first], key: first.key, setIndex: 0))
    }

    func testNormalizeDropsBrokenRows() throws {
        let raw = """
        [
          {"date":"2026-11-25","workout":"Силовая B","exercise":" Гакк-жим ","plan":"3 × 10–12","week":3,
           "weight":22.5,"sets":[12,"11",null,9],"km":null,"min":null,"note":"заметка","лишнее":1},
          {"date":"2026-11-25","exercise":"Гакк-жим","occ":1,"weight":"20","sets":"нет"},
          {"date":"25.11.2026","exercise":"Гакк-жим"},
          {"date":"2026-11-25","exercise":"   "},
          {"date":"2026-11-25"},
          "строка", null, 5
        ]
        """
        let value = try JSONDecoder().decode(JSONValue.self, from: Data(raw.utf8))
        let rows = Journal.normalize(value)
        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(rows[0].key, "2026-11-25|Гакк-жим|0")
        XCTAssertEqual(rows[0].weight, 22.5)
        XCTAssertEqual(rows[0].sets, [12, nil, nil])
        XCTAssertEqual(rows[0].week, 3)
        XCTAssertEqual(rows[0].note, "заметка")
        XCTAssertEqual(rows[1].key, "2026-11-25|Гакк-жим|1")
        XCTAssertNil(rows[1].weight)
        XCTAssertEqual(rows[1].sets, [nil, nil, nil])
        XCTAssertEqual(Journal.normalize(nil), [])
        XCTAssertEqual(Journal.normalize(.string("журнал")), [])
    }

    func testRowSurvivesStorage() throws {
        var row = try Fixture.row("2026-11-23", "Сгибание ног")
        row.note = "сиденье на 4"
        row.pending = true
        let data = try JSONEncoder().encode(row)
        XCTAssertEqual(try JSONDecoder().decode(JournalRow.self, from: data), row)
    }
}
