import SwiftUI

/// The editor panels the proxy opens, one at a time, keyed so a second replaces the first.
enum ProxyEditor: Identifiable {
    case source(ProxySourceDraft)
    case nodeFile(URL)
    /// Every source's nodes when nil, else that source's.
    case nodes(UUID?)
    case strategy(ProxyStrategyDraft)
    /// A strategy for each of several regions at once.
    case regionStrategies
    case rules
    /// The route library, with names from the catalog and a link field.
    case addRoute
    /// A new rule-set route from `link` when the id is nil, else the link route with that id.
    case linkRoute(id: String?, link: String)
    /// A rule for a connection the activity page lists, which goes to `current` now.
    case quickRule(host: String, process: String, current: ProxyTarget?)
    case config

    var id: String {
        switch self {
        case .source(let draft): "source-" + draft.source.id.uuidString
        case .nodeFile(let url): "file-" + url.path
        case .nodes(let source): "nodes-" + (source?.uuidString ?? "all")
        case .strategy(let draft): "strategy-" + draft.strategy.id.uuidString
        case .regionStrategies: "region-strategies"
        case .rules: "rules"
        case .addRoute: "add-route"
        case .linkRoute(let id, let link): "route-" + (id ?? link)
        case .quickRule(let host, let process, _): "quick-rule-" + host + "-" + process
        case .config: "config"
        }
    }
}

struct ProxyEditorPanel: View {
    let editor: ProxyEditor
    let manager: ProxyManager
    /// Opens another editor in this one's place, as the library does for a link.
    let replace: (ProxyEditor) -> Void
    let close: () -> Void

    var body: some View {
        switch editor {
        case .source(let draft): ProxySourceEditor(draft: draft, manager: manager, close: close)
        case .nodeFile(let url): ProxyNodeFileEditor(file: url, manager: manager, close: close)
        case .nodes(let source): ProxyNodeListViewer(manager: manager, source: source, close: close)
        case .strategy(let draft): ProxyStrategyEditor(draft: draft, manager: manager, close: close)
        case .regionStrategies: ProxyRegionStrategiesEditor(manager: manager, close: close)
        case .rules: ProxyRulesEditor(manager: manager, close: close)
        case .addRoute: ProxyRouteLibrary(manager: manager, openLink: { replace(.linkRoute(id: nil, link: $0)) }, close: close)
        case .linkRoute(let id, let link):
            ProxyCustomRouteEditor(routeID: id, link: link, manager: manager, close: close)
        case .quickRule(let host, let process, let current):
            ProxyQuickRuleEditor(host: host, process: process, current: current, manager: manager, close: close)
        case .config: ProxyConfigViewer(manager: manager, close: close)
        }
    }
}
