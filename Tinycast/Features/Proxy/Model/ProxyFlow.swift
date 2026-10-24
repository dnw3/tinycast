import Foundation

/// The overview's flow map: each kind of traffic on the left, beside the strategy it goes to.
struct ProxyFlow: Equatable, Sendable {
    enum Source: Hashable, Sendable {
        /// The user's own rules, drawn as one row since each can go somewhere else.
        case rules(count: Int)
        /// A route by id; `ProxyRoute.finalID` is the remaining traffic.
        case route(String)
    }

    struct Row: Equatable, Identifiable, Sendable {
        var source: Source
        /// One for a route; every distinct target for the rules.
        var targets: [ProxyTarget]

        var id: Source { source }
    }

    /// Positions in points, from the top of the map.
    struct Layout: Equatable, Sendable {
        var rows: [Double]
        var targets: [ProxyTarget: Double]
        var height: Double
    }

    /// A site test's path: the row it matched, or every row in a forced mode, and its target.
    struct Highlight: Equatable, Sendable {
        var source: Source?
        var target: ProxyTarget
        /// The node the test went out through, which a strategy spreading its load may not show.
        var exit: String?
        var failed = false
    }

    /// Rules first, then the routes grouped by target in the order the targets are listed.
    var rows: [Row]
    /// Strategies in the profile's order, then Direct and Reject, as far as any row uses them.
    var targets: [ProxyTarget]

    init(profile: ProxyProfile, mode: ProxyMode) {
        let forced: ProxyTarget? =
            switch mode {
            case .rule: nil
            case .global: .strategy(profile.defaultStrategy)
            case .direct: .direct
            }
        func rank(_ target: ProxyTarget) -> Int {
            switch target {
            case .strategy(let id): profile.strategies.firstIndex { $0.id == id } ?? profile.strategies.count
            case .direct: profile.strategies.count + 1
            case .reject: profile.strategies.count + 2
            }
        }
        let routes =
            profile.routes.filter(\.isEnabled).map { Row(source: .route($0.id), targets: [$0.target]) }
            + [Row(source: .route(ProxyRoute.finalID), targets: [profile.finalTarget])]
        let sorted = routes.enumerated().sorted { lhs, rhs in
            (rank(lhs.element.targets[0]), lhs.offset) < (rank(rhs.element.targets[0]), rhs.offset)
        }.map(\.element)
        let rules = profile.rules.filter(\.isEnabled)
        var distinct: [ProxyTarget] = []
        for rule in rules where !distinct.contains(rule.target) { distinct.append(rule.target) }
        var rows = (rules.isEmpty ? [] : [Row(source: .rules(count: rules.count), targets: distinct)]) + sorted
        if let forced {
            for index in rows.indices { rows[index].targets = [forced] }
        }
        self.rows = rows
        targets = Array(Set(rows.flatMap(\.targets))).sorted { rank($0) < rank($1) }
    }

    /// Rows stack in groups by first target; each target sits level with the middle of its rows.
    func layout(rowHeight: Double, groupGap: Double, top: Double, targetSpacing: Double) -> Layout {
        func group(_ row: Row) -> ProxyTarget? { row.source.isRules ? nil : row.targets.first }
        var y = top
        var centers: [Double] = []
        for (index, row) in rows.enumerated() {
            if index > 0, group(row) != group(rows[index - 1]) { y += groupGap }
            centers.append(y + rowHeight / 2)
            y += rowHeight
        }
        var placed: [(ProxyTarget, Double)] = targets.map { target in
            var ys = zip(rows, centers).filter { !$0.0.source.isRules && $0.0.targets.first == target }.map(\.1)
            if ys.isEmpty { ys = zip(rows, centers).filter { $0.0.targets.contains(target) }.map(\.1) }
            return (target, ((ys.min() ?? top) + (ys.max() ?? top)) / 2)
        }
        placed.sort { $0.1 < $1.1 }
        for index in placed.indices.dropFirst() where placed[index].1 - placed[index - 1].1 < targetSpacing {
            placed[index].1 = placed[index - 1].1 + targetSpacing
        }
        let height = max(y, (placed.last?.1 ?? 0) + targetSpacing / 2)
        return Layout(rows: centers, targets: Dictionary(uniqueKeysWithValues: placed), height: height)
    }
}

extension ProxyFlow.Source {
    var isRules: Bool {
        if case .rules = self { return true }
        return false
    }
}

extension ProxyProbe {
    /// The map's path for this test: the row it matched and that row's target, or a forced mode's.
    func highlight(in profile: ProxyProfile, mode: ProxyMode) -> ProxyFlow.Highlight? {
        var exit: String?
        let match: ProxyActivity.Match
        switch outcome {
        case .mode:
            let target: ProxyTarget = mode == .direct ? .direct : .strategy(profile.defaultStrategy)
            return ProxyFlow.Highlight(source: nil, target: target)
        case .matched(let rule, let payload, let node):
            exit = node
            match = ProxyActivity.matching(rule: rule, payload: payload, in: profile)
        case .failed(let rule, let payload, _):
            match = ProxyActivity.matching(rule: rule, payload: payload, in: profile)
        }
        let failed = exit == nil
        switch match {
        case .rule(let id):
            let rules = ProxyFlow(profile: profile, mode: mode).rows.first { $0.source.isRules }
            guard let target = profile.rules.first(where: { $0.id == id })?.target, let rules else { return nil }
            return ProxyFlow.Highlight(source: rules.source, target: target, exit: exit, failed: failed)
        case .route(let id):
            let target = id == ProxyRoute.finalID ? profile.finalTarget : profile.routes.first { $0.id == id }?.target
            guard let target else { return nil }
            return ProxyFlow.Highlight(source: .route(id), target: target, exit: exit, failed: failed)
        case .mode, .core, .unknown:
            return nil
        }
    }
}
