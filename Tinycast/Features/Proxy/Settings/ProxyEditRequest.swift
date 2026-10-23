import Foundation

/// An editor the launcher, the menu bar or Settings asks the proxy window to open.
struct ProxyEditRequest: Identifiable, Equatable {
    enum Kind: Equatable {
        /// `connects` when Connect found no source, so saving the first one finishes what it began.
        case addSubscription(link: String?, connects: Bool)
        case importFile
        case editSource(UUID)
        case newStrategy(route: String?)
        case editStrategy(UUID)
        case editRules
        case addRoute
    }

    let id = UUID()
    let kind: Kind
}
