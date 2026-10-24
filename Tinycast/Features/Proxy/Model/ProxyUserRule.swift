import Foundation

/// One of the user's own rules. Every one is matched before any route.
struct ProxyUserRule: Codable, Equatable, Identifiable, Sendable {
    enum Kind: String, Codable, CaseIterable, Sendable {
        case domain
        case domainSuffix
        case domainKeyword
        case ipCIDR
        case processName

        var keyword: String {
            switch self {
            case .domain: "DOMAIN"
            case .domainSuffix: "DOMAIN-SUFFIX"
            case .domainKeyword: "DOMAIN-KEYWORD"
            case .ipCIDR: "IP-CIDR"
            case .processName: "PROCESS-NAME"
            }
        }
    }

    var id: UUID
    var kind: Kind
    /// Always the output of `normalize(_:as:)`.
    var value: String
    var target: ProxyTarget
    var isEnabled: Bool

    /// The value as the core reads it, or nil when it cannot be a rule of this kind.
    static func normalize(_ input: String, as kind: Kind) -> String? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let value: String? =
            switch kind {
            case .domain:
                host(from: trimmed)
            case .domainSuffix:
                String(host(from: trimmed).trimmingPrefix(/(?:[*+]?\.)+/))
            case .domainKeyword:
                trimmed.contains(where: \.isWhitespace) ? nil : trimmed.lowercased()
            case .ipCIDR:
                ProxyCIDR(trimmed)?.text
            case .processName:
                trimmed
            }
        guard let value, !value.isEmpty, ProxyText.isSafe(value) else { return nil }
        switch kind {
        case .domain, .domainSuffix: return isHostname(value) ? value : nil
        case .domainKeyword, .ipCIDR, .processName: return value
        }
    }

    /// The host of a pasted URL or bare host, lowercased, without its port, path or brackets.
    static func host(from input: String) -> String {
        var host = Substring(input.trimmingCharacters(in: .whitespacesAndNewlines))
        if let scheme = host.range(of: "://") { host = host[scheme.upperBound...] }
        if let end = host.firstIndex(where: { "/?#".contains($0) }) { host = host[..<end] }
        if let at = host.lastIndex(of: "@") { host = host[host.index(after: at)...] }
        if host.hasPrefix("["), let close = host.firstIndex(of: "]") {
            host = host[host.index(after: host.startIndex)..<close]
        } else if host.count(where: { $0 == ":" }) == 1, let colon = host.firstIndex(of: ":") {
            host = host[..<colon]
        }
        return host.lowercased()
    }

    private static func isHostname(_ host: String) -> Bool {
        let labels = host.split(separator: ".", omittingEmptySubsequences: false)
        return labels.allSatisfy { label in
            !label.isEmpty && label.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }
        }
    }
}

/// An IPv4 or IPv6 range, held as its masked network so equal ranges compare equal.
struct ProxyCIDR: Equatable, Sendable {
    let bytes: [UInt8]
    let prefix: Int

    init?(_ text: String) {
        let parts = text.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: false)
        guard let address = Self.address(String(parts[0])) else { return nil }
        let width = address.count * 8
        if parts.count == 2 {
            guard let prefix = Int(parts[1]), (0...width).contains(prefix), String(prefix) == parts[1] else {
                return nil
            }
            self.prefix = prefix
        } else {
            self.prefix = width
        }
        bytes = Self.masked(address, prefix: prefix)
    }

    /// Canonical text the core's parser accepts, whatever spelling the user typed.
    var text: String {
        var buffer = [CChar](repeating: 0, count: Int(INET6_ADDRSTRLEN))
        let family = bytes.count == 4 ? AF_INET : AF_INET6
        _ = bytes.withUnsafeBytes { inet_ntop(family, $0.baseAddress, &buffer, socklen_t(buffer.count)) }
        let text = buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
        return (String(bytes: text, encoding: .ascii) ?? "") + "/\(prefix)"
    }

    func contains(_ address: [UInt8]) -> Bool {
        address.count == bytes.count && Self.masked(address, prefix: prefix) == bytes
    }

    /// Four or sixteen bytes, or nil for anything that is not an address literal.
    static func address(_ text: String) -> [UInt8]? {
        var v4 = in_addr()
        if inet_pton(AF_INET, text, &v4) == 1 { return withUnsafeBytes(of: &v4) { Array($0) } }
        var v6 = in6_addr()
        if inet_pton(AF_INET6, text, &v6) == 1 { return withUnsafeBytes(of: &v6) { Array($0) } }
        return nil
    }

    private static func masked(_ address: [UInt8], prefix: Int) -> [UInt8] {
        address.enumerated().map { index, byte in
            byte & (~UInt8(0) << (8 - min(max(prefix - index * 8, 0), 8)))
        }
    }
}

/// The rule the core would match first for a host or address; nil leaves it to the routes.
enum ProxyRuleMatch {
    static func firstMatch(in rules: [ProxyUserRule], for input: String) -> ProxyUserRule? {
        let host = ProxyUserRule.host(from: input)
        let address = ProxyCIDR.address(host)
        return rules.first { rule in
            guard rule.isEnabled else { return false }
            switch rule.kind {
            case .domain: return address == nil && host == rule.value
            case .domainSuffix:
                return address == nil && (host == rule.value || host.hasSuffix("." + rule.value))
            case .domainKeyword: return address == nil && host.contains(rule.value)
            case .ipCIDR: return address.map { ProxyCIDR(rule.value)?.contains($0) == true } ?? false
            case .processName: return false
            }
        }
    }
}

extension ProxyUserRule {
    /// Two-label endings names are sold under, so `bbc.co.uk` never widens to all of `co.uk`.
    private static let secondLevelSuffixes: Set<String> = [
        "co.uk", "org.uk", "ac.uk", "gov.uk", "com.cn", "net.cn", "org.cn", "gov.cn", "edu.cn", "com.hk",
        "com.tw", "co.jp", "ne.jp", "or.jp", "co.kr", "com.sg", "com.au", "net.au", "co.nz", "com.br",
        "co.in", "com.my", "co.th", "com.vn"
    ]

    /// The rules that could match what was typed or taken from the browser, broadest first.
    static func candidates(for input: String) -> [(kind: Kind, value: String)] {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        if ProxyCIDR.address(trimmed) != nil || trimmed.contains("/") && ProxyCIDR(trimmed) != nil,
            let range = normalize(trimmed, as: .ipCIDR)
        {
            return [(.ipCIDR, range)]
        }
        let host = host(from: trimmed)
        guard host.contains("."), let domain = normalize(host, as: .domain) else {
            return [(Kind.processName, trimmed), (.domainKeyword, trimmed.lowercased())].filter {
                normalize($0.1, as: $0.0) == $0.1
            }
        }
        let labels = domain.split(separator: ".").map(String.init)
        let ending = labels.suffix(2).joined(separator: ".")
        let registered = labels.suffix(secondLevelSuffixes.contains(ending) ? 3 : 2).joined(separator: ".")
        var candidates: [(kind: Kind, value: String)] = [(.domainSuffix, registered)]
        if domain != registered { candidates.append((.domainSuffix, domain)) }
        candidates.append((.domain, domain))
        let name = registered.split(separator: ".").first.map(String.init) ?? domain
        if normalize(name, as: .domainKeyword) == name { candidates.append((.domainKeyword, name)) }
        return candidates
    }
}
