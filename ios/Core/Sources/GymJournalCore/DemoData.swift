import Foundation

/// Учебный журнал с выдуманными числами: для показа приложения без таблицы и для тестов.
///
/// Файл demo.json — ответ настоящего скрипта на запрос pull поверх учебной таблицы, его делает
/// ios/tools/generate.mjs. Адрес и ключ учебные: к Google и к настоящей таблице они не ведут.
public enum DemoData {
    public static let key = "0123456789abcdef0123456789abcdef01234567"
    public static let url = "https://script.google.com/macros/s/TESTDEPLOYMENTID_0123456789/exec"
    /// День, который учебный журнал считает сегодняшним.
    public static let today = "2026-11-25"

    public static var connection: Connection { Connection(url: url, key: key) }

    /// Ответ скрипта на запрос pull.
    public static var pullResponse: Data? {
        guard let file = Bundle.module.url(forResource: "demo", withExtension: "json") else { return nil }
        return try? Data(contentsOf: file)
    }

    /// Учебная таблица, которая отвечает вместо скрипта.
    public static func bridge() -> DemoBridge? {
        guard let data = pullResponse else { return nil }
        return DemoBridge(pullResponse: data, key: key)
    }
}
