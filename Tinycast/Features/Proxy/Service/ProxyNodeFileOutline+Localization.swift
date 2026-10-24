import Foundation

/// Reads a node file off the main actor, for what Settings tells about it.
enum ProxyNodeFileReader {
    /// Nil when the file cannot be read as text.
    @concurrent
    static func outline(of url: URL) async -> ProxyNodeFileOutline? {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        return ProxyNodeFileOutline(text: text)
    }
}

extension ProxyNodeFileOutline {
    /// What the HUD says once the file is a source.
    func importMessage(name: String) -> String {
        if nodes == 0 {
            return proxyProviders > 0
                ? String(localized: "“\(name)” only names providers, whose nodes Tinycast does not read")
                : String(localized: "“\(name)” has no nodes under proxies")
        }
        return hasUnusedContent
            ? String(localized: "Added “\(name)”: only its \(nodes) nodes are used")
            : String(localized: "Added “\(name)” with \(nodes) nodes")
    }

    var nodesTitle: String {
        switch nodes {
        case 0: String(localized: "No nodes under proxies")
        default: String(localized: "\(nodes) nodes")
        }
    }

    /// What in the file goes unused, spelled out; nil when nothing does.
    var unusedSummary: String? {
        var parts: [String] = []
        if proxyGroups > 0 {
            parts.append(String(localized: "\(proxyGroups) proxy groups"))
        }
        if rules > 0 {
            parts.append(String(localized: "\(rules) rules"))
        }
        if ruleProviders > 0 {
            parts.append(String(localized: "\(ruleProviders) rule sets"))
        }
        if proxyProviders > 0 {
            parts.append(String(localized: "\(proxyProviders) proxy providers"))
        }
        if !otherKeys.isEmpty {
            let keys = otherKeys.prefix(3).joined(separator: ", ")
            parts.append(String(localized: "settings such as \(keys)"))
        }
        guard !parts.isEmpty else { return nil }
        return String(localized: "Not used: \(parts.formatted(.list(type: .and)))")
    }
}
