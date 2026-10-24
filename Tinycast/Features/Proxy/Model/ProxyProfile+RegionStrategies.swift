import Foundation

extension ProxyProfile {
    /// A strategy taking exactly this region's nodes already, which another would only repeat.
    func strategy(forRegion region: ProxyRegion) -> ProxyStrategy? {
        strategies.first { $0.pool.map { $0.regions == [region] && $0.pattern.isEmpty } == true }
    }

    /// One strategy per region, in the region table's order, taking it from every source.
    @discardableResult
    mutating func addRegionStrategies(
        _ regions: Set<ProxyRegion>, kind: ProxyStrategy.Kind, offeredByDefault: Bool,
        named name: (ProxyRegion) -> String, newID: () -> UUID
    ) -> [UUID] {
        var names = Set(strategies.map { $0.name.lowercased() })
        let tints = ProxyStrategy.Tint.allCases
        var unusedTints = tints.filter { tint in !strategies.contains { $0.tint == tint } }
        var added: [UUID] = []
        for region in ProxyRegion.allCases where regions.contains(region) {
            let base = name(region)
            let candidates = [base] + (2...99).map { "\(base) \($0)" }
            let unique = candidates.first { !names.contains($0.lowercased()) } ?? base
            names.insert(unique.lowercased())
            let tint = unusedTints.isEmpty ? tints[strategies.count % tints.count] : unusedTints.removeFirst()
            let pool = ProxyStrategy.Pool(sources: nil, regions: [region], pattern: "", exclude: "")
            let strategy = ProxyStrategy(id: newID(), name: unique, kind: kind, tint: tint, pool: pool)
            strategies.append(strategy)
            added.append(strategy.id)
        }
        if offeredByDefault, let index = strategies.firstIndex(where: { $0.id == defaultStrategy }) {
            strategies[index].members += added.map(ProxyTarget.strategy)
        }
        return added
    }
}
