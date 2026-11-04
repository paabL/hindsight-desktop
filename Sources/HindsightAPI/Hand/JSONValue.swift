import Foundation

/// Valeur JSON arbitraire (champs libres de l'API : `metadata`, `request`, `llm_info`, …).
public enum JSONValue: Codable, Sendable, Hashable {
    case null
    case bool(Bool)
    case int(Int)
    case double(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let v = try? c.decode(Bool.self) { self = .bool(v) }
        else if let v = try? c.decode(Int.self) { self = .int(v) }
        else if let v = try? c.decode(Double.self) { self = .double(v) }
        else if let v = try? c.decode(String.self) { self = .string(v) }
        else if let v = try? c.decode([JSONValue].self) { self = .array(v) }
        else if let v = try? c.decode([String: JSONValue].self) { self = .object(v) }
        else { throw DecodingError.dataCorruptedError(in: c, debugDescription: "JSON invalide") }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .null: try c.encodeNil()
        case .bool(let v): try c.encode(v)
        case .int(let v): try c.encode(v)
        case .double(let v): try c.encode(v)
        case .string(let v): try c.encode(v)
        case .array(let v): try c.encode(v)
        case .object(let v): try c.encode(v)
        }
    }

    // MARK: Accès pratiques

    public var stringValue: String? {
        switch self {
        case .string(let s): return s
        case .int(let i): return String(i)
        case .double(let d): return String(d)
        case .bool(let b): return b ? "true" : "false"
        default: return nil
        }
    }
    public var intValue: Int? {
        switch self {
        case .int(let i): return i
        case .double(let d): return Int(exactly: d)
        case .string(let s): return Int(s)
        default: return nil
        }
    }
    public var doubleValue: Double? {
        switch self {
        case .int(let i): return Double(i)
        case .double(let d): return d
        case .string(let s): return Double(s)
        default: return nil
        }
    }
    public var boolValue: Bool? {
        if case .bool(let b) = self { return b }
        return nil
    }
    public var arrayValue: [JSONValue]? {
        if case .array(let a) = self { return a }
        return nil
    }
    public var objectValue: [String: JSONValue]? {
        if case .object(let o) = self { return o }
        return nil
    }
    public var isNull: Bool {
        if case .null = self { return true }
        return false
    }

    public subscript(key: String) -> JSONValue? {
        objectValue?[key]
    }
    public subscript(index: Int) -> JSONValue? {
        guard let a = arrayValue, a.indices.contains(index) else { return nil }
        return a[index]
    }

    /// JSON lisible (clés triées) pour affichage brut.
    public func prettyString() -> String {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        guard let d = try? enc.encode(self), let s = String(data: d, encoding: .utf8) else { return "" }
        return s
    }
}

extension JSONValue: ExpressibleByStringLiteral, ExpressibleByIntegerLiteral, ExpressibleByBooleanLiteral,
    ExpressibleByFloatLiteral, ExpressibleByNilLiteral, ExpressibleByArrayLiteral, ExpressibleByDictionaryLiteral
{
    public init(stringLiteral value: String) { self = .string(value) }
    public init(integerLiteral value: Int) { self = .int(value) }
    public init(booleanLiteral value: Bool) { self = .bool(value) }
    public init(floatLiteral value: Double) { self = .double(value) }
    public init(nilLiteral: ()) { self = .null }
    public init(arrayLiteral elements: JSONValue...) { self = .array(elements) }
    public init(dictionaryLiteral elements: (String, JSONValue)...) {
        self = .object(Dictionary(elements, uniquingKeysWith: { $1 }))
    }
}
