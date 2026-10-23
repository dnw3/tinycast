import Foundation

/// When the launcher should lead with the proxy, and what on the clipboard it may offer to add.
enum ProxyLauncherHint {
    /// Latin words need four letters or the whole word, so "pro" still finds the apps it means.
    private static let words = ["proxy", "vpn", "mihomo", "clash", "代理", "节点", "翻墙"]

    static func asksForProxy(_ query: String) -> Bool {
        let typed = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !typed.isEmpty else { return false }
        return words.contains { word in
            guard word.hasPrefix(typed) else { return false }
            let isLatin = word.unicodeScalars.allSatisfy(\.isASCII)
            return typed == word || (isLatin ? typed.count >= 4 : typed.count >= 2)
        }
    }

    /// Path words providers put in subscription links; a page someone copied has none of them.
    private static let markers = ["sub", "token", "clash", "mihomo", "v2ray", "flag=", "/link/", "/s/"]

    /// The clipboard's text when it is one web link that reads as a subscription.
    static func subscriptionLink(in clipboard: String?) -> String? {
        guard let text = clipboard?.trimmingCharacters(in: .whitespacesAndNewlines),
            !text.contains(where: \.isWhitespace), ProxyText.isWebURL(text),
            let url = URLComponents(string: text)
        else { return nil }
        let rest = (url.percentEncodedPath + "?" + (url.percentEncodedQuery ?? "")).lowercased()
        return markers.contains(where: rest.contains) ? text : nil
    }

    /// A link with its secret part hidden, to show what ↵ would add without reading it out.
    static func masked(_ link: String) -> String {
        guard let url = URLComponents(string: link), let host = url.host else { return "••••" }
        let first = url.path.split(separator: "/").first.map(String.init)
        let visible = first.flatMap { $0.count <= 8 ? "/" + $0 : nil } ?? ""
        return host + visible + "/••••"
    }
}
