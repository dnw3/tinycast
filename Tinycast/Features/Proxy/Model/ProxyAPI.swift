import Foundation

/// The core's REST payloads. Fields the core leaves out, or sends as null, decode as empty.
enum ProxyAPI {
    struct Version: Decodable, Sendable {
        var version: String
    }

    struct DelayRecord: Decodable, Equatable, Sendable {
        var delay: Int
    }

    /// One test URL's results; `alive` describes the latest one.
    struct TestHistory: Decodable, Equatable, Sendable {
        var alive: Bool
        var history: [DelayRecord]

        init(alive: Bool, history: [DelayRecord]) {
            self.alive = alive
            self.history = history
        }

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            alive = try container.decodeIfPresent(Bool.self, forKey: .alive) ?? true
            history = try container.decodeIfPresent([DelayRecord].self, forKey: .history) ?? []
        }

        private enum CodingKeys: String, CodingKey {
            case alive
            case history
        }
    }

    /// A group, a built-in outbound or a node. Only groups carry `now` and `all`.
    struct Proxy: Decodable, Equatable, Sendable {
        var name: String
        var type: String
        var udp: Bool
        var latest: TestHistory
        var tests: [String: TestHistory]
        var now: String?
        var all: [String]
        var hidden: Bool
        var testURL: String?
        var providerName: String?

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            name = try container.decode(String.self, forKey: .name)
            type = try container.decode(String.self, forKey: .type)
            udp = try container.decodeIfPresent(Bool.self, forKey: .udp) ?? false
            latest = TestHistory(
                alive: try container.decodeIfPresent(Bool.self, forKey: .alive) ?? true,
                history: try container.decodeIfPresent([DelayRecord].self, forKey: .history) ?? [])
            tests = try container.decodeIfPresent([String: TestHistory].self, forKey: .extra) ?? [:]
            now = try container.decodeIfPresent(String.self, forKey: .now).flatMap { $0.isEmpty ? nil : $0 }
            all = try container.decodeIfPresent([String].self, forKey: .all) ?? []
            hidden = try container.decodeIfPresent(Bool.self, forKey: .hidden) ?? false
            testURL = try container.decodeIfPresent(String.self, forKey: .testURL).flatMap {
                $0.isEmpty ? nil : $0
            }
            providerName = try container.decodeIfPresent(String.self, forKey: .providerName)
                .flatMap { $0.isEmpty ? nil : $0 }
        }

        private enum CodingKeys: String, CodingKey {
            case name
            case type
            case udp
            case alive
            case history
            case extra
            case now
            case all
            case hidden
            case testURL = "testUrl"
            case providerName = "provider-name"
        }
    }

    struct Proxies: Decodable, Sendable {
        var proxies: [String: Proxy]
    }

    /// From the subscription's `subscription-userinfo` header, in bytes and Unix seconds.
    struct Usage: Decodable, Equatable, Sendable {
        var upload: Int64
        var download: Int64
        var total: Int64
        /// Zero when the subscription never expires.
        var expire: Int64

        private enum CodingKeys: String, CodingKey {
            case upload = "Upload"
            case download = "Download"
            case total = "Total"
            case expire = "Expire"
        }
    }

    struct Provider: Decodable, Sendable {
        var name: String
        /// `HTTP` or `File` for a source; `Compatible` for the members a group lists itself.
        var vehicleType: String
        var proxies: [Proxy]
        var updatedAt: Date?
        var usage: Usage?

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            name = try container.decode(String.self, forKey: .name)
            vehicleType = try container.decode(String.self, forKey: .vehicleType)
            proxies = try container.decodeIfPresent([Proxy].self, forKey: .proxies) ?? []
            updatedAt = try container.decodeIfPresent(String.self, forKey: .updatedAt).flatMap(ProxyAPI.date)
            usage = try container.decodeIfPresent(Usage.self, forKey: .usage)
        }

        private enum CodingKeys: String, CodingKey {
            case name
            case vehicleType
            case proxies
            case updatedAt
            case usage = "subscriptionInfo"
        }
    }

    struct Providers: Decodable, Sendable {
        var providers: [String: Provider]
    }

    struct RuleProvider: Decodable, Sendable {
        var name: String
        var ruleCount: Int
        var updatedAt: Date?

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            name = try container.decode(String.self, forKey: .name)
            ruleCount = try container.decodeIfPresent(Int.self, forKey: .ruleCount) ?? 0
            updatedAt = try container.decodeIfPresent(String.self, forKey: .updatedAt).flatMap(ProxyAPI.date)
        }

        private enum CodingKeys: String, CodingKey {
            case name
            case ruleCount
            case updatedAt
        }
    }

    struct RuleProviders: Decodable, Sendable {
        var providers: [String: RuleProvider]
    }

    /// One second of `/traffic`: rates in bytes per second, totals since the core started.
    struct Traffic: Decodable, Equatable, Sendable {
        var up: Int64
        var down: Int64
        var upTotal: Int64?
        var downTotal: Int64?
    }

    /// One open connection as `/connections` lists it.
    struct Connection: Decodable, Equatable, Identifiable, Sendable {
        var id: String
        /// `tcp` or `udp`.
        var network: String
        /// The name asked for, or else the one sniffed from its traffic; empty for a bare address.
        var host: String
        var destinationIP: String
        var destinationPort: Int
        /// Empty when the core could not tell which app opened it.
        var process: String
        /// How it came in: `HTTP`, `Socks5` or `Tun`, or `Inner` for one the core opened itself.
        var inbound: String
        var upload: Int64
        var download: Int64
        var start: Date?
        /// The node first and the outermost group last, as the core records them.
        var chains: [String]
        /// The matching rule's type, such as `RuleSet` or `Match`, and what it matched on.
        var rule: String
        var rulePayload: String

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = try container.decode(String.self, forKey: .id)
            let metadata = try container.nestedContainer(keyedBy: MetadataKeys.self, forKey: .metadata)
            func text(_ key: MetadataKeys) throws -> String {
                try metadata.decodeIfPresent(String.self, forKey: key) ?? ""
            }
            network = try text(.network)
            let sniffed = try text(.sniffHost)
            let asked = try text(.host)
            host = asked.isEmpty ? sniffed : asked
            destinationIP = try text(.destinationIP)
            destinationPort = try (try? metadata.decodeIfPresent(Int.self, forKey: .destinationPort))
                ?? Int(text(.destinationPort)) ?? 0
            process = try text(.process)
            inbound = try text(.type)
            upload = try container.decodeIfPresent(Int64.self, forKey: .upload) ?? 0
            download = try container.decodeIfPresent(Int64.self, forKey: .download) ?? 0
            start = try container.decodeIfPresent(String.self, forKey: .start).flatMap(ProxyAPI.date)
            chains = try container.decodeIfPresent([String].self, forKey: .chains) ?? []
            rule = try container.decodeIfPresent(String.self, forKey: .rule) ?? ""
            rulePayload = try container.decodeIfPresent(String.self, forKey: .rulePayload) ?? ""
        }

        private enum CodingKeys: String, CodingKey {
            case id
            case metadata
            case upload
            case download
            case start
            case chains
            case rule
            case rulePayload
        }

        private enum MetadataKeys: String, CodingKey {
            case network
            case type
            case host
            case sniffHost
            case destinationIP
            case destinationPort
            case process
        }
    }

    struct Connections: Decodable, Sendable {
        var connections: [Connection]

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            connections = try container.decodeIfPresent([Connection].self, forKey: .connections) ?? []
        }

        private enum CodingKeys: String, CodingKey {
            case connections
        }
    }

    /// One `/logs` record: `type` is the level, such as `warning`.
    struct LogRecord: Decodable, Equatable, Sendable {
        var type: String
        var payload: String
    }

    struct Delay: Decodable, Sendable {
        var delay: Int
    }

    struct Message: Decodable, Sendable {
        var message: String
    }

    /// RFC 3339, with or without fractional seconds; Go's zero time means never.
    static func date(_ text: String) -> Date? {
        guard let date = try? Date.ISO8601FormatStyle(includingFractionalSeconds: true).parse(text) else {
            return nil
        }
        return date.timeIntervalSince1970 > 0 ? date : nil
    }
}
