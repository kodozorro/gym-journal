import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// Обращения к мостику — веб-приложению Apps Script, привязанному к таблице.
//
// Все обращения — POST с JSON в теле и заголовком Content-Type: text/plain. Ключ едет в теле
// запроса: в адресе он попал бы в журналы. Формат обмена тот же, что у веб-приложения,
// поэтому скрипт в таблице менять не нужно.

/// Адрес веб-приложения и ключ.
public struct Connection: Equatable, Codable, Sendable {
    public var url: String
    public var key: String

    public init(url: String, key: String) {
        self.url = url
        self.key = key
    }
}

/// Ошибка обмена с таблицей: короткий код и текст для человека.
public struct BridgeError: Error, Equatable, Sendable {
    /// network, timeout, unauthorized, not_json, api_mismatch и коды самого скрипта.
    public var code: String
    public var message: String

    public init(code: String, message: String) {
        self.code = code
        self.message = message
    }
}

/// Сбой доставки запроса.
public enum TransportFailure: Error, Equatable, Sendable {
    case timeout
    case network
}

public struct TransportResponse: Sendable {
    public var status: Int
    public var body: Data

    public init(status: Int, body: Data) {
        self.status = status
        self.body = body
    }
}

/// Доставка запроса до скрипта. В приложении это URLSession, в тестах — учебная таблица в памяти.
public protocol BridgeTransport: Sendable {
    func post(url: URL, body: Data, timeout: TimeInterval) async throws -> TransportResponse
}

/// Настоящая сеть.
public final class URLSessionTransport: BridgeTransport, @unchecked Sendable {
    private let session: URLSession

    public init(timeout: TimeInterval = Bridge.timeout) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = nil
        configuration.httpShouldSetCookies = false
        configuration.httpCookieAcceptPolicy = .never
        configuration.timeoutIntervalForRequest = timeout
        configuration.timeoutIntervalForResource = timeout
        session = URLSession(configuration: configuration)
    }

    public func post(url: URL, body: Data, timeout: TimeInterval) async throws -> TransportResponse {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: timeout)
        request.httpMethod = "POST"
        request.setValue("text/plain;charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        do {
            // Ответ приходит через перенаправление на script.googleusercontent.com: URLSession идёт по нему сам.
            let (data, response) = try await session.data(for: request)
            return TransportResponse(status: (response as? HTTPURLResponse)?.statusCode ?? 0, body: data)
        } catch let error as URLError where error.code == .timedOut {
            throw TransportFailure.timeout
        } catch {
            throw TransportFailure.network
        }
    }
}

public enum Bridge {
    public static let apiVersion = 1
    /// Версия кода скрипта, под которую написано приложение.
    public static let expectedScript = 1
    /// Сколько секунд ждать ответа скрипта.
    public static let timeout: TimeInterval = 40

    private static let scriptURL = Rx(
        #"^https://script\.google\.com/(?:a/macros/[^/\s]+/s|a/[^/\s]+/macros/s|macros/s)/[A-Za-z0-9_-]{8,}/(exec|dev)$"#
    )
    private static let localURL = Rx(#"^http://(?:localhost|127\.0\.0\.1)(?::[0-9]{1,5})?/\S*$"#)
    private static let wrapping = Rx(#"^[<"'«]+|[>"'»]+$"#)
    private static let queryTail = Rx(#"[?#].*$"#)
    private static let foundScriptURL = Rx(#"https://script\.google\.com/[^\s"'<>«»]+?/(?:exec|dev)\b"#)
    private static let foundLocalURL = Rx(#"http://(?:localhost|127\.0\.0\.1)(?::[0-9]{1,5})?/[^\s"'<>«»]*"#)
    private static let foundKey = Rx(#"(?:^|[^0-9a-f])([0-9a-f]{40})(?![0-9a-f])"#, caseInsensitive: true)

    public enum AddressCheck: Equatable, Sendable {
        case url(String)
        case error(String)
    }

    /// Проверяет адрес веб-приложения. Ключ отправляется только на script.google.com:
    /// опечатка в адресе не должна унести его на чужой сервер.
    /// allowLocal — разрешить учебный мостик на этом же компьютере (только при разработке).
    public static func normalizeURL(_ input: String, allowLocal: Bool = false) -> AddressCheck {
        var text = wrapping.replace(input.trimmingCharacters(in: .whitespacesAndNewlines), with: "")
        if text.isEmpty { return .error("Вставьте адрес веб-приложения.") }
        if allowLocal && localURL.test(text) { return .url(text) }
        text = queryTail.replace(text, with: "")
        guard let match = scriptURL.match(text) else {
            return .error("Адрес должен начинаться с https://script.google.com/macros/s/ и заканчиваться на /exec.")
        }
        if match[1] == "dev" {
            return .error("Это тестовый адрес, он заканчивается на /dev. Нужен адрес развёртывания: он заканчивается на /exec.")
        }
        return .url(text)
    }

    /// Достаёт адрес и ключ из вставленного текста: их удобно переслать на телефон одним сообщением.
    public static func extractConnection(_ text: String) -> (url: String?, key: String?) {
        let url = foundScriptURL.match(text)?[0] ?? foundLocalURL.match(text)?[0]
        var rest = text
        if let url, let range = rest.range(of: url) { rest.replaceSubrange(range, with: " ") }
        let key = foundKey.match(rest)?[1]
        return (url, key)
    }

    /// Вызывает мостик и возвращает разобранный ответ.
    public static func call(
        _ connection: Connection, action: String, payload: [String: JSONValue] = [:],
        transport: BridgeTransport, timeout: TimeInterval = Bridge.timeout
    ) async throws -> [String: JSONValue] {
        var body = payload
        body["key"] = .string(connection.key)
        body["action"] = .string(action)
        guard let url = URL(string: connection.url), let data = try? JSONEncoder().encode(JSONValue.object(body)) else {
            throw BridgeError(code: "network", message: "Нет связи со скриптом таблицы.")
        }

        let response: TransportResponse
        do {
            response = try await transport.post(url: url, body: data, timeout: timeout)
        } catch TransportFailure.timeout {
            throw BridgeError(code: "timeout", message: "Скрипт таблицы не ответил вовремя.")
        } catch {
            throw BridgeError(code: "network", message: "Нет связи со скриптом таблицы.")
        }

        guard let parsed = try? JSONDecoder().decode(JSONValue.self, from: response.body), let object = parsed.object else {
            let status = response.status != 0 && response.status != 200 ? " (код \(response.status))" : ""
            throw BridgeError(
                code: "not_json",
                message: "Скрипт ответил страницей вместо данных\(status). "
                    + "Проверьте, что в развёртывании доступ «Все» и что после правки кода выпущена новая версия."
            )
        }
        guard object["ok"] == .bool(true) else {
            let code = object["error"]?.string ?? ""
            let message = object["message"]?.string ?? ""
            throw BridgeError(
                code: code.isEmpty ? "bridge" : code,
                message: message.isEmpty ? "Скрипт таблицы вернул ошибку." : message
            )
        }
        guard object["api"]?.integer == apiVersion else {
            throw BridgeError(
                code: "api_mismatch",
                message: "Скрипт в таблице другой версии. Обновите код скрипта по инструкции и выпустите новую версию развёртывания."
            )
        }
        return object
    }
}
