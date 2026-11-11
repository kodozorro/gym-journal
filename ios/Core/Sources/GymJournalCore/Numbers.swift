import Foundation

/// Число из поля ввода.
public enum ParsedNumber: Equatable, Sendable {
    /// Поле пустое.
    case empty
    /// Набрано не число.
    case invalid
    case value(Double)

    public var number: Double? {
        if case .value(let value) = self { return value }
        return nil
    }
}

/// Разбор и вывод чисел. Дробную часть пользователь вводит через запятую или точку.
public enum Numbers {
    /// Разбирает число из поля ввода: «42,5», «42.5», «,5».
    public static func parseDecimal(_ input: String) -> ParsedNumber {
        let text = String(input.filter { !$0.isWhitespace })
        if text.isEmpty { return .empty }
        var whole = ""
        var fraction = ""
        var separators = 0
        for character in text {
            if character == "." || character == "," {
                separators += 1
                continue
            }
            guard let ascii = character.asciiValue, ascii >= 48, ascii <= 57 else { return .invalid }
            if separators == 0 { whole.append(character) } else { fraction.append(character) }
        }
        if separators > 1 { return .invalid }
        if separators == 1 && fraction.isEmpty { return .invalid }
        if whole.isEmpty && fraction.isEmpty { return .invalid }
        let normalized = (whole.isEmpty ? "0" : whole) + (fraction.isEmpty ? "" : "." + fraction)
        guard let value = Double(normalized), value.isFinite else { return .invalid }
        return .value(value)
    }

    /// Целое неотрицательное число (повторы).
    public static func parseCount(_ input: String) -> ParsedNumber {
        let parsed = parseDecimal(input)
        if case .value(let value) = parsed, value != value.rounded() { return .invalid }
        return parsed
    }

    /// Округление до ближайшего целого; ровно половина уходит вверх, как в таблице и в веб-приложении.
    public static func roundHalfUp(_ value: Double) -> Double {
        let lower = value.rounded(.down)
        return value - lower >= 0.5 ? lower + 1 : lower
    }

    /// Целое из дробного без аварии на NaN и на числах, которые не помещаются в Int:
    /// на часах Int занимает 32 бита. Значение прижимается к границам.
    public static func int(_ value: Double) -> Int {
        if value.isNaN { return 0 }
        return Int(Swift.max(-2_000_000_000, Swift.min(2_000_000_000, value)))
    }

    public static func roundTo(_ value: Double, _ digits: Int = 2) -> Double {
        let k = pow(10.0, Double(digits))
        return roundHalfUp((value + Double.ulpOfOne) * k) / k
    }

    /// Запись числа без лишних нулей и с точкой: «42.5», «40».
    public static func plain(_ value: Double) -> String {
        if value == value.rounded(), abs(value) < 1e15 { return String(Int64(value)) }
        return "\(value)"
    }

    /// «42,5», «40», «3,25» — без лишних нулей, с запятой.
    public static func format(_ value: Double?, digits: Int = 2) -> String {
        guard let value, value.isFinite else { return "" }
        return plain(roundTo(value, digits)).replacingOccurrences(of: ".", with: ",")
    }

    /// Склонение: `plural(3, "подход", "подхода", "подходов")` → «подхода».
    public static func plural(_ count: Int, _ one: String, _ few: String, _ many: String) -> String {
        let value = abs(count)
        let mod10 = value % 10
        let mod100 = value % 100
        if mod10 == 1 && mod100 != 11 { return one }
        if mod10 >= 2 && mod10 <= 4 && (mod100 < 12 || mod100 > 14) { return few }
        return many
    }
}
