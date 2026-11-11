import Foundation

/// План силового упражнения: «3 × 10–12», «2 × 12–15 на ногу».
public struct StrengthPlan: Equatable, Sendable {
    public var sets: Int
    public var low: Int?
    public var high: Int?
    /// Что написано после чисел: «на ногу».
    public var tail: String
    public var perSide: Bool
    public var text: String
    /// План не разобран: показываются три подхода без диапазона.
    public var unknown: Bool

    public init(sets: Int, low: Int?, high: Int?, tail: String, perSide: Bool, text: String, unknown: Bool) {
        self.sets = sets
        self.low = low
        self.high = high
        self.tail = tail
        self.perSide = perSide
        self.text = text
        self.unknown = unknown
    }

    /// «10–12» или «10», если границы совпадают.
    public var rangeText: String {
        guard let low, let high else { return "" }
        return low == high ? String(low) : "\(low)–\(high)"
    }
}

/// План ходьбы: «3 км», «4–4,5 км, наклон 5–6 %».
public struct CardioPlan: Equatable, Sendable {
    public var km: Double?
    public var kmHigh: Double?
    public var text: String
}

public enum Plan: Equatable, Sendable {
    case strength(StrengthPlan)
    case cardio(CardioPlan)
}

/// Разбор текста из столбца «План». План живёт в таблице, а не в коде: здесь только чтение формата.
public enum Plans {
    public static let maxSets = 3

    // «3 × 10–12», «2 × 12–15 на ногу», «3x10», «2 х 8-10» (латинская x, кириллическая х, знак ×)
    private static let strengthRx = Rx(#"^\s*([0-9]{1,2})\s*[×xXхХ*]\s*([0-9]{1,3})(?:\s*[–—-]\s*([0-9]{1,3}))?\s*(.*)$"#)
    // «3 км», «4–4,5 км», «3–3,5 км, наклон 5–6 %»
    private static let kmRx = Rx(#"([0-9]+(?:[.,][0-9]+)?)(?:\s*[–—-]\s*([0-9]+(?:[.,][0-9]+)?))?\s*км"#, caseInsensitive: true)
    private static let perSideRx = Rx(#"на\s+(ногу|руку|сторону)"#, caseInsensitive: true)

    public static func parse(_ value: String) -> Plan {
        let text = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if let m = strengthRx.match(text), let first = m[1], let second = m[2] {
            let sets = min(max(Int(first) ?? 1, 1), maxSets)
            var low = Int(second) ?? 0
            var high = m[3].flatMap { Int($0) } ?? low
            if high < low { swap(&low, &high) }
            let tail = (m[4] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            return .strength(StrengthPlan(
                sets: sets, low: low, high: high, tail: tail, perSide: perSideRx.test(tail), text: text, unknown: false
            ))
        }
        if let m = kmRx.match(text), let first = m[1] {
            let low = Numbers.parseDecimal(first).number
            let high = m[2].map { Numbers.parseDecimal($0).number } ?? low
            return .cardio(CardioPlan(km: low, kmHigh: high, text: text))
        }
        return .cardio(CardioPlan(km: nil, kmHigh: nil, text: text))
    }

    /// Число подходов и диапазон повторов; если план не разобрать — три подхода без диапазона.
    public static func strength(_ value: String) -> StrengthPlan {
        switch parse(value) {
        case .strength(let plan):
            return plan
        case .cardio(let plan):
            return StrengthPlan(sets: maxSets, low: nil, high: nil, tail: "", perSide: false, text: plan.text, unknown: true)
        }
    }
}
