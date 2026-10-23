import Foundation

/// The add-route library: the built-in categories by section, and every rule set the catalog holds.
enum ProxyRuleCatalog {
    enum Section: CaseIterable, Sendable {
        case basics
        case ai
        case streaming
        case social
        case development
        case platforms
        case games
        case mainlandChina
        case finance

        var categories: [ProxyRouteCategory] {
            switch self {
            case .basics: [.ads, .lan, .foreign]
            case .ai: [.ai, .openai, .anthropic, .gemini, .copilot, .perplexity, .xai]
            case .streaming:
                [
                    .streaming, .netflix, .youtube, .disney, .spotify, .tiktok, .twitch, .hbo, .primeVideo, .hulu,
                    .appleTV, .bahamut, .abema, .dazn, .bbc, .tvb, .niconico
                ]
            case .social:
                [.telegram, .x, .facebook, .instagram, .whatsapp, .discord, .line, .reddit, .signal, .linkedin, .pinterest]
            case .development:
                [.github, .gitlab, .docker, .npm, .python, .huggingface, .jetbrains, .vercel, .stackOverflow, .devTools]
            case .platforms:
                [
                    .apple, .icloud, .google, .microsoft, .onedrive, .amazon, .cloudflare, .dropbox, .notion, .zoom,
                    .slack, .wikipedia, .pixiv, .scholar
                ]
            case .games: [.games, .steam, .epicGames, .playStation, .xbox, .nintendo, .blizzard, .ea, .ubisoft, .riot]
            case .mainlandChina:
                [.china, .bilibili, .tencent, .alibaba, .bytedance, .baidu, .netease, .jd, .xiaohongshu, .zhihu, .chinaBanks]
            case .finance: [.paypal, .crypto, .binance]
            }
        }
    }

    /// Every geosite set the catalog held when the list was generated, by name.
    static let geosites: [String] = ProxyRuleNames.geosite.split(separator: "\n").map(String.init)
    static let geoips: [String] = ProxyRuleNames.geoip.split(separator: "\n").map(String.init)

    /// Categories whose title, brand, aliases or rule sets contain the query, in library order.
    static func categories(
        matching query: String, title: (ProxyRouteCategory) -> String
    ) -> [ProxyRouteCategory] {
        let needle = fold(query)
        let all = Section.allCases.flatMap(\.categories)
        guard !needle.isEmpty else { return all }
        return all.filter { category in
            let names = [title(category), category.rawValue] + category.aliases
                + category.ruleSets.map(\.catalogName)
            return names.contains { fold($0).contains(needle) }
        }
    }

    /// Catalog sets named like the query, those starting with it first, as `geosite:` or `geoip:`.
    static func ruleSets(matching query: String, limit: Int) -> [ProxyRuleSet] {
        let needle = fold(query).replacing("geosite:", with: "").replacing("geoip:", with: "")
        guard !needle.isEmpty else { return [] }
        func ranked(_ names: [String]) -> [String] {
            let hits = names.filter { $0.contains(needle) }
            return hits.filter { $0.hasPrefix(needle) } + hits.filter { !$0.hasPrefix(needle) }
        }
        let found = ranked(geosites).map { ProxyRuleSet.geosite($0) } + ranked(geoips).map { ProxyRuleSet.geoip($0) }
        return Array(found.prefix(limit))
    }

    /// `geosite:netflix` or `geoip:cn`, when the catalog holds that set.
    static func ruleSet(named text: String) -> ProxyRuleSet? {
        let parts = text.trimmingCharacters(in: .whitespaces).lowercased().split(separator: ":", maxSplits: 1)
        guard parts.count == 2 else { return nil }
        let name = String(parts[1])
        switch parts[0] {
        case "geosite" where geosites.contains(name): return .geosite(name)
        case "geoip" where geoips.contains(name): return .geoip(name)
        default: return nil
        }
    }

    private static func fold(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespaces).folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }
}

extension ProxyRouteCategory {
    /// A product's own name, the same in every language; nil for a category described in words.
    var brand: String? {
        switch self {
        case .telegram: "Telegram"
        case .github: "GitHub"
        case .google: "Google"
        case .microsoft: "Microsoft"
        case .x: "X"
        case .steam: "Steam"
        case .openai: "OpenAI"
        case .anthropic: "Claude"
        case .gemini: "Gemini"
        case .copilot: "GitHub Copilot"
        case .perplexity: "Perplexity"
        case .xai: "Grok"
        case .netflix: "Netflix"
        case .youtube: "YouTube"
        case .disney: "Disney+"
        case .spotify: "Spotify"
        case .tiktok: "TikTok"
        case .twitch: "Twitch"
        case .hbo: "HBO Max"
        case .primeVideo: "Prime Video"
        case .hulu: "Hulu"
        case .appleTV: "Apple TV+"
        case .bahamut: "Bahamut"
        case .abema: "ABEMA"
        case .dazn: "DAZN"
        case .bbc: "BBC"
        case .tvb: "TVB"
        case .niconico: "niconico"
        case .facebook: "Facebook"
        case .instagram: "Instagram"
        case .whatsapp: "WhatsApp"
        case .discord: "Discord"
        case .line: "LINE"
        case .reddit: "Reddit"
        case .signal: "Signal"
        case .linkedin: "LinkedIn"
        case .pinterest: "Pinterest"
        case .gitlab: "GitLab"
        case .docker: "Docker"
        case .npm: "npm"
        case .python: "Python"
        case .huggingface: "Hugging Face"
        case .jetbrains: "JetBrains"
        case .vercel: "Vercel"
        case .stackOverflow: "Stack Overflow"
        case .icloud: "iCloud"
        case .onedrive: "OneDrive"
        case .amazon: "Amazon"
        case .cloudflare: "Cloudflare"
        case .dropbox: "Dropbox"
        case .notion: "Notion"
        case .zoom: "Zoom"
        case .slack: "Slack"
        case .wikipedia: "Wikipedia"
        case .pixiv: "pixiv"
        case .epicGames: "Epic Games"
        case .playStation: "PlayStation"
        case .xbox: "Xbox"
        case .nintendo: "Nintendo"
        case .blizzard: "Blizzard"
        case .ea: "EA"
        case .ubisoft: "Ubisoft"
        case .riot: "Riot Games"
        case .paypal: "PayPal"
        case .binance: "Binance"
        default: nil
        }
    }

    /// Other names a search finds it by, such as the Chinese name of an English brand.
    var aliases: [String] {
        switch self {
        case .ads: ["广告", "廣告", "tracking", "跟踪"]
        case .lan: ["局域网", "區域網路", "private", "内网"]
        case .ai: ["人工智能", "chatgpt", "claude"]
        case .streaming: ["流媒体", "串流", "视频", "影音"]
        case .telegram: ["电报", "電報", "tg"]
        case .apple: ["苹果", "蘋果", "app store"]
        case .google: ["谷歌", "gmail"]
        case .microsoft: ["微软", "微軟", "office", "outlook", "teams"]
        case .x: ["twitter", "推特"]
        case .steam: ["蒸汽"]
        case .games: ["游戏", "遊戲", "games"]
        case .bilibili: ["哔哩哔哩", "b站"]
        case .foreign: ["国外", "海外", "境外"]
        case .china: ["国内", "國內", "大陆", "直连"]
        case .openai: ["chatgpt", "gpt", "sora"]
        case .anthropic: ["anthropic"]
        case .gemini: ["bard", "google ai"]
        case .xai: ["xai"]
        case .netflix: ["奈飞", "网飞", "網飛"]
        case .youtube: ["油管"]
        case .disney: ["迪士尼"]
        case .tiktok: ["抖音"]
        case .hbo: ["hbo"]
        case .primeVideo: ["亚马逊视频"]
        case .appleTV: ["apple tv"]
        case .bahamut: ["巴哈姆特", "动画疯", "動畫瘋"]
        case .bbc: ["iplayer"]
        case .tvb: ["无线电视", "無綫電視"]
        case .facebook: ["脸书", "臉書", "meta"]
        case .whatsapp: ["whats app"]
        case .line: ["連我"]
        case .linkedin: ["领英"]
        case .docker: ["docker hub"]
        case .python: ["pypi", "pip"]
        case .stackOverflow: ["stackexchange"]
        case .devTools: ["开发", "開發", "developer"]
        case .icloud: ["苹果云"]
        case .amazon: ["亚马逊", "亞馬遜", "aws"]
        case .wikipedia: ["维基", "維基", "wikimedia"]
        case .scholar: ["学术", "學術", "论文", "scholar"]
        case .epicGames: ["epic"]
        case .playStation: ["psn", "索尼"]
        case .xbox: ["xbox live"]
        case .nintendo: ["任天堂", "switch"]
        case .blizzard: ["暴雪", "battle.net"]
        case .riot: ["拳头", "英雄联盟", "valorant"]
        case .tencent: ["腾讯", "騰訊", "qq", "微信", "wechat"]
        case .alibaba: ["阿里", "淘宝", "支付宝", "taobao", "alipay"]
        case .bytedance: ["字节", "字節", "抖音", "douyin"]
        case .baidu: ["百度"]
        case .netease: ["网易", "網易", "163"]
        case .jd: ["京东", "京東"]
        case .xiaohongshu: ["小红书", "小紅書", "rednote"]
        case .zhihu: ["知乎"]
        case .chinaBanks: ["银行", "銀行", "bank"]
        case .paypal: ["贝宝"]
        case .crypto: ["加密货币", "加密貨幣", "币圈", "bitcoin"]
        case .binance: ["币安", "幣安"]
        default: []
        }
    }
}

extension ProxyRuleSet {
    /// Downloaded from a link of the user's own rather than the catalog.
    var isLinked: Bool {
        if case .url = location { return true }
        return false
    }

    /// `geosite:netflix` for a catalog set, else the file name its link ends in.
    var catalogName: String {
        switch location {
        case .catalog(let path):
            let parts = path.split(separator: "/")
            let name = parts.last.map { String($0.dropLast(".mrs".count)) } ?? path
            return (parts.first.map(String.init) ?? "") + ":" + name
        case .url(let url):
            return URLComponents(string: url)?.path.split(separator: "/").last.map(String.init) ?? url
        }
    }
}
