import Foundation

/// One downloadable list of domains or address ranges, matched by a `RULE-SET` rule.
struct ProxyRuleSet: Codable, Hashable, Sendable {
    enum Behavior: String, Codable, Sendable {
        case domain
        case ipcidr
        case classical
    }

    enum Format: String, Codable, Sendable {
        case mrs
        case yaml
        case text

        var fileExtension: String {
            switch self {
            case .mrs: "mrs"
            case .yaml: "yaml"
            case .text: "list"
            }
        }
    }

    enum Location: Hashable, Sendable {
        /// A path under the rule catalog's base URL, which the caller chooses.
        case catalog(String)
        case url(String)
    }

    /// The rule-provider name, unique within a configuration.
    var name: String
    var behavior: Behavior
    var format: Format
    var location: Location
    /// China's address list resolves, so an unlisted domain hosted in China still goes direct.
    var resolves: Bool

    /// The MetaCubeX/meta-rules-dat catalog the built-in categories are made of.
    static let catalogBase = "https://github.com/MetaCubeX/meta-rules-dat/raw/meta/geo"

    static func geosite(_ name: String) -> ProxyRuleSet {
        ProxyRuleSet(
            name: "geosite-" + name, behavior: .domain, format: .mrs,
            location: .catalog("geosite/\(name).mrs"),
            resolves: false)
    }

    static func geoip(_ name: String, resolves: Bool = false) -> ProxyRuleSet {
        ProxyRuleSet(
            name: "geoip-" + name, behavior: .ipcidr, format: .mrs, location: .catalog("geoip/\(name).mrs"),
            resolves: resolves)
    }

    func url(catalogBase: String) -> String {
        switch location {
        case .catalog(let path): catalogBase + "/" + path
        case .url(let url): url
        }
    }
}

extension ProxyRuleSet.Location: Codable {
    private enum CodingKeys: String, CodingKey {
        case catalog
        case url
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let path = try container.decodeIfPresent(String.self, forKey: .catalog) {
            self = .catalog(path)
        } else {
            self = .url(try container.decode(String.self, forKey: .url))
        }
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .catalog(let path): try container.encode(path, forKey: .catalog)
        case .url(let url): try container.encode(url, forKey: .url)
        }
    }
}

/// The traffic categories Tinycast knows; each is a fixed set of rule sets from the catalog.
enum ProxyRouteCategory: String, CaseIterable, Codable, Sendable {
    case ads
    case lan
    case ai
    case streaming
    case telegram
    case github
    case apple
    case google
    case microsoft
    case x
    case steam
    case games
    case bilibili
    case foreign
    case china
    case openai
    case anthropic
    case gemini
    case copilot
    case perplexity
    case xai
    case netflix
    case youtube
    case disney
    case spotify
    case tiktok
    case twitch
    case hbo
    case primeVideo
    case hulu
    case appleTV
    case bahamut
    case abema
    case dazn
    case bbc
    case tvb
    case niconico
    case facebook
    case instagram
    case whatsapp
    case discord
    case line
    case reddit
    case signal
    case linkedin
    case pinterest
    case gitlab
    case docker
    case npm
    case python
    case huggingface
    case jetbrains
    case vercel
    case stackOverflow
    case devTools
    case icloud
    case onedrive
    case amazon
    case cloudflare
    case dropbox
    case notion
    case zoom
    case slack
    case wikipedia
    case pixiv
    case scholar
    case epicGames
    case playStation
    case xbox
    case nintendo
    case blizzard
    case ea
    case ubisoft
    case riot
    case tencent
    case alibaba
    case bytedance
    case baidu
    case netease
    case jd
    case xiaohongshu
    case zhihu
    case chinaBanks
    case paypal
    case crypto
    case binance

    var ruleSets: [ProxyRuleSet] {
        switch self {
        case .ads: [.geosite("category-ads-all")]
        case .lan: [.geosite("private"), .geoip("private")]
        case .ai: [.geosite("category-ai-!cn")]
        case .streaming:
            [
                .geosite("netflix"), .geosite("youtube"), .geosite("disney"), .geosite("spotify"),
                .geosite("tiktok"), .geoip("netflix")
            ]
        case .telegram: [.geosite("telegram"), .geoip("telegram")]
        case .google: [.geosite("google"), .geoip("google")]
        case .x: [.geosite("twitter")]
        case .games: [.geosite("category-games")]
        case .foreign: [.geosite("geolocation-!cn")]
        case .china: [.geosite("cn"), .geoip("cn", resolves: true)]
        case .gemini: [.geosite("google-gemini")]
        case .copilot: [.geosite("github-copilot")]
        case .netflix: [.geosite("netflix"), .geoip("netflix")]
        case .primeVideo: [.geosite("primevideo")]
        case .appleTV: [.geosite("apple-tvplus")]
        case .facebook: [.geosite("facebook"), .geoip("facebook")]
        case .npm: [.geosite("npmjs")]
        case .stackOverflow: [.geosite("stackexchange")]
        case .devTools: [.geosite("category-dev")]
        case .cloudflare: [.geosite("cloudflare"), .geoip("cloudflare")]
        case .wikipedia: [.geosite("wikimedia")]
        case .scholar: [.geosite("category-scholar-!cn")]
        case .epicGames: [.geosite("epicgames")]
        case .playStation: [.geosite("playstation")]
        case .chinaBanks: [.geosite("category-bank-cn")]
        case .crypto: [.geosite("category-cryptocurrency")]
        default: [.geosite(rawValue.lowercased())]
        }
    }
}

/// One routing row: traffic matching a category, or the user's own rule sets, goes to a target.
struct ProxyRoute: Codable, Equatable, Identifiable, Sendable {
    enum Kind: Equatable, Sendable {
        case category(ProxyRouteCategory)
        case custom(name: String, ruleSets: [ProxyRuleSet])
    }

    /// The category's raw value, or `custom-` and eight hex digits; stable across renames.
    var id: String
    var kind: Kind
    var target: ProxyTarget
    var isEnabled: Bool

    /// The hidden select group its rules point at, so a new target applies without a reload.
    var groupName: String { "route/" + id }

    var ruleSets: [ProxyRuleSet] {
        switch kind {
        case .category(let category): category.ruleSets
        case .custom(_, let ruleSets): ruleSets
        }
    }

    static func category(_ category: ProxyRouteCategory, to target: ProxyTarget) -> ProxyRoute {
        ProxyRoute(id: category.rawValue, kind: .category(category), target: target, isEnabled: true)
    }

    static let finalID = "final"
    static let finalGroupName = "route/" + finalID
}

extension ProxyRoute.Kind: Codable {
    private enum CodingKeys: String, CodingKey {
        case category
        case name
        case ruleSets
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let category = try container.decodeIfPresent(ProxyRouteCategory.self, forKey: .category) {
            self = .category(category)
        } else {
            self = .custom(
                name: try container.decode(String.self, forKey: .name),
                ruleSets: try container.decode([ProxyRuleSet].self, forKey: .ruleSets))
        }
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .category(let category): try container.encode(category, forKey: .category)
        case .custom(let name, let ruleSets):
            try container.encode(name, forKey: .name)
            try container.encode(ruleSets, forKey: .ruleSets)
        }
    }
}
