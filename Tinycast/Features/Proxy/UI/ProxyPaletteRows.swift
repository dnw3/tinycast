import SwiftUI

/// How targets, options and nodes read in the proxy screens, so all three say them alike.
enum ProxyPaletteRows {
    /// The core names its built-in outbounds in capitals; the rows use the words Settings uses.
    static func optionTitle(_ option: String) -> String {
        switch option {
        case "DIRECT": String(localized: "Direct")
        case "REJECT", "REJECT-DROP": String(localized: "Reject")
        default: option
        }
    }

    /// A node as its flag and name, anything else as `optionTitle` spells it.
    static func optionTitle(_ option: String, in snapshot: ProxySnapshot?) -> String {
        snapshot?.nodes[option]?.label ?? optionTitle(option)
    }

    /// Where a target's traffic goes and how fast; routes share strategies, so nodes would repeat.
    static func landing(
        of target: ProxyTarget, profile: ProxyProfile, snapshot: ProxySnapshot?
    ) -> (subtitle: String, trailing: String?, tone: ProxyPaletteRow.Tone) {
        let title = target.title(in: profile)
        guard let id = target.strategyID, let strategy = profile.strategy(id),
            let node = snapshot?.node(reachedBy: id, in: profile)
        else { return (title, nil, .secondary) }
        let delay = node.delay(for: strategy.testURL)
        return (title, delay.label, ProxyPaletteRow.Tone(delay))
    }

    /// A strategy, those made by region apart and under their flags, with its node and that delay.
    static func strategyRow(
        _ strategy: ProxyStrategy, id: String? = nil, reaching node: ProxySnapshot.Node?, isCurrent: Bool
    ) -> ProxyPaletteRow {
        let region = strategy.soleRegion
        let delay = node?.delay(for: strategy.testURL)
        return ProxyPaletteRow(
            id: id ?? strategy.id.uuidString,
            section: region == nil ? String(localized: "Strategies") : String(localized: "Region Strategies"),
            leading: .strategy(strategy), title: strategy.bareName,
            subtitle: node.map { region == nil ? $0.label : ProxyNodeName($0.name).title },
            trailing: delay?.label, trailingTone: delay.map(ProxyPaletteRow.Tone.init) ?? .secondary,
            isCurrent: isCurrent)
    }

    /// Asks the user to connect when there is nothing live to show, and connects on ↵.
    static func connectRow(section: String? = nil) -> ProxyPaletteRow {
        ProxyPaletteRow(
            id: "connect", section: section, leading: .symbol("network.slash"),
            title: String(localized: "The proxy is not connected"),
            subtitle: String(localized: "Press Return to connect"))
    }

    static func matches(_ query: FuzzyMatch.Query, _ fields: String?...) -> Bool {
        query.isEmpty || fields.contains { $0.map { FuzzyMatch.score(query, candidate: $0) != nil } ?? false }
    }
}

/// The ⌘K rows every proxy screen ends with.
@MainActor
enum ProxyPaletteActions {
    static func connectionItem(coordinator: ProxyCoordinator, manager: ProxyManager) -> PopoverMenuItem {
        if manager.store.wantsConnection {
            return PopoverMenuItem(
                title: String(localized: "Disconnect Proxy"), systemImage: "network.slash",
                startsSection: true
            ) {
                coordinator.disconnect()
            }
        }
        return PopoverMenuItem(
            title: String(localized: "Connect Proxy"), systemImage: "network", startsSection: true
        ) {
            coordinator.connect()
        }
    }
}
