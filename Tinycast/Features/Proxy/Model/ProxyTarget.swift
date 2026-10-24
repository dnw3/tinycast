import Foundation

/// Where matched traffic goes: a strategy, or one of the two outcomes the core provides itself.
enum ProxyTarget: Hashable, Sendable {
    case direct
    case reject
    case strategy(UUID)

    var strategyID: UUID? {
        if case .strategy(let id) = self { return id }
        return nil
    }
}

extension ProxyTarget: Codable {
    init(from decoder: any Decoder) throws {
        let value = try decoder.singleValueContainer().decode(String.self)
        switch value {
        case "direct": self = .direct
        case "reject": self = .reject
        default:
            guard value.hasPrefix("strategy:"), let id = UUID(uuidString: String(value.dropFirst(9))) else {
                throw DecodingError.dataCorrupted(
                    .init(codingPath: decoder.codingPath, debugDescription: "Unknown proxy target \(value)"))
            }
            self = .strategy(id)
        }
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .direct: try container.encode("direct")
        case .reject: try container.encode("reject")
        case .strategy(let id): try container.encode("strategy:" + id.uuidString)
        }
    }
}
