import Foundation

/// A node file's top-level sections, counted line by line; the core reads only `proxies` from it.
struct ProxyNodeFileOutline: Equatable, Sendable {
    /// Entries under `proxies`, or the share links of a file that is a list of them.
    var nodes = 0
    var proxyGroups = 0
    var rules = 0
    var ruleProviders = 0
    /// Remote sources the file names; their nodes never reach the pool.
    var proxyProviders = 0
    /// Every other top-level key, such as `port`, `dns` or `tun`, in file order.
    var otherKeys: [String] = []

    var hasUnusedContent: Bool {
        proxyGroups > 0 || rules > 0 || ruleProviders > 0 || proxyProviders > 0 || !otherKeys.isEmpty
    }

    private enum Section {
        case proxies
        case proxyGroups
        case rules
        case ruleProviders
        case proxyProviders
        case other
    }

    /// Indentation alone decides what an entry is, which holds for the block style Clash files use.
    init(text: String) {
        var section: Section?
        var entryIndent: Int?
        var links = 0
        var hasProxies = false
        for line in text.split(whereSeparator: \.isNewline) {
            let content = line.drop { $0 == " " || $0 == "\t" }
            guard !content.isEmpty, !content.hasPrefix("#"), content != "---", content != "..." else {
                continue
            }
            let indent = line.count - content.count
            if indent == 0, !Self.isEntry(content) {
                guard let key = Self.key(of: content) else {
                    if Self.isShareLink(content) { links += 1 }
                    continue
                }
                section = Self.section(named: key)
                entryIndent = nil
                switch section {
                case .proxies: hasProxies = true
                case .other: if !otherKeys.contains(key) { otherKeys.append(key) }
                default: break
                }
                continue
            }
            guard let current = section, current != .other else { continue }
            let isMapping = current == .ruleProviders || current == .proxyProviders
            guard isMapping ? !Self.isEntry(content) && Self.key(of: content) != nil : Self.isEntry(content)
            else { continue }
            if entryIndent == nil { entryIndent = indent }
            guard indent == entryIndent else { continue }
            switch current {
            case .proxies: nodes += 1
            case .proxyGroups: proxyGroups += 1
            case .rules: rules += 1
            case .ruleProviders: ruleProviders += 1
            case .proxyProviders: proxyProviders += 1
            case .other: break
            }
        }
        if !hasProxies { nodes = links }
    }

    private static func section(named key: String) -> Section {
        switch key {
        case "proxies": .proxies
        case "proxy-groups": .proxyGroups
        case "rules": .rules
        case "rule-providers": .ruleProviders
        case "proxy-providers": .proxyProviders
        default: .other
        }
    }

    /// A sequence entry: a dash followed by a space, or alone on its line.
    private static func isEntry(_ content: Substring) -> Bool {
        content == "-" || content.hasPrefix("- ") || content.hasPrefix("-\t")
    }

    /// The key a mapping line opens, without quotes; nil for a line that opens none, such as a URL.
    private static func key(of content: Substring) -> String? {
        guard let colon = content.firstIndex(of: ":") else { return nil }
        let rest = content[content.index(after: colon)...]
        guard rest.isEmpty || rest.first == " " || rest.first == "\t" else { return nil }
        let key = content[..<colon].trimmingCharacters(in: .whitespaces)
        let unquoted = key.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
        return unquoted.isEmpty ? nil : unquoted
    }

    private static func isShareLink(_ content: Substring) -> Bool {
        guard let separator = content.range(of: "://") else { return false }
        let scheme = content[..<separator.lowerBound]
        return !scheme.isEmpty
            && scheme.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "+" || $0 == "-") }
    }
}
