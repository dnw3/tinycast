import Foundation

/// Where one test connection went, read from the line the core logs when it routes a connection.
struct ProxyProbe: Equatable, Sendable {
    /// The host and port the test connects to, from what the user typed.
    struct Destination: Equatable, Sendable {
        var host: String
        var port: Int

        /// A URL or a bare host; the port is the URL's own, else 80 for `http://` and 443.
        init?(_ input: String) {
            let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
            let host = ProxyUserRule.host(from: trimmed)
            guard !host.isEmpty, !host.contains(where: \.isWhitespace) else { return nil }
            self.host = host
            let url = URLComponents(string: trimmed.contains("://") ? trimmed : "https://" + trimmed)
            port = url?.port ?? (trimmed.lowercased().hasPrefix("http://") ? 80 : 443)
        }

        /// As the core logs it: a bracketed IPv6 address, else the host itself.
        var address: String {
            (host.contains(":") ? "[\(host)]" : host) + ":\(port)"
        }
    }

    enum Outcome: Equatable, Sendable {
        /// The rule's type and payload as the core names them, and the node or outcome at the end.
        case matched(rule: String, payload: String, exit: String)
        /// Global or direct mode, which skips the rules and routes.
        case mode(exit: String)
        /// It matched, but the strategy could not connect.
        case failed(rule: String, payload: String, reason: String)
    }

    var destination: Destination
    var outcome: Outcome

    /// The outcome when `line` is the core's record of the connection from `sourcePort`.
    static func outcome(of line: String, sourcePort: Int, destination: Destination) -> Outcome? {
        guard let from = line.range(of: "127.0.0.1:\(sourcePort)"),
            let next = line[from.upperBound...].first, next == "(" || next == " ",
            line.contains("--> \(destination.address)")
        else { return nil }
        let tail = line[from.upperBound...]
        if let match = tail.firstMatch(of: #/--> \S+ match (\w+)(?:\((.*)\))? using (.+)$/#) {
            let (_, rule, payload, chain) = match.output
            return .matched(rule: String(rule), payload: String(payload ?? ""), exit: exit(of: chain))
        }
        if let match = tail.firstMatch(of: #/--> \S+ using (GLOBAL|DIRECT)$/#) {
            return .mode(exit: String(match.output.1))
        }
        if let match = line.firstMatch(of: #/dial .+? \(match (\w+)\/(.*?)\) .+ error: (.+)$/#) {
            let (_, rule, payload, reason) = match.output
            return .failed(rule: String(rule), payload: String(payload), reason: String(reason))
        }
        return nil
    }

    /// `route/ai[香港 01]` names the outermost group and the node; a lone name is the outcome itself.
    private static func exit(of chain: Substring) -> String {
        guard chain.hasSuffix("]"), let open = chain.firstIndex(of: "[") else { return String(chain) }
        return String(chain[chain.index(after: open)..<chain.index(before: chain.endIndex)])
    }
}
