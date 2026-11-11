import Foundation

/// Поле экранной цифровой клавиатуры.
///
/// Системная клавиатура для чисел не вызывается: она закрывает пол-экрана,
/// а в зале вводить нужно одной рукой и быстро.
public struct KeypadField: Equatable, Sendable, Identifiable {
    public var name: String
    public var label: String
    public var unit: String
    /// Набранное, с запятой: «42,5».
    public var text: String
    /// Показано прежнее значение; первая цифра его заменит.
    public var fresh: Bool
    /// Только целые (повторы).
    public var integer: Bool
    /// Наибольшее допустимое число.
    public var max: Double?
    /// Знаков после запятой.
    public var digits: Int
    /// Цифр до запятой.
    public var whole: Int

    public var id: String { name }

    public init(
        name: String, label: String = "", unit: String = "", value: Double? = nil, integer: Bool = false,
        max: Double? = nil, digits: Int = 2, whole: Int = 4
    ) {
        self.name = name
        self.label = label
        self.unit = unit
        self.text = value.map { Numbers.format($0, digits: integer ? 0 : digits) } ?? ""
        self.fresh = value != nil
        self.integer = integer
        self.max = max
        self.digits = integer ? 0 : digits
        self.whole = whole
    }

    /// Нажатие клавиши. Нажатие, которое дало бы недопустимое число, ничего не меняет.
    public func pressing(_ key: KeypadKey) -> KeypadField {
        var next = self
        switch key {
        case .back:
            next.text = fresh ? "" : String(text.dropLast())
            next.fresh = false
            return next
        case .comma:
            let base = fresh ? "" : text
            if integer || base.contains(",") { return settled(base) }
            return accepting(base.isEmpty ? "0," : base + ",", base: base)
        case .digit(let digit):
            guard (0...9).contains(digit) else { return self }
            let base = fresh ? "" : text
            return accepting(base == "0" ? String(digit) : base + String(digit), base: base)
        }
    }

    /// Нажатие не принято: текст прежний, но «свежесть» снимается, если поле уже начали править.
    private func settled(_ base: String) -> KeypadField {
        guard fresh else { return self }
        var next = self
        next.fresh = false
        next.text = base
        return next
    }

    private func accepting(_ candidate: String, base: String) -> KeypadField {
        let parts = candidate.split(separator: ",", maxSplits: 1, omittingEmptySubsequences: false)
        let wholePart = parts.first.map(String.init) ?? ""
        let fraction = parts.count > 1 ? String(parts[1]) : ""
        if wholePart.count > whole || fraction.count > digits { return settled(base) }
        var next = self
        next.fresh = false
        next.text = candidate
        return next
    }

    /// Число из поля.
    public var value: ParsedNumber {
        let trimmed = text.hasSuffix(",") ? String(text.dropLast()) : text
        let parsed = Numbers.parseDecimal(trimmed)
        if integer, case .value(let number) = parsed, number != number.rounded() { return .invalid }
        return parsed
    }

    /// Текст ошибки или пустая строка.
    public var error: String {
        switch value {
        case .invalid:
            return "Это не число."
        case .value(let number):
            if let max, number > max { return "Не больше \(Numbers.format(max))." }
            return ""
        case .empty:
            return ""
        }
    }
}

public enum KeypadKey: Equatable, Sendable {
    case digit(Int)
    case comma
    case back
}
