import Foundation

/// A policy group: picks one of its options by hand, by delay, by order or by spreading the load.
struct ProxyStrategy: Codable, Equatable, Identifiable, Sendable {
    enum Kind: String, Codable, CaseIterable, Sendable {
        case select
        case urlTest = "url-test"
        case fallback
        case loadBalance = "load-balance"
    }

    enum Tint: String, Codable, CaseIterable, Sendable {
        case blue
        case cyan
        case purple
        case orange
        case green
        case pink
    }

    /// The nodes offered after the members.
    struct Pool: Codable, Equatable, Sendable {
        /// Nil takes every enabled source, so one added later joins without an edit.
        var sources: [UUID]?
        /// A node is in the pool when it names one of the regions or matches the pattern.
        var regions: [ProxyRegion]
        var pattern: String
        var exclude: String

        static let everything = Pool(sources: nil, regions: [], pattern: "", exclude: "")
    }

    var id: UUID
    var name: String
    var tint: Tint
    var kind: Kind
    var members: [ProxyTarget]
    var pool: Pool?
    var testURL: String
    /// Seconds between delay tests; the core skips them while nothing routes through the strategy.
    var testInterval: Int
    var tolerance: Int
    /// The option last picked in a select strategy, picked again whenever the core reloads.
    var selected: String?

    static let defaultTestURL = "https://www.gstatic.com/generate_204"

    init(
        id: UUID, name: String, kind: Kind, tint: Tint = .blue, members: [ProxyTarget] = [],
        pool: Pool? = .everything
    ) {
        self.id = id
        self.name = name
        self.tint = tint
        self.kind = kind
        self.members = members
        self.pool = pool
        self.testURL = Self.defaultTestURL
        self.testInterval = 300
        self.tolerance = 50
        self.selected = nil
    }
}

extension ProxyStrategy.Pool {
    /// One filter, excluding by lookahead, so mihomo never moves the members or drops one.
    var filter: String? {
        let included = regions.map(\.filter) + (pattern.isEmpty ? [] : [pattern])
        let inclusion =
            included.isEmpty ? "" : ".*(?:" + included.map { "(?:\($0))" }.joined(separator: "|") + ")"
        let exclusion = exclude.isEmpty ? "" : "(?!.*(?:\(exclude)))"
        return inclusion.isEmpty && exclusion.isEmpty ? nil : "^" + exclusion + inclusion
    }

    /// The names the filter keeps, judged by ICU; the core's regexp2 agrees on any valid pattern.
    func admitted(_ names: [String]) -> [String] {
        guard let filter else { return names }
        guard let regex = try? NSRegularExpression(pattern: filter) else { return [] }
        return names.filter { regex.firstMatch(in: $0, range: NSRange($0.startIndex..., in: $0)) != nil }
    }
}
