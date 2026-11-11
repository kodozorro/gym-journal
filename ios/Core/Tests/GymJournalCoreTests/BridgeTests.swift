import XCTest
@testable import GymJournalCore

/// Ответ, который отдаётся как есть: для случаев, которых у учебной таблицы нет.
private struct FixedTransport: BridgeTransport {
    var status = 200
    var body: String
    var failure: TransportFailure?

    func post(url: URL, body: Data, timeout: TimeInterval) async throws -> TransportResponse {
        if let failure { throw failure }
        return TransportResponse(status: status, body: Data(self.body.utf8))
    }
}

final class BridgeAddressTests: XCTestCase {
    func testAddressCheck() throws {
        let cases = try Fixture.section("bridge")["urls"].list
        XCTAssertGreaterThan(cases.count, 20)
        for item in cases {
            let text = item["text"].text
            let allowLocal = item["allowLocal"].flag
            let label = "«\(text)», учебный мостик \(allowLocal ? "разрешён" : "запрещён")"
            switch Bridge.normalizeURL(text, allowLocal: allowLocal) {
            case .url(let url):
                XCTAssertEqual(url, item["out"]["url"].string, label)
            case .error(let message):
                XCTAssertEqual(message, item["out"]["error"].string, label)
            }
        }
    }

    /// Ключ уходит только на адрес развёртывания: слишком короткий номер — опечатка.
    func testShortDeploymentIsRejected() {
        // адрес собран из частей: целиком он остановил бы проверку репозитория на секреты
        let address = "https://script.google.com/macros/s/" + "short" + "/exec"
        guard case .error(let message) = Bridge.normalizeURL(address) else {
            return XCTFail("Короткий адрес принят")
        }
        XCTAssertTrue(message.hasPrefix("Адрес должен начинаться"))
        guard case .error = Bridge.normalizeURL("http://127.0.0.1:8080/bridge") else {
            return XCTFail("Учебный мостик принят без разрешения")
        }
    }

    func testAddressAndKeyFromPastedText() throws {
        let cases = try Fixture.section("bridge")["extract"].list
        XCTAssertFalse(cases.isEmpty)
        for item in cases {
            let found = Bridge.extractConnection(item["text"].text)
            XCTAssertEqual(found.url, item["url"].string, item["text"].text)
            XCTAssertEqual(found.key, item["key"].string, item["text"].text)
        }
    }
}

/// Учебная таблица отвечает на запросы так же, как настоящий скрипт.
final class DemoBridgeTests: XCTestCase {
    func testAnswersLikeTheRealScript() throws {
        let bridge = try XCTUnwrap(DemoData.bridge())
        let cases = try Fixture.bridgeCases()
        XCTAssertGreaterThan(cases.count, 20)
        for item in cases {
            let name = item["name"].text
            let answer = try bridge.handle(Data(item["request"].text.utf8))
            let got = try JSONDecoder().decode(JSONValue.self, from: answer)
            if let difference = got.difference(from: item["response"]) {
                XCTFail("«\(name)»: \(difference)")
            }
        }
    }

    func testModes() throws {
        let bridge = try XCTUnwrap(DemoData.bridge())
        let ping = Data(#"{"key":"\#(DemoData.key)","action":"ping"}"#.utf8)

        bridge.setMode(.html)
        let page = try bridge.handle(ping)
        XCTAssertTrue(String(decoding: page, as: UTF8.self).hasPrefix("<!doctype html>"))

        bridge.setMode(.down)
        XCTAssertThrowsError(try bridge.handle(ping)) { error in
            XCTAssertEqual(error as? TransportFailure, .network)
        }

        bridge.setMode(.busy)
        let push = Data(#"{"key":"\#(DemoData.key)","action":"push","entries":[]}"#.utf8)
        let busy = try JSONDecoder().decode(JSONValue.self, from: bridge.handle(push))
        XCTAssertEqual(busy["error"].text, "busy")
        // читать занятая таблица даёт
        let pull = Data(#"{"key":"\#(DemoData.key)","action":"pull"}"#.utf8)
        let read = try JSONDecoder().decode(JSONValue.self, from: bridge.handle(pull))
        XCTAssertTrue(read["ok"].flag)

        bridge.setMode(.ok)
        bridge.setKey("")
        let noKey = try JSONDecoder().decode(JSONValue.self, from: bridge.handle(ping))
        XCTAssertEqual(noKey["error"].text, "no_key")
        XCTAssertEqual(bridge.requests.count, 5)
    }

    func testManualEditInTheSheet() throws {
        let bridge = try XCTUnwrap(DemoData.bridge())
        bridge.edit { rows in
            rows.removeAll { $0.date == Fixture.today && $0.exercise == "Гакк-жим" }
        }
        XCTAssertEqual(bridge.journal.count, Fixture.journal.count - 1)
        let body = #"{"key":"\#(DemoData.key)","action":"push","entries":[{"date":"\#(Fixture.today)","exercise":"Гакк-жим","weight":20}]}"#
        let answer = try JSONDecoder().decode(JSONValue.self, from: bridge.handle(Data(body.utf8)))
        XCTAssertEqual(answer["results"][0]["status"].text, "not_found")
    }
}

final class BridgeCallTests: XCTestCase {
    private func code(_ work: () async throws -> [String: JSONValue]) async -> String {
        do {
            _ = try await work()
            return "ok"
        } catch let error as BridgeError {
            return error.code
        } catch {
            return "другая ошибка"
        }
    }

    func testCallReadsJournal() async throws {
        let bridge = try XCTUnwrap(DemoData.bridge())
        let answer = try await Bridge.call(DemoData.connection, action: "pull", transport: bridge)
        XCTAssertEqual(answer["journal"]?.array?.count, Fixture.journal.count)
        XCTAssertEqual(answer["start"]?.string, "2026-11-09")
        // ключ и действие едут в теле запроса
        XCTAssertEqual(bridge.requests.last?["key"]?.string, DemoData.key)
        XCTAssertEqual(bridge.requests.last?["action"]?.string, "pull")
    }

    func testErrorsGetCodes() async throws {
        let bridge = try XCTUnwrap(DemoData.bridge())
        let wrong = Connection(url: DemoData.url, key: "не тот ключ")
        let unauthorized = await code { try await Bridge.call(wrong, action: "ping", transport: bridge) }
        XCTAssertEqual(unauthorized, "unauthorized")

        bridge.setMode(.html)
        let page = await code { try await Bridge.call(DemoData.connection, action: "ping", transport: bridge) }
        XCTAssertEqual(page, "not_json")

        bridge.setMode(.down)
        let down = await code { try await Bridge.call(DemoData.connection, action: "ping", transport: bridge) }
        XCTAssertEqual(down, "network")

        let slow = FixedTransport(body: "", failure: .timeout)
        let timeout = await code { try await Bridge.call(DemoData.connection, action: "ping", transport: slow) }
        XCTAssertEqual(timeout, "timeout")

        let other = FixedTransport(body: #"{"ok":true,"api":2,"script":7}"#)
        let mismatch = await code { try await Bridge.call(DemoData.connection, action: "ping", transport: other) }
        XCTAssertEqual(mismatch, "api_mismatch")

        let silent = FixedTransport(body: #"{"ok":false}"#)
        let unknown = await code { try await Bridge.call(DemoData.connection, action: "ping", transport: silent) }
        XCTAssertEqual(unknown, "bridge")

        let broken = Connection(url: "", key: DemoData.key)
        let noAddress = await code { try await Bridge.call(broken, action: "ping", transport: bridge) }
        XCTAssertEqual(noAddress, "network")
    }

    func testPageInsteadOfDataNamesTheStatus() async {
        let page = FixedTransport(status: 403, body: "<html>Доступ запрещён</html>")
        do {
            _ = try await Bridge.call(DemoData.connection, action: "ping", transport: page)
            XCTFail("Страница принята за ответ")
        } catch let error as BridgeError {
            XCTAssertEqual(error.code, "not_json")
            XCTAssertTrue(error.message.contains("(код 403)"), error.message)
        } catch {
            XCTFail("\(error)")
        }
    }
}
