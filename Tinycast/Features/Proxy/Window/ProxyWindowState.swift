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
    enum NodesTab: Hashable {
        case strategy(UUID)
        case allNodes
    }

    var page: ProxyWindowPage
    /// Nil opens the default strategy.
    var nodesTab: NodesTab?
    /// An editor a command asked for, opened by the window's root, which then clears it.
    var editRequest: ProxyEditRequest?

    init(page: ProxyWindowPage) {
        self.page = page
    }
}
