import XCTest
@testable import GymJournalCore

/// Даты и числа считаются так же, как в веб-приложении.
final class DatesTests: XCTestCase {
    func testWeekdaysLabelsAndShifts() throws {
        let cases = try Fixture.section("dates")["days"].list
        XCTAssertFalse(cases.isEmpty)
        for item in cases {
            let iso = item["iso"].text
            XCTAssertEqual(Days.isoWeekday(iso), item["weekday"].whole, iso)
            XCTAssertEqual(Days.mondayOf(iso), item["monday"].text, iso)
            XCTAssertEqual(Days.formatSheetDay(iso), item["sheet"].text, iso)
            XCTAssertEqual(Days.formatLongDay(iso), item["long"].text, iso)
            XCTAssertEqual(Days.formatShortDay(iso), item["short"].text, iso)
            XCTAssertEqual(Days.formatNumericDay(iso), item["numeric"].text, iso)
            XCTAssertEqual(Days.addDays(iso, 1), item["plus1"].text, iso)
            XCTAssertEqual(Days.addDays(iso, -14), item["minus14"].text, iso)
            XCTAssertEqual(Days.addDays(iso, 45), item["plus45"].text, iso)
        }
    }

    func testOnlyRealDatesAreAccepted() throws {
        let cases = try Fixture.section("dates")["valid"].list
        XCTAssertFalse(cases.isEmpty)
        for item in cases {
            XCTAssertEqual(Days.isISODate(item["text"].text), item["ok"].flag, "«\(item["text"].text)»")
        }
    }

    func testRanges() throws {
        for item in try Fixture.section("dates")["ranges"].list {
            let from = item["from"].text
            let to = item["to"].text
            XCTAssertEqual(Days.formatRange(from, to), item["text"].text, "\(from) – \(to)")
        }
    }

    func testDifferences() throws {
        for item in try Fixture.section("dates")["diffs"].list {
            let a = item["a"].text
            let b = item["b"].text
            XCTAssertEqual(Days.diffDays(a, b), item["days"].whole, "\(a) − \(b)")
        }
    }

    func testDayNumberGoesThereAndBack() {
        XCTAssertEqual(Days.iso(0), "1970-01-01")
        XCTAssertEqual(Days.parse("1970-01-01"), 0)
        XCTAssertEqual(Days.parse("2000-03-01"), 11_017)
        for ordinal in stride(from: -200_000, through: 200_000, by: 997) {
            let date = Days.civil(ordinal)
            XCTAssertEqual(Days.ordinal(year: date.year, month: date.month, day: date.day), ordinal)
            XCTAssertEqual(Days.parse(Days.iso(ordinal)), date.year >= 0 ? ordinal : nil)
        }
    }

    func testBadDateIsLeftAsIs() {
        XCTAssertEqual(Days.addDays("завтра", 1), "завтра")
        XCTAssertEqual(Days.diffDays("завтра", "2026-11-09"), 0)
        XCTAssertEqual(Days.formatSheetDay("завтра"), "завтра")
        XCTAssertEqual(Days.formatLongDay(""), "")
        XCTAssertEqual(Days.formatRange("a", "b"), "a – b")
    }

    func testTodayFollowsTheClockOfThePhone() throws {
        // 25 ноября 2026 года, 22:30 по Гринвичу
        let seconds = Double(Days.ordinal(year: 2026, month: 11, day: 25)) * 86_400 + 22.5 * 3600
        let now = Date(timeIntervalSince1970: seconds)
        let utc = try XCTUnwrap(TimeZone(identifier: "UTC"))
        let tokyo = try XCTUnwrap(TimeZone(identifier: "Asia/Tokyo"))
        let losAngeles = try XCTUnwrap(TimeZone(identifier: "America/Los_Angeles"))
        XCTAssertEqual(Days.today(now, timeZone: utc), "2026-11-25")
        XCTAssertEqual(Days.today(now, timeZone: tokyo), "2026-11-26")
        XCTAssertEqual(Days.today(now, timeZone: losAngeles), "2026-11-25")
    }

    func testMoment() throws {
        let utc = try XCTUnwrap(TimeZone(identifier: "UTC"))
        let day = Double(Days.ordinal(year: 2026, month: 11, day: 25)) * 86_400
        let now = Date(timeIntervalSince1970: day + 22.5 * 3600)
        XCTAssertEqual(Days.formatMoment(nil, now: now, timeZone: utc), "ещё ни разу")
        XCTAssertEqual(Days.formatMoment(Date(timeIntervalSince1970: day + 9 * 3600 + 5 * 60), now: now, timeZone: utc), "09:05")
        XCTAssertEqual(
            Days.formatMoment(Date(timeIntervalSince1970: day - 86_400 + 12 * 3600 + 31 * 60), now: now, timeZone: utc),
            "24 ноября, 12:31"
        )
    }
}

final class NumbersTests: XCTestCase {
    func testDecimalInput() throws {
        let cases = try Fixture.section("numbers")["decimal"].list
        XCTAssertFalse(cases.isEmpty)
        for item in cases {
            XCTAssertEqual(Numbers.parseDecimal(item["text"].text), item["out"].parsedNumber, "«\(item["text"].text)»")
        }
    }

    func testCountInput() throws {
        for item in try Fixture.section("numbers")["count"].list {
            XCTAssertEqual(Numbers.parseCount(item["text"].text), item["out"].parsedNumber, "«\(item["text"].text)»")
        }
    }

    func testFormat() throws {
        for item in try Fixture.section("numbers")["format"].list {
            let value = try XCTUnwrap(item["value"].number)
            XCTAssertEqual(Numbers.format(value, digits: item["digits"].whole), item["text"].text, "\(value)")
        }
        XCTAssertEqual(Numbers.format(nil), "")
        XCTAssertEqual(Numbers.format(.nan), "")
        XCTAssertEqual(Numbers.format(.infinity), "")
    }

    func testRounding() throws {
        for item in try Fixture.section("numbers")["round"].list {
            let value = try XCTUnwrap(item["value"].number)
            XCTAssertEqual(Numbers.roundTo(value, item["digits"].whole), item["out"].number, "\(value)")
        }
        XCTAssertEqual(Numbers.roundHalfUp(2.5), 3)
        XCTAssertEqual(Numbers.roundHalfUp(-2.5), -2)
        XCTAssertEqual(Numbers.roundHalfUp(2.4999), 2)
    }

    func testPlural() throws {
        for item in try Fixture.section("numbers")["plural"].list {
            let count = item["n"].whole
            XCTAssertEqual(Numbers.plural(count, "упражнение", "упражнения", "упражнений"), item["text"].text, "\(count)")
        }
    }

    func testPlainText() {
        XCTAssertEqual(Numbers.plain(40), "40")
        XCTAssertEqual(Numbers.plain(42.5), "42.5")
        XCTAssertEqual(Numbers.plain(-0.0), "0")
        XCTAssertEqual(Numbers.plain(1_000_000), "1000000")
    }

    /// На часах Int занимает 32 бита: большое число из таблицы не должно ронять приложение.
    func testHugeNumbersDoNotCrash() {
        XCTAssertEqual(Numbers.int(12.9), 12)
        XCTAssertEqual(Numbers.int(.nan), 0)
        XCTAssertEqual(Numbers.int(.infinity), 2_000_000_000)
        XCTAssertEqual(Numbers.int(-.infinity), -2_000_000_000)
        XCTAssertEqual(Numbers.int(1e18), 2_000_000_000)
        XCTAssertNil(JSONValue.number(1e12).integer)
        XCTAssertEqual(JSONValue.number(12).integer, 12)
        XCTAssertNil(JSONValue.number(12.5).integer)
        XCTAssertEqual(RestTimer.clock(1e18), "33333333:20")
        XCTAssertNil(Journal.pace(km: 0, min: 10))
        XCTAssertNotNil(Journal.pace(km: 1e-12, min: 1440))
        let plan = Plans.strength("3 × 10–12")
        XCTAssertEqual(Present.reps(plan: plan, current: 1e15, last: nil).anchor, 2_000_000_000)
    }
}
