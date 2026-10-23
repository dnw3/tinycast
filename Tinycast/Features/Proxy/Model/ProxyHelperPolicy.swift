import Foundation

/// What the root helper accepts: configs shaped like the builder's, and its file names.
enum ProxyHelperPolicy {
    static let maxConfigSize = 16 << 20
    static let maxFileSize = 64 << 20
    /// Over four times the 57 MB core, so only a runaway transfer ever reaches it.
    static let maxCoreSize = 256 << 20

    /// Every top-level key `ProxyConfigBuilder` writes; others could open a controller or port.
    static let configKeys: Set<String> = [
        "mode", "log-level", "ipv6", "mixed-port", "allow-lan", "unified-delay", "tcp-concurrent",
        "find-process-mode", "profile", "sniffer", "dns", "tun", "proxy-providers", "proxy-groups",
        "rule-providers", "rules"
    ]

    /// A node file Tinycast copies in: only the names the config builder gives file sources.
    static func isProviderFile(_ name: String) -> Bool {
        guard name.hasPrefix("src-"), name.hasSuffix(".yaml") else { return false }
        return ProxyHelperGrant.isLowercaseHex(String(name.dropFirst(4).dropLast(5)), count: 8)
    }

    /// Why the helper refuses `config`, or nothing when it may run it.
    static func problems(inConfig config: Data) -> [String] {
        guard config.count <= maxConfigSize else { return ["config is too large"] }
        guard let object = try? JSONSerialization.jsonObject(with: config),
            let document = object as? [String: Any]
        else { return ["config is not a JSON object"] }
        var problems = document.keys.filter { !configKeys.contains($0) }.sorted().map {
            "unexpected key \($0)"
        }
        for (name, provider) in providers(document["proxy-providers"])
        where !isProviderFile(name + ".yaml") || provider["path"] as? String != "providers/\(name).yaml" {
            problems.append("proxy provider \(name) has an unexpected path")
        }
        for (name, provider) in providers(document["rule-providers"])
        where !isRuleFile(provider["path"] as? String, named: name) {
            problems.append("rule provider \(name) has an unexpected path")
        }
        return problems
    }

    private static func providers(_ value: Any?) -> [(String, [String: Any])] {
        guard let table = value as? [String: Any] else { return [] }
        return table.sorted { $0.key < $1.key }.map { ($0.key, $0.value as? [String: Any] ?? [:]) }
    }

    /// `rules/<name>.<format>`, as the builder writes it; a name such as `geolocation-!cn` passes.
    private static func isRuleFile(_ path: String?, named name: String) -> Bool {
        let unsafe = name.unicodeScalars.contains {
            $0 == "/" || $0 == "\\" || CharacterSet.controlCharacters.contains($0)
        }
        guard !name.isEmpty, name.utf8.count <= 128, !name.hasPrefix("."), !unsafe else { return false }
        return ["mrs", "yaml", "text"].contains { path == "rules/\(name).\($0)" }
    }
}
