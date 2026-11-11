import XCTest
@testable import GymJournalCore

/// Шкала графика, цифровая клавиатура, справочник упражнений и таймер отдыха — как в веб-приложении.
final class ScaleTests: XCTestCase {
    func testNiceScale() throws {
        let cases = try Fixture.section("scale").list
        XCTAssertFalse(cases.isEmpty)
        for item in cases {
            let low = try XCTUnwrap(item["min"].number)
            let high = try XCTUnwrap(item["max"].number)
            let count = try XCTUnwrap(item["count"].number)
            let scale = Scales.nice(low, high, count: count, fromZero: item["fromZero"].flag)
            let label = "\(low)…\(high)"
            XCTAssertEqual(scale.lo, item["out"]["lo"].number, label)
            XCTAssertEqual(scale.hi, item["out"]["hi"].number, label)
            XCTAssertEqual(scale.step, item["out"]["step"].number, label)
            let ticks: [Double?] = scale.ticks.map { $0 }
            XCTAssertEqual(ticks, item["out"]["ticks"].numbers, label)
        }
    }

    func testPosition() {
        let scale = Scales.nice(0, 13, fromZero: true)
        XCTAssertEqual(scale.position(0, from: 200, to: 20), 200)
        XCTAssertEqual(scale.position(15, from: 200, to: 20), 20)
        XCTAssertEqual(scale.position(7.5, from: 200, to: 20), 110)
        XCTAssertEqual(Scales.linear(5, 3, 3, 0, 100), 50, "пустой отрезок: середина")
        XCTAssertEqual(Scales.niceStep(0), 1)
        XCTAssertEqual(Scales.nice(.nan, 5).lo, 0)
    }
}

final class KeypadTests: XCTestCase {
    private func key(_ text: String) -> KeypadKey? {
        switch text {
        case ",": return .comma
        case "back": return .back
        default: return Int(text).map { KeypadKey.digit($0) }
        }
    }

    func testTyping() throws {
        let cases = try Fixture.section("keypad").list
        XCTAssertFalse(cases.isEmpty)
        for (index, item) in cases.enumerated() {
            let spec = item["spec"]
            var field = KeypadField(
                name: spec["name"].text,
                value: spec["value"].number,
                integer: spec["integer"].flag,
                max: spec["max"].number,
                digits: spec["digits"].integer ?? 2,
                whole: spec["whole"].integer ?? 4
            )
            let label = "случай \(index)"
            XCTAssertEqual(field.text, item["initial"].text, label)
            for step in item["steps"].list {
                let pressed = try XCTUnwrap(key(step["key"].text), label)
                field = field.pressing(pressed)
                XCTAssertEqual(field.text, step["text"].text, "\(label), клавиша \(step["key"].text)")
                XCTAssertEqual(field.fresh, step["fresh"].flag, "\(label), клавиша \(step["key"].text)")
            }
            XCTAssertEqual(field.value, item["value"].parsedNumber, label)
            XCTAssertEqual(field.error, item["error"].text, label)
        }
    }

    func testStrangeKeysAreIgnored() {
        let field = KeypadField(name: "weight", value: 25)
        XCTAssertEqual(field.pressing(.digit(12)), field)
        XCTAssertEqual(field.pressing(.digit(-1)), field)
    }
}

final class GuideTests: XCTestCase {
    func testGuideMatchesWebApp() throws {
        let guide = try Fixture.section("guide")
        XCTAssertEqual(Guide.strengthRule, guide["rule"].text)
        XCTAssertEqual(Guide.legend, guide["legend"].text)
        XCTAssertEqual(Guide.photoNames.sorted(), guide["photos"].texts.sorted())
        XCTAssertEqual(Guide.artNames, guide["art"].texts.sorted())

        let cases = guide["cases"].list
        XCTAssertGreaterThan(cases.count, 40)
        for item in cases {
            let exercise = item["exercise"].text
            let machine = item["machine"].text
            let label = "\(exercise) / \(machine)"
            let got = Guide.guide(exercise: exercise, machine: machine)
            let want = item["out"]
            XCTAssertEqual(got.machine, want["machine"].text, label)
            XCTAssertEqual(got.photo, want["photo"].string, label)
            XCTAssertEqual(got.look, want["look"].text, label)
            XCTAssertEqual(got.art, want["art"].text, label)
            XCTAssertEqual(got.view, want["view"].text, label)
            XCTAssertEqual(got.legend, want["legend"].text, label)
            XCTAssertEqual(got.muscles, want["muscles"].text, label)
            XCTAssertEqual(got.steps, want["steps"].texts, label)
            XCTAssertEqual(got.rule, want["rule"].text, label)
            XCTAssertEqual(got.search, want["search"].text, label)
            XCTAssertEqual(got.machineType, want["machineType"].text, label)
            XCTAssertEqual(Guide.machineType(machine), want["machineType"].text, label)
        }
    }

    /// Каждой строке учебной программы есть что показать: рисунок и подсказки.
    func testEveryDemoRowHasGuide() {
        for row in Fixture.journal {
            let guide = Guide.guide(exercise: row.exercise, machine: row.machine)
            XCTAssertFalse(guide.art.isEmpty, row.key)
            XCTAssertFalse(guide.steps.isEmpty, row.key)
            XCTAssertEqual(guide.cardio, row.isWalk, row.key)
            XCTAssertEqual(guide.photo == nil, row.isWalk, row.key)
        }
    }
}

final class RestTimerTests: XCTestCase {
    private let start = moment(1_800_000_000_000)

    func testClock() throws {
        for item in try Fixture.section("timer")["clock"].list {
            let seconds = try XCTUnwrap(item["seconds"].number)
            XCTAssertEqual(RestTimer.clock(seconds), item["text"].text, "\(seconds)")
        }
        XCTAssertEqual(RestTimer.clock(75), "1:15")
    }

    func testCountdown() throws {
        let rest = RestTimer.start(now: start, seconds: 90)
        XCTAssertTrue(rest.isValid)
        let cases = try Fixture.section("timer")["rest"].list
        XCTAssertFalse(cases.isEmpty)
        for item in cases {
            let ms = try XCTUnwrap(item["ms"].number)
            let now = start.addingTimeInterval(ms / 1000)
            let label = "\(ms) мс"
            XCTAssertEqual(rest.left(now: now), item["left"].whole, label)
            XCTAssertEqual(rest.isOver(now: now), item["over"].flag, label)
            XCTAssertEqual(rest.overtime(now: now), item["overtime"].whole, label)
            let progress = try XCTUnwrap(item["progress"].number)
            XCTAssertEqual(rest.progress(now: now), progress, accuracy: 1e-6, label)
        }
    }

    func testExtension() throws {
        let timer = try Fixture.section("timer")
        let rest = RestTimer.start(now: start, seconds: 90)
        let cases: [(String, TimeInterval)] = [("extendedEarly", 60), ("extendedLate", 100)]
        for (name, at) in cases {
            let extended = rest.extended(now: start.addingTimeInterval(at), seconds: 30)
            let want = timer[name]
            let startedAt = try XCTUnwrap(want["startedAt"].number)
            let endsAt = try XCTUnwrap(want["endsAt"].number)
            XCTAssertEqual(extended.startedAt.timeIntervalSince(start) * 1000, startedAt, accuracy: 0.01, name)
            XCTAssertEqual(extended.endsAt.timeIntervalSince(start) * 1000, endsAt, accuracy: 0.01, name)
            XCTAssertEqual(extended.total, want["total"].number, name)
        }
    }

    func testBrokenTimerIsRejected() throws {
        XCTAssertFalse(RestTimer(startedAt: start, endsAt: start.addingTimeInterval(-1), total: 90).isValid)
        XCTAssertFalse(RestTimer(startedAt: start, endsAt: start.addingTimeInterval(90), total: .nan).isValid)
        let rest = RestTimer.start(now: start, seconds: 90)
        let data = try JSONEncoder().encode(rest)
        XCTAssertEqual(try JSONDecoder().decode(RestTimer.self, from: data), rest)
    }
}
