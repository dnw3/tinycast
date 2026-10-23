import Foundation

/// What a rule-set link holds, read from its first bytes: the file format and the kind of entries.
struct ProxyRuleSetDetection: Equatable, Sendable {
    /// The link to download, a GitHub page turned into its file.
    var link: String
    var format: ProxyRuleSet.Format
    var behavior: ProxyRuleSet.Behavior
    /// The file's name without its extension, for the route's name.
    var name: String
    /// Entries the sample held; nil for a compressed `.mrs`, whose entries cannot be read here.
    var entries: Int?

    /// How many bytes to download for `detect`; a list's kind shows in its first lines.
    static let sampleLength = 64 << 10

    /// The rule types a classical list names before its first comma.
    static let ruleTypes: Set<String> = [
        "DOMAIN", "DOMAIN-SUFFIX", "DOMAIN-KEYWORD", "DOMAIN-REGEX", "DOMAIN-WILDCARD", "GEOSITE", "GEOIP",
        "SRC-GEOIP", "IP-ASN", "SRC-IP-ASN", "IP-CIDR", "IP-CIDR6", "SRC-IP-CIDR", "IP-SUFFIX", "SRC-IP-SUFFIX",
        "SRC-PORT", "DST-PORT", "IN-PORT", "IN-USER", "IN-NAME", "IN-TYPE", "PROCESS-NAME", "PROCESS-PATH",
        "PROCESS-NAME-REGEX", "PROCESS-PATH-REGEX", "PROCESS-NAME-WILDCARD", "PROCESS-PATH-WILDCARD", "NETWORK",
        "DSCP", "UID", "AND", "OR", "NOT", "SUB-RULE", "RULE-SET", "MATCH", "USER-AGENT", "URL-REGEX"
    ]

    /// `github.com/<owner>/<repo>/blob/…` is a web page; `/raw/` there serves the file itself.
    static func normalize(_ link: String) -> String {
        let trimmed = link.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var components = URLComponents(string: trimmed), components.host == "github.com" else { return trimmed }
        var parts = components.path.split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count > 4, parts[3] == "blob" else { return trimmed }
        parts[3] = "raw"
        components.path = parts.joined(separator: "/")
        return components.string ?? trimmed
    }

    /// Reads the format from the bytes, never the extension: Loyalsoldier's `.txt` files are YAML.
    static func detect(link: String, sample: Data, isComplete: Bool) -> ProxyRuleSetDetection {
        let link = normalize(link)
        if sample.starts(with: zstdMagic) {
            return ProxyRuleSetDetection(
                link: link, format: .mrs, behavior: behaviorFromPath(link), name: name(of: link), entries: nil)
        }
        // A cut sample can end inside a line, even a character, so only whole lines are read.
        let whole = isComplete ? sample : sample.lastIndex(of: 0x0A).map { sample[...$0] } ?? Data()
        let lines = (String(bytes: whole, encoding: .utf8) ?? "").split(whereSeparator: \.isNewline)
        let meaningful = lines.map { $0.trimmingCharacters(in: .whitespaces.union(["\u{FEFF}"])) }
            .filter { !$0.isEmpty && !isComment($0) }
        let isYAML = meaningful.first?.hasPrefix("payload:") == true
        let entries =
            isYAML
            ? meaningful.dropFirst().compactMap { line in
                line.hasPrefix("-") ? unquoted(line.dropFirst().trimmingCharacters(in: .whitespaces)) : nil
            }
            : meaningful
        return ProxyRuleSetDetection(
            link: link, format: isYAML ? .yaml : .text, behavior: behavior(of: entries), name: name(of: link),
            entries: entries.count)
    }

    /// The best guess when the link could not be read: its extension and path.
    static func guess(link: String) -> ProxyRuleSetDetection {
        let link = normalize(link)
        let path = (URLComponents(string: link)?.path ?? link).lowercased()
        let format: ProxyRuleSet.Format =
            path.hasSuffix(".mrs") ? .mrs : path.hasSuffix(".yaml") || path.hasSuffix(".yml") ? .yaml : .text
        let behavior = format == .mrs ? behaviorFromPath(link) : .domain
        return ProxyRuleSetDetection(link: link, format: format, behavior: behavior, name: name(of: link), entries: nil)
    }

    /// Mixed when any entry names its rule type, addresses when every entry is one, else domains.
    static func behavior(of entries: [String]) -> ProxyRuleSet.Behavior {
        if entries.contains(where: isClassical) { return .classical }
        if !entries.isEmpty, entries.allSatisfy({ ProxyCIDR($0) != nil }) { return .ipcidr }
        return .domain
    }

    private static let zstdMagic: [UInt8] = [0x28, 0xB5, 0x2F, 0xFD]

    private static func isClassical(_ entry: String) -> Bool {
        guard let comma = entry.firstIndex(of: ",") else { return false }
        return ruleTypes.contains(entry[..<comma].trimmingCharacters(in: .whitespaces).uppercased())
    }

    private static func isComment(_ line: String) -> Bool {
        line.hasPrefix("#") || line.hasPrefix("//") || line.hasPrefix(";")
    }

    private static func unquoted(_ text: String) -> String {
        for quote in ["'", "\""] where text.count >= 2 && text.hasPrefix(quote) && text.hasSuffix(quote) {
            return String(text.dropFirst().dropLast())
        }
        return text
    }

    /// meta-rules-dat keeps address sets under `geoip/`; elsewhere a name such as `cncidr` says it.
    private static func behaviorFromPath(_ link: String) -> ProxyRuleSet.Behavior {
        let path = (URLComponents(string: link)?.path ?? link).lowercased()
        let words = path.split { !$0.isLetter && !$0.isNumber }
        let addressWords: Set<Substring> = ["geoip", "ip", "ipcidr", "cidr", "cncidr", "ips"]
        return words.contains(where: addressWords.contains) || path.contains("cidr") ? .ipcidr : .domain
    }

    private static func name(of link: String) -> String {
        let file = URLComponents(string: link)?.path.split(separator: "/").last.map(String.init) ?? ""
        let stem = file.split(separator: ".").first.map(String.init) ?? file
        return stem.removingPercentEncoding ?? stem
    }
}
