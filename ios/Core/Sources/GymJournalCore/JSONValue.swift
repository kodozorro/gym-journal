import Foundation

/// Произвольное значение JSON.
///
/// Ответ скрипта сначала разбирается в него, а потом приводится к строкам журнала:
/// одно неожиданное поле не должно ронять разбор всего ответа.
public enum JSONValue: Equatable, Sendable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    /// Конечное число или nil.
    public var number: Double? {
        if case .number(let value) = self, value.isFinite { return value }
        return nil
    }

    public var string: String? {
        if case .string(let value) = self { return value }
        return nil
    }

    public var array: [JSONValue]? {
        if case .array(let value) = self { return value }
        return nil
    }

    public var object: [String: JSONValue]? {
        if case .object(let value) = self { return value }
        return nil
    }

    /// Целое число или nil.
    public var integer: Int? {
        // граница с запасом меньше 2^31: на часах Int занимает 32 бита
        guard let value = number, value == value.rounded(), abs(value) <= 2_000_000_000 else { return nil }
        return Int(value)
    }

    public static func optional(_ value: Double?) -> JSONValue {
        value.map { JSONValue.number($0) } ?? .null
    }
}

extension JSONValue: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else if let value = try? container.decode([String: JSONValue].self) {
            self = .object(value)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Значение не похоже на JSON")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null:
            try container.encodeNil()
        case .bool(let value):
            try container.encode(value)
        case .number(let value):
            try container.encode(value)
        case .string(let value):
            try container.encode(value)
        case .array(let value):
            try container.encode(value)
        case .object(let value):
            try container.encode(value)
        }
    }
}
