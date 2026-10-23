import Foundation

extension ProxyRouteCategory {
    var title: String {
        if let brand { return brand }
        return switch self {
        case .ads: String(localized: "Ad Blocking")
        case .lan: String(localized: "Local Network")
        case .ai: String(localized: "AI Services")
        case .streaming: String(localized: "Streaming")
        case .apple: String(localized: "Apple Services")
        case .games: String(localized: "Game Platforms")
        case .bilibili: String(localized: "Bilibili")
        case .foreign: String(localized: "Overseas Websites")
        case .china: String(localized: "Mainland China Websites")
        case .devTools: String(localized: "Developer Tools")
        case .scholar: String(localized: "Academic Sites")
        case .tencent: String(localized: "Tencent")
        case .alibaba: String(localized: "Alibaba")
        case .bytedance: String(localized: "ByteDance")
        case .baidu: String(localized: "Baidu")
        case .netease: String(localized: "NetEase")
        case .jd: String(localized: "JD.com")
        case .xiaohongshu: String(localized: "Xiaohongshu")
        case .zhihu: String(localized: "Zhihu")
        case .chinaBanks: String(localized: "Mainland China Banks")
        case .crypto: String(localized: "Cryptocurrency")
        default: rawValue
        }
    }

    /// What a category covers when its name alone does not say; nil for a single product.
    var summary: String? {
        switch self {
        case .ads: String(localized: "Ad and tracking domains")
        case .lan: String(localized: "Private addresses and local names")
        case .ai: String(localized: "ChatGPT, Claude, Gemini, Copilot and more")
        case .streaming: String(localized: "Netflix, YouTube, Disney+, Spotify, TikTok")
        case .apple: String(localized: "App Store, iCloud and system updates")
        case .games: String(localized: "Epic, Battle.net, PlayStation, Xbox and more")
        case .foreign: String(localized: "Every other overseas domain")
        case .china: String(localized: "Mainland China domains and addresses")
        case .devTools: String(localized: "Package registries, code hosts and developer services")
        case .scholar: String(localized: "Journals, papers and academic search")
        case .chinaBanks: String(localized: "Online banking in mainland China")
        case .crypto: String(localized: "Exchanges and wallets")
        default: nil
        }
    }
}

extension ProxyRuleCatalog.Section {
    var title: String {
        switch self {
        case .basics: String(localized: "Basics")
        case .ai: String(localized: "AI")
        case .streaming: String(localized: "Streaming")
        case .social: String(localized: "Social and Messaging")
        case .development: String(localized: "Development")
        case .platforms: String(localized: "Platforms and Tools")
        case .games: String(localized: "Games")
        case .mainlandChina: String(localized: "Mainland China")
        case .finance: String(localized: "Finance")
        }
    }
}

extension ProxyRoute {
    var title: String {
        switch kind {
        case .category(let category): category.title
        case .custom(let name, _): name
        }
    }

    /// The category's summary, or the rule sets it is made of.
    var subtitle: String {
        if case .category(let category) = kind, let summary = category.summary { return summary }
        return ruleSets.map(\.catalogName).joined(separator: " · ")
    }

    static var finalTitle: String { String(localized: "Everything Else") }
    static var finalSubtitle: String { String(localized: "When nothing above matches; always last") }
}
