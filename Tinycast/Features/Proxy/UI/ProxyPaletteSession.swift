import Foundation

/// What the proxy's palette screens are looking at: the rule being made, the strategy being shown.
@MainActor
@Observable
final class ProxyPaletteSession {
    /// The rule a strategy is being picked for, by the screen the new-rule screen pushes.
    struct RuleDraft: Equatable {
        var kind: ProxyUserRule.Kind
        var value: String
    }

    var rule: RuleDraft?
    /// The strategy whose options the node screen lists.
    var strategyID: UUID?
    /// The browser a new rule's site came from, named beside the field.
    var ruleSource: String?
}
