import XCTest
@testable import GymJournalCore

/// Очередь записей ведёт себя так же, как в веб-приложении: тот же порядок, те же запросы.
final class OutboxTests: XCTestCase {
    private let rows = Fixture.journal

    private func row(_ key: String) throws -> JournalRow {
        try XCTUnwrap(rows.first { $0.key == key }, "нет строки \(key)")
    }

    private func keys(_ marks: [SentMark]) -> [String] {
        marks.map { $0.key }
    }

    private func revs(_ marks: [SentMark]) -> [Int] {
        marks.map { $0.rev }
    }

    /// Очередь после всех шагов эталона.
    private func filled() throws -> Outbox {
        var box = Outbox()
        for (index, step) in try Fixture.section("outbox")["steps"].list.enumerated() {
            let fields = try step["fields"].decoded(RowFields.self)
            box = OutboxLogic.queue(box, row: try row(step["row"].text), fields: fields, now: moment(Double(1000 + index)))
        }
        return box
    }

    func testQueueAndPush() throws {
        let steps = try Fixture.section("outbox")["steps"].list
        XCTAssertGreaterThan(steps.count, 5)
        var box = Outbox()
        for (index, step) in steps.enumerated() {
            let label = "шаг \(index + 1)"
            let fields = try step["fields"].decoded(RowFields.self)
            box = OutboxLogic.queue(box, row: try row(step["row"].text), fields: fields, now: moment(Double(1000 + index)))
            XCTAssertEqual(box.seq, step["seq"].whole, label)
            XCTAssertEqual(box.pendingCount, step["pending"].whole, label)

            let push = OutboxLogic.buildPush(box)
            if let difference = JSONValue.array(push.entries).difference(from: step["entries"]) {
                XCTFail("\(label): \(difference)")
            }
            let wantKeys: [String] = step["sent"].list.map { $0["key"].text }
            let wantRevs: [Int] = step["sent"].list.map { $0["rev"].whole }
            XCTAssertEqual(keys(push.sent), wantKeys, label)
            XCTAssertEqual(revs(push.sent), wantRevs, label)
        }
    }

    func testEditsAreShownOverTheJournal() throws {
        let box = try filled()
        let shown = OutboxLogic.apply(rows, box).filter { $0.pending }
        let expected = try Fixture.section("outbox")["applied"].list
        XCTAssertEqual(shown.count, expected.count)
        for (row, want) in zip(shown, expected) {
            let key = want["key"].text
            XCTAssertEqual(row.key, key)
            XCTAssertEqual(row.weight, want["weight"].number, key)
            XCTAssertEqual(row.sets, want["sets"].numbers, key)
            XCTAssertEqual(row.km, want["km"].number, key)
            XCTAssertEqual(row.min, want["min"].number, key)
            XCTAssertEqual(row.note, want["note"].text, key)
        }
        XCTAssertEqual(OutboxLogic.apply(rows, Outbox()), rows)
    }

    func testAnswerOfTheSheet() throws {
        let box = try filled()
        let ack = try Fixture.section("outbox")["ack"]
        let push = OutboxLogic.buildPush(box)
        let wantKeys: [String] = ack["sent"].list.map { $0["key"].text }
        let wantRevs: [Int] = ack["sent"].list.map { $0["rev"].whole }
        XCTAssertEqual(keys(push.sent), wantKeys)
        XCTAssertEqual(revs(push.sent), wantRevs)

        // пока запрос был в пути, одну строку успели поправить
        let racing = OutboxLogic.queue(
            box, row: try row(ack["racingKey"].text), fields: RowFields(note: "поправили в пути"), now: moment(2000)
        )
        let acked = try OutboxLogic.ack(racing, sent: push.sent, results: ack["results"], now: moment(3000))
        XCTAssertEqual(Set(acked.items.keys), Set(ack["pendingKeys"].texts))

        let wantFailed = ack["failed"].list
        XCTAssertEqual(acked.failed.count, wantFailed.count)
        for (item, want) in zip(acked.failed, wantFailed) {
            XCTAssertEqual(item.item.key, want["key"].text)
            XCTAssertEqual(item.status, want["status"].text)
            XCTAssertEqual(item.reason, want["reason"].text)
            XCTAssertEqual(Present.describe(item.item.fields), want["describe"].text)
            XCTAssertEqual(item.failedAt, moment(3000))
        }

        let retry = try Fixture.section("outbox")["retry"]
        let retried = OutboxLogic.retryFailed(acked, index: 0, now: moment(4000))
        XCTAssertEqual(Set(retried.items.keys), Set(retry["pendingKeys"].texts))
        let failedKeys: [String] = retried.failed.map { $0.item.key }
        XCTAssertEqual(failedKeys, retry["failed"].texts)
        if let difference = JSONValue.array(OutboxLogic.buildPush(retried).entries).difference(from: retry["entries"]) {
            XCTFail("повтор: \(difference)")
        }

        let dropped = OutboxLogic.dropFailed(retried, index: 0)
        XCTAssertTrue(dropped.failed.isEmpty)
        XCTAssertEqual(OutboxLogic.dropFailed(dropped, index: 3), dropped)
        XCTAssertEqual(OutboxLogic.retryFailed(dropped, index: 0, now: moment(5000)), dropped)
    }

    func testAnswerOfWrongLengthIsNotTrusted() throws {
        let box = try filled()
        let push = OutboxLogic.buildPush(box)
        XCTAssertThrowsError(try OutboxLogic.ack(box, sent: push.sent, results: .array([]), now: moment(1)))
        XCTAssertThrowsError(try OutboxLogic.ack(box, sent: push.sent, results: nil, now: moment(1)))
        XCTAssertThrowsError(try OutboxLogic.ack(box, sent: push.sent, results: .string("ок"), now: moment(1)))
    }

    func testEmptyEditChangesNothing() throws {
        let hack = try Fixture.row(Fixture.today, "Гакк-жим")
        let box = OutboxLogic.queue(Outbox(), row: hack, fields: RowFields(), now: moment(1))
        XCTAssertEqual(box, Outbox())
        XCTAssertTrue(OutboxLogic.buildPush(box).entries.isEmpty)
    }

    func testPushIsCutToTheLimit() throws {
        var box = Outbox()
        let day = Fixture.day(Fixture.today).filter { !$0.isWalk }
        for (index, row) in day.enumerated() {
            box = OutboxLogic.queue(box, row: row, fields: RowFields(weight: .set(Double(20 + index))), now: moment(Double(index)))
        }
        let push = OutboxLogic.buildPush(box, limit: 4)
        XCTAssertEqual(push.entries.count, 4)
        XCTAssertEqual(keys(push.sent), day.prefix(4).map { $0.key })
    }

    func testNewEditReplacesRejectedOne() throws {
        let hack = try Fixture.row(Fixture.today, "Гакк-жим")
        var box = OutboxLogic.queue(Outbox(), row: hack, fields: RowFields(weight: .set(2000)), now: moment(1))
        let push = OutboxLogic.buildPush(box)
        let results = JSONValue.array([.object(["status": .string("rejected"), "reason": .string("Вес должен быть числом от 0 до 1000.")])])
        box = try OutboxLogic.ack(box, sent: push.sent, results: results, now: moment(2))
        XCTAssertEqual(box.pendingCount, 0)
        XCTAssertEqual(box.failed.count, 1)
        XCTAssertEqual(Present.failedReason(box.failed[0]), "Вес должен быть числом от 0 до 1000.")

        box = OutboxLogic.queue(box, row: hack, fields: RowFields(weight: .set(20)), now: moment(3))
        XCTAssertTrue(box.failed.isEmpty)
        XCTAssertEqual(box.pendingCount, 1)
    }

    func testFieldsSurviveStorage() throws {
        let cases: [RowFields] = [
            RowFields(),
            RowFields(weight: .set(27.5)),
            RowFields(weight: .set(nil)),
            RowFields(sets: [12, nil, 9]),
            RowFields(km: .set(1.5), min: .set(nil)),
            RowFields(note: ""),
            RowFields(weight: .set(30), sets: [10, 10, 10], km: .set(nil), min: .set(18), note: "тяжело"),
        ]
        for fields in cases {
            let data = try JSONEncoder().encode(fields)
            XCTAssertEqual(try JSONDecoder().decode(RowFields.self, from: data), fields)
        }
        let box = try filled()
        let data = try JSONEncoder().encode(box)
        XCTAssertEqual(try JSONDecoder().decode(Outbox.self, from: data), box)
    }

    func testLaterEditWinsFieldByField() {
        let first = RowFields(weight: .set(20), sets: [12, nil, nil], note: "раз")
        let second = RowFields(weight: .set(nil), km: .set(3))
        let merged = second.merged(over: first)
        XCTAssertEqual(merged.weight, .set(nil))
        XCTAssertEqual(merged.sets, [12, nil, nil])
        XCTAssertEqual(merged.km, .set(3))
        XCTAssertEqual(merged.min, .keep)
        XCTAssertEqual(merged.note, "раз")
        XCTAssertTrue(RowFields().isEmpty)
        XCTAssertFalse(RowFields(note: "").isEmpty)
    }
}
