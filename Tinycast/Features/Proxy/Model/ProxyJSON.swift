import Foundation

/// A mihomo config value; mihomo reads YAML and JSON is YAML, so the config is built as JSON.
enum ProxyJSON: Equatable, Sendable {
    case object([String: ProxyJSON])
    case array([ProxyJSON])
    case string(String)
    case int(Int)
    case bool(Bool)

    subscript(key: String) -> ProxyJSON? {
        if case .object(let fields) = self { return fields[key] }
        return nil
    }

    var string: String? {
        if case .string(let value) = self { return value }
        return nil
    }

    var int: Int? {
        if case .int(let value) = self { return value }
        return nil
    }

    var bool: Bool? {
        if case .bool(let value) = self { return value }
        return nil
    }

    var array: [ProxyJSON]? {
        if case .array(let items) = self { return items }
        return nil
    }

    var object: [String: ProxyJSON]? {
        if case .object(let fields) = self { return fields }
        return nil
    }

    /// Sorted keys, so an unchanged profile yields the same bytes and is not re-applied.
    func encoded(pretty: Bool = false) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        if pretty { encoder.outputFormatting.insert(.prettyPrinted) }
        return try encoder.encode(self)
    }
}

extension ProxyJSON: Encodable {
    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .object(let fields): try container.encode(fields)
        case .array(let items): try container.encode(items)
        case .string(let value): try container.encode(value)
        case .int(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        }
    }
}

extension ProxyJSON: ExpressibleByStringLiteral, ExpressibleByIntegerLiteral, ExpressibleByBooleanLiteral,
    ExpressibleByArrayLiteral, ExpressibleByDictionaryLiteral
{
    init(stringLiteral value: String) { self = .string(value) }
    init(integerLiteral value: Int) { self = .int(value) }
    init(booleanLiteral value: Bool) { self = .bool(value) }
    init(arrayLiteral elements: ProxyJSON...) { self = .array(elements) }

    init(dictionaryLiteral elements: (String, ProxyJSON)...) {
        self = .object(Dictionary(elements, uniquingKeysWith: { _, last in last }))
    }
}
