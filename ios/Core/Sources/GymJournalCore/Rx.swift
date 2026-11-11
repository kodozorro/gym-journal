import Foundation

/// Небольшая обёртка над NSRegularExpression: шаблоны проверены тестами, поэтому ошибка в шаблоне —
/// ошибка программиста, а не данных.
struct Rx {
    private let regex: NSRegularExpression

    init(_ pattern: String, caseInsensitive: Bool = false) {
        do {
            regex = try NSRegularExpression(pattern: pattern, options: caseInsensitive ? [.caseInsensitive] : [])
        } catch {
            preconditionFailure("Неверный шаблон: \(pattern)")
        }
    }

    func test(_ text: String) -> Bool {
        regex.firstMatch(in: text, options: [], range: NSRange(text.startIndex..., in: text)) != nil
    }

    /// Первое совпадение: под индексом 0 — всё совпадение, дальше группы; nil — группа не участвовала.
    func match(_ text: String) -> [String?]? {
        guard let found = regex.firstMatch(in: text, options: [], range: NSRange(text.startIndex..., in: text)) else {
            return nil
        }
        var groups: [String?] = []
        for index in 0..<found.numberOfRanges {
            if let range = Range(found.range(at: index), in: text) {
                groups.append(String(text[range]))
            } else {
                groups.append(nil)
            }
        }
        return groups
    }

    /// Заменяет все совпадения шаблона.
    func replace(_ text: String, with template: String) -> String {
        regex.stringByReplacingMatches(in: text, options: [], range: NSRange(text.startIndex..., in: text), withTemplate: template)
    }
}
