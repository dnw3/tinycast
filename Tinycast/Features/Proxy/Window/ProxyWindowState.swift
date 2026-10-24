import Foundation

/// The proxy window's pages, in sidebar order.
enum ProxyWindowPage: String, CaseIterable, Identifiable, Sendable {
    case overview
    case nodes
    case routes
    case sources
    case activity

    var id: String { rawValue }

    var title: LocalizedStringResource {
        switch self {
        case .overview: "Overview"
        case .nodes: "Nodes"
        case .routes: "Routing"
        case .sources: "Subscriptions"
        case .activity: "Activity"
        }
    }

    var symbol: String {
        switch self {
        case .overview: "gauge.with.dots.needle.67percent"
        case .nodes: "network"
        case .routes: "arrow.triangle.branch"
        case .sources: "link"
        case .activity: "waveform.path.ecg"
        }
    }
}

/// What the open proxy window shows; it lives as long as the window and persists nothing.
@MainActor
@Observable
final class ProxyWindowState {
    var page: ProxyWindowPage
    /// The strategy the Nodes page shows; nil shows the default one.
    var nodesStrategy: UUID?
    /// The one source the Nodes page narrows a strategy's nodes to; nil shows every source's.
    var nodesSource: UUID?
    /// Region groups opened or closed by hand, keyed by `ProxyRegionGroup.id`, for every strategy.
    var regionExpansion: [String: Bool] = [:]
    /// The fold of region strategies among a strategy's options, if opened or closed by hand.
    var regionStrategiesOpen: Bool?
    /// An editor a command asked for, opened by the window's root, which then clears it.
    var editRequest: ProxyEditRequest?

    init(page: ProxyWindowPage) {
        self.page = page
    }
}
