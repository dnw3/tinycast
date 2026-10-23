import Foundation

/// Everything the proxy is configured with; the core's config is built from this alone.
struct ProxyProfile: Codable, Equatable, Sendable {
    var isEnabled: Bool
    var sources: [ProxySource]
    var strategies: [ProxyStrategy]
    /// DNS and rule-set downloads go through it, so it can never be deleted.
    var defaultStrategy: UUID
    var routes: [ProxyRoute]
    /// Where traffic that no rule or route claims goes.
    var finalTarget: ProxyTarget
    var rules: [ProxyUserRule]
    var general: ProxyGeneral

    static func starter(defaultName: String, fastestName: String, newID: () -> UUID) -> ProxyProfile {
        let fastest = ProxyStrategy(id: newID(), name: fastestName, kind: .urlTest, tint: .cyan)
        let primary = ProxyStrategy(
            id: newID(), name: defaultName, kind: .select, members: [.strategy(fastest.id)])
        let target = ProxyTarget.strategy(primary.id)
        return ProxyProfile(
            isEnabled: false, sources: [], strategies: [primary, fastest], defaultStrategy: primary.id,
            routes: recommendedRoutes(to: target), finalTarget: target, rules: [], general: ProxyGeneral())
    }

    /// The recommended routes in match order; `target` stands for the default strategy.
    static func recommendedRoutes(to target: ProxyTarget) -> [ProxyRoute] {
        let pairs: [(ProxyRouteCategory, ProxyTarget)] = [
            (.ads, .reject), (.lan, .direct), (.ai, target), (.streaming, target), (.telegram, target),
            (.github, target), (.apple, .direct), (.foreign, target), (.china, .direct)
        ]
        return pairs.map { ProxyRoute.category($0, to: $1) }
    }

    /// Recommended routes back in order with their targets; every other route stays ahead.
    mutating func restoreRecommendedRoutes() {
        let target = ProxyTarget.strategy(defaultStrategy)
        let recommended = Self.recommendedRoutes(to: target)
        let ids = Set(recommended.map(\.id))
        routes = routes.filter { !ids.contains($0.id) } + recommended
        finalTarget = target
    }

    /// Subscriptions in use, the only sources an update fetches again.
    var hasSubscriptions: Bool {
        sources.contains { $0.kind == .subscription && $0.isEnabled }
    }

    var followsRecommendedRoutes: Bool {
        var restored = self
        restored.restoreRecommendedRoutes()
        return restored == self
    }

    /// Ahead of any route that would match its traffic first: one sharing a set, or a broad one.
    mutating func addRoute(_ route: ProxyRoute) {
        let names = Set(route.ruleSets.map(\.name))
        let broad: Set<String> = [ProxyRouteCategory.foreign.rawValue, ProxyRouteCategory.china.rawValue]
        let index = routes.firstIndex { broad.contains($0.id) || !names.isDisjoint(with: $0.ruleSets.map(\.name)) }
        routes.insert(route, at: index ?? routes.endIndex)
    }

    func strategy(_ id: UUID) -> ProxyStrategy? {
        strategies.first { $0.id == id }
    }
}

extension ProxyRoute {
    var isBuiltIn: Bool {
        if case .category = kind { return true }
        return false
    }
}
