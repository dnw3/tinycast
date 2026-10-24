import Foundation

/// The regions a node name is recognised by, listed by area; a node naming none is "other".
enum ProxyRegion: String, CaseIterable, Codable, Sendable {
    case hongKong = "hk"
    case taiwan = "tw"
    case macau = "mo"
    case japan = "jp"
    case korea = "kr"
    case singapore = "sg"
    case malaysia = "my"
    case thailand = "th"
    case vietnam = "vn"
    case philippines = "ph"
    case indonesia = "id"
    case cambodia = "kh"
    case myanmar = "mm"
    case india = "in"
    case pakistan = "pk"
    case bangladesh = "bd"
    case nepal = "np"
    case sriLanka = "lk"
    case mongolia = "mn"
    case kazakhstan = "kz"
    case uzbekistan = "uz"
    case australia = "au"
    case newZealand = "nz"
    case unitedStates = "us"
    case canada = "ca"
    case mexico = "mx"
    case brazil = "br"
    case argentina = "ar"
    case chile = "cl"
    case colombia = "co"
    case peru = "pe"
    case unitedKingdom = "uk"
    case ireland = "ie"
    case germany = "de"
    case france = "fr"
    case netherlands = "nl"
    case belgium = "be"
    case luxembourg = "lu"
    case switzerland = "ch"
    case austria = "at"
    case italy = "it"
    case spain = "es"
    case portugal = "pt"
    case sweden = "se"
    case norway = "no"
    case finland = "fi"
    case denmark = "dk"
    case iceland = "is"
    case estonia = "ee"
    case latvia = "lv"
    case lithuania = "lt"
    case poland = "pl"
    case czechia = "cz"
    case slovakia = "sk"
    case hungary = "hu"
    case slovenia = "si"
    case croatia = "hr"
    case serbia = "rs"
    case romania = "ro"
    case bulgaria = "bg"
    case greece = "gr"
    case cyprus = "cy"
    case moldova = "md"
    case ukraine = "ua"
    case russia = "ru"
    case turkey = "tr"
    case georgia = "ge"
    case armenia = "am"
    case azerbaijan = "az"
    case israel = "il"
    case unitedArabEmirates = "ae"
    case saudiArabia = "sa"
    case qatar = "qa"
    case egypt = "eg"
    case morocco = "ma"
    case southAfrica = "za"
    case nigeria = "ng"
    case kenya = "ke"
    /// Only a node that says it exits in the mainland, never a mainland city that relays elsewhere.
    case mainlandChina = "cn"

    /// Names the region in every language and spells its flag; `uk` predates ISO codes.
    var regionCode: String {
        self == .unitedKingdom ? "GB" : rawValue.uppercased()
    }

    /// For plain text; nil where a China-region Mac draws the flag as a missing glyph.
    var flag: String? {
        self == .taiwan ? nil : flagEmoji
    }

    /// The regional indicators, which a view draws itself where the font will not.
    var flagEmoji: String {
        let indicators = regionCode.unicodeScalars.compactMap { Unicode.Scalar(0x1F1A5 + $0.value) }
        return String(String.UnicodeScalarView(indicators))
    }

    private var words: [String] {
        switch self {
        case .hongKong: ["香港", "深港", "沪港", "广港", "京港", "Hong ?Kong"]
        case .taiwan: ["台湾", "臺灣", "台灣", "台北", "臺北", "新北", "彰化", "高雄", "Taiwan", "Taipei", "Kaohsiung"]
        case .macau: ["澳门", "澳門", "Maca[ou]"]
        case .japan:
            [
                "日本", "东京", "東京", "大阪", "埼玉", "名古屋", "福冈", "福岡", "Japan", "Tokyo", "Osaka", "Nagoya",
                "Fukuoka"
            ]
        case .korea: ["韩国", "韓國", "首尔", "首爾", "春川", "釜山", "Korea", "Seoul", "Busan"]
        case .singapore: ["新加坡", "狮城", "獅城", "Singapore"]
        case .malaysia: ["马来西亚", "馬來西亞", "吉隆坡", "Malaysia", "Kuala ?Lumpur"]
        case .thailand: ["泰国", "泰國", "曼谷", "Thailand", "Bangkok"]
        case .vietnam: ["越南", "河内", "河內", "胡志明", "Viet ?Nam", "Hanoi", "Ho ?Chi ?Minh"]
        case .philippines: ["菲律宾", "菲律賓", "马尼拉", "馬尼拉", "Philippines", "Manila"]
        case .indonesia: ["印尼", "印度尼西亚", "印度尼西亞", "雅加达", "雅加達", "Indonesia", "Jakarta"]
        case .cambodia: ["柬埔寨", "金边", "金邊", "Cambodia", "Phnom ?Penh"]
        case .myanmar: ["缅甸", "緬甸", "仰光", "Myanmar", "Burma", "Yangon"]
        // Not followed by 尼 or "na", which would be Indonesia or Indiana.
        case .india:
            ["印度(?!尼)", "孟买", "孟買", "新德里", "班加罗尔", "班加羅爾", "India(?!na)", "Mumbai", "Delhi", "Bangalore"]
        case .pakistan: ["巴基斯坦", "卡拉奇", "Pakistan", "Karachi"]
        case .bangladesh: ["孟加拉", "达卡", "達卡", "Bangladesh", "Dhaka"]
        case .nepal: ["尼泊尔", "尼泊爾", "加德满都", "Nepal", "Kathmandu"]
        case .sriLanka: ["斯里兰卡", "斯里蘭卡", "科伦坡", "Sri ?Lanka", "Colombo"]
        // Not Inner Mongolia, a mainland province.
        case .mongolia: ["(?<!内)(?<!內)蒙古", "乌兰巴托", "烏蘭巴托", "Mongolia", "Ulaanbaatar"]
        case .kazakhstan: ["哈萨克", "哈薩克", "阿拉木图", "阿斯塔纳", "Kazakhstan", "Almaty", "Astana"]
        case .uzbekistan: ["乌兹别克", "烏茲別克", "塔什干", "Uzbekistan", "Tashkent"]
        case .australia:
            [
                "澳大利亚", "澳大利亞", "澳洲", "悉尼", "雪梨", "墨尔本", "墨爾本", "布里斯班", "珀斯", "Australia",
                "Sydney", "Melbourne", "Brisbane", "Perth"
            ]
        case .newZealand: ["新西兰", "新西蘭", "纽西兰", "紐西蘭", "New ?Zealand", "Auckland"]
        case .unitedStates:
            [
                "美国", "美國", "洛杉矶", "洛杉磯", "圣何塞", "聖何塞", "硅谷", "矽谷", "西雅图", "西雅圖", "芝加哥",
                "达拉斯", "達拉斯", "纽约", "紐約", "凤凰城", "鳳凰城", "旧金山", "舊金山", "圣克拉拉", "聖克拉拉",
                "弗里蒙特", "波特兰", "波特蘭", "亚特兰大", "亞特蘭大", "迈阿密", "邁阿密", "华盛顿", "華盛頓", "阿什本",
                "拉斯维加斯", "拉斯維加斯", "丹佛", "United ?States", "America", "Los Angeles", "San Jose",
                "Silicon Valley", "Seattle", "Chicago", "Dallas", "New York", "Phoenix", "San Francisco",
                "Santa Clara", "Fremont", "Portland", "Atlanta", "Miami", "Washington", "Ashburn", "Las Vegas",
                "Denver", "Virginia", "Oregon"
            ]
        case .canada:
            [
                "加拿大", "多伦多", "多倫多", "温哥华", "溫哥華", "蒙特利尔", "蒙特婁", "Canada", "Toronto",
                "Vancouver", "Montreal"
            ]
        // Not New Mexico, a state.
        case .mexico: ["墨西哥", "(?<!New )Mexico"]
        case .brazil: ["巴西", "圣保罗", "聖保羅", "Brazil", "Brasil", "S[aã]o ?Paulo"]
        case .argentina: ["阿根廷", "布宜诺斯艾利斯", "Argentina", "Buenos ?Aires"]
        case .chile: ["智利", "Chile", "Santiago"]
        case .colombia: ["哥伦比亚", "哥倫比亞", "波哥大", "Colombia", "Bogot[aá]"]
        case .peru: ["秘鲁", "秘魯", "利马", "利馬", "Peru"]
        case .unitedKingdom:
            [
                "英国", "英國", "伦敦", "倫敦", "曼彻斯特", "曼徹斯特", "United ?Kingdom", "Britain", "England",
                "London", "Manchester"
            ]
        case .ireland: ["爱尔兰", "愛爾蘭", "都柏林", "Ireland", "Dublin"]
        // Not 都柏林, Dublin.
        case .germany:
            [
                "德国", "德國", "法兰克福", "法蘭克福", "(?<!都)柏林", "慕尼黑", "杜塞尔多夫", "杜塞爾多夫", "纽伦堡",
                "紐倫堡", "Germany", "Frankfurt", "Berlin", "Munich", "D[uü]sseldorf", "Nuremberg"
            ]
        case .france: ["法国", "法國", "巴黎", "马赛", "馬賽", "France", "Paris", "Marseille"]
        case .netherlands: ["荷兰", "荷蘭", "阿姆斯特丹", "Netherlands", "Holland", "Amsterdam"]
        case .belgium: ["比利时", "比利時", "布鲁塞尔", "布魯塞爾", "Belgium", "Brussels"]
        case .luxembourg: ["卢森堡", "盧森堡", "Luxembourg"]
        case .switzerland:
            ["瑞士", "苏黎世", "蘇黎世", "日内瓦", "日內瓦", "Switzerland", "Swiss", "Z[uü]rich", "Geneva"]
        case .austria: ["奥地利", "奧地利", "维也纳", "維也納", "Austria", "Vienna"]
        // Not followed by 尼, which would be Romania.
        case .italy: ["意大利", "義大利", "米兰", "米蘭", "罗马(?!尼)", "羅馬(?!尼)", "Italy", "Milan"]
        case .spain: ["西班牙", "马德里", "馬德里", "巴塞罗那", "巴塞隆納", "Spain", "Madrid", "Barcelona"]
        case .portugal: ["葡萄牙", "里斯本", "Portugal", "Lisbon"]
        case .sweden: ["瑞典", "斯德哥尔摩", "斯德哥爾摩", "Sweden", "Stockholm"]
        case .norway: ["挪威", "奥斯陆", "奧斯陸", "Norway", "Oslo"]
        case .finland: ["芬兰", "芬蘭", "赫尔辛基", "赫爾辛基", "Finland", "Helsinki"]
        case .denmark: ["丹麦", "丹麥", "哥本哈根", "Denmark", "Copenhagen"]
        case .iceland: ["冰岛", "冰島", "雷克雅未克", "Iceland", "Reykjavik"]
        case .estonia: ["爱沙尼亚", "愛沙尼亞", "塔林", "Estonia", "Tallinn"]
        case .latvia: ["拉脱维亚", "拉脫維亞", "Latvia"]
        case .lithuania: ["立陶宛", "维尔纽斯", "維爾紐斯", "Lithuania", "Vilnius"]
        case .poland: ["波兰", "波蘭", "华沙", "華沙", "Poland", "Warsaw"]
        case .czechia: ["捷克", "布拉格", "Czech", "Prague"]
        case .slovakia: ["斯洛伐克", "布拉迪斯拉发", "Slovakia", "Bratislava"]
        case .hungary: ["匈牙利", "布达佩斯", "布達佩斯", "Hungary", "Budapest"]
        case .slovenia: ["斯洛文尼亚", "斯洛文尼亞", "卢布尔雅那", "Slovenia", "Ljubljana"]
        case .croatia: ["克罗地亚", "克羅地亞", "克羅埃西亞", "萨格勒布", "Croatia", "Zagreb"]
        case .serbia: ["塞尔维亚", "塞爾維亞", "贝尔格莱德", "Serbia", "Belgrade"]
        case .romania: ["罗马尼亚", "羅馬尼亞", "布加勒斯特", "Romania", "Bucharest"]
        case .bulgaria: ["保加利亚", "保加利亞", "Bulgaria"]
        case .greece: ["希腊", "希臘", "雅典", "Greece", "Athens"]
        case .cyprus: ["塞浦路斯", "賽普勒斯", "Cyprus"]
        case .moldova: ["摩尔多瓦", "摩爾多瓦", "基希讷乌", "Moldova", "Chisinau"]
        case .ukraine: ["乌克兰", "烏克蘭", "基辅", "基輔", "Ukraine", "Kyiv", "Kiev"]
        case .russia:
            [
                "俄罗斯", "俄羅斯", "莫斯科", "圣彼得堡", "聖彼得堡", "新西伯利亚", "新西伯利亞", "海参崴", "Russia",
                "Moscow", "Petersburg", "Novosibirsk", "Vladivostok"
            ]
        case .turkey: ["土耳其", "伊斯坦布尔", "伊斯坦堡", "Turkey", "Türkiye", "Istanbul"]
        // Only the country's names: Georgia is also a state.
        case .georgia: ["格鲁吉亚", "格魯吉亞", "第比利斯", "Tbilisi"]
        case .armenia: ["亚美尼亚", "亞美尼亞", "埃里温", "Armenia", "Yerevan"]
        case .azerbaijan: ["阿塞拜疆", "亞塞拜然", "巴库", "巴庫", "Azerbaijan", "Baku"]
        case .israel: ["以色列", "特拉维夫", "特拉維夫", "Israel", "Tel ?Aviv"]
        case .unitedArabEmirates:
            ["阿联酋", "阿聯酋", "迪拜", "杜拜", "阿布扎比", "United ?Arab", "Emirates", "Dubai", "Abu ?Dhabi"]
        case .saudiArabia: ["沙特", "沙烏地", "利雅得", "Saudi", "Riyadh"]
        case .qatar: ["卡塔尔", "卡塔爾", "卡達", "多哈", "Qatar", "Doha"]
        case .egypt: ["埃及", "开罗", "開羅", "Egypt", "Cairo"]
        case .morocco: ["摩洛哥", "卡萨布兰卡", "Morocco", "Casablanca"]
        case .southAfrica:
            ["南非", "约翰内斯堡", "約翰尼斯堡", "开普敦", "開普敦", "South ?Africa", "Johannesburg", "Cape ?Town"]
        case .nigeria: ["尼日利亚", "尼日利亞", "奈及利亞", "拉各斯", "Nigeria", "Lagos"]
        case .kenya: ["肯尼亚", "肯尼亞", "肯亞", "内罗毕", "奈洛比", "Kenya", "Nairobi"]
        case .mainlandChina: ["回国", "回國", "中国大陆", "中國大陸"]
        }
    }

    /// Uppercase only, without codes that are words or units (IN, IT, TH, GB, CA) or CN2's CN.
    private var codes: [String] {
        switch self {
        case .hongKong: ["HK", "HKG"]
        case .taiwan: ["TW", "TWN", "TPE"]
        case .macau: ["MO"]
        case .japan: ["JP", "JPN", "NRT", "HND", "KIX"]
        case .korea: ["KR", "KOR", "ICN"]
        case .singapore: ["SG", "SGP", "SIN"]
        case .malaysia: ["MY", "MYS"]
        case .thailand: ["THA"]
        case .vietnam: ["VN", "VNM"]
        case .philippines: ["PH", "PHL"]
        case .indonesia: ["IDN"]
        case .cambodia: ["KH", "KHM"]
        case .myanmar: ["MMR"]
        case .india: ["IND"]
        case .pakistan: ["PK", "PAK"]
        case .bangladesh: ["BD", "BGD"]
        case .nepal: ["NPL"]
        case .sriLanka: ["LKA"]
        case .mongolia: ["MN", "MNG"]
        case .kazakhstan: ["KZ", "KAZ"]
        case .uzbekistan: ["UZB"]
        case .australia: ["AU", "AUS", "SYD"]
        case .newZealand: ["NZ", "NZL"]
        case .unitedStates: ["US", "USA", "LAX", "SJC", "SFO", "JFK", "ORD", "DFW"]
        case .canada: ["CAN", "YYZ", "YVR"]
        case .mexico: ["MX", "MEX"]
        case .brazil: ["BR", "BRA"]
        case .argentina: ["AR", "ARG"]
        case .chile: ["CL", "CHL"]
        case .colombia: ["COL"]
        case .unitedKingdom: ["UK", "GBR", "LHR"]
        case .ireland: ["IE", "IRL"]
        case .germany: ["DE", "DEU"]
        case .france: ["FR", "FRA", "CDG"]
        case .netherlands: ["NL", "NLD", "AMS"]
        case .belgium: ["BEL"]
        case .luxembourg: ["LU", "LUX"]
        case .switzerland: ["CH", "CHE"]
        case .austria: ["AUT"]
        case .italy: ["ITA"]
        case .spain: ["ESP"]
        case .portugal: ["PRT"]
        case .sweden: ["SE", "SWE"]
        case .norway: ["NOR"]
        case .finland: ["FI", "FIN"]
        case .denmark: ["DK", "DNK"]
        case .iceland: ["ISL"]
        case .estonia: ["EE"]
        case .latvia: ["LV", "LVA"]
        case .lithuania: ["LT", "LTU"]
        case .poland: ["PL", "POL"]
        case .czechia: ["CZ", "CZE"]
        case .slovakia: ["SK", "SVK"]
        case .hungary: ["HU", "HUN"]
        case .slovenia: ["SVN"]
        case .croatia: ["HRV"]
        case .serbia: ["RS", "SRB"]
        case .romania: ["RO", "ROU"]
        case .bulgaria: ["BG", "BGR"]
        case .greece: ["GR", "GRC"]
        case .cyprus: ["CY", "CYP"]
        case .moldova: ["MDA"]
        case .ukraine: ["UA", "UKR"]
        case .russia: ["RU", "RUS"]
        case .turkey: ["TR", "TUR"]
        case .georgia: ["GEO"]
        case .azerbaijan: ["AZE"]
        case .israel: ["IL", "ISR"]
        case .unitedArabEmirates: ["AE", "UAE"]
        case .saudiArabia: ["SAU"]
        case .qatar: ["QAT"]
        case .egypt: ["EG", "EGY"]
        case .southAfrica: ["ZA", "ZAF"]
        case .nigeria: ["NG", "NGA"]
        case .kenya: ["KE"]
        case .peru, .armenia, .morocco, .mainlandChina: []
        }
    }

    /// Some subscriptions flag Taiwan's nodes 🇨🇳, so that flag alone never means the mainland.
    private var namedByFlag: Bool { self != .mainlandChina }

    /// One pattern both ICU and Go's regexp2 accept, so the node list and mihomo's `filter` agree.
    var filter: String {
        let names = (namedByFlag ? [flagEmoji] : []) + words
        let name = "(?i:" + names.joined(separator: "|") + ")"
        guard !codes.isEmpty else { return name }
        return name + "|(?<![A-Za-z])(?:" + codes.joined(separator: "|") + ")(?![A-Za-z])"
    }

    /// The region named earliest, so "🇺🇸 美国 | 香港中转" is the United States rather than Hong Kong.
    static func classify(_ name: String) -> ProxyRegion? {
        let range = NSRange(name.startIndex..., in: name)
        var best: (region: ProxyRegion, location: Int)?
        for (region, expression) in expressions {
            guard let match = expression.firstMatch(in: name, range: range) else { continue }
            if match.range.location < best?.location ?? .max {
                best = (region, match.range.location)
            }
        }
        return best?.region
    }

    /// The flag a name opens with, as providers often write one, and the name after it.
    static func leadingFlag(of name: String) -> (flag: String, rest: String)? {
        guard let first = name.first, first.unicodeScalars.count == 2,
            first.unicodeScalars.allSatisfy({ (0x1F1E6...0x1F1FF).contains($0.value) })
        else { return nil }
        let rest = String(name.dropFirst().drop(while: \.isWhitespace))
        return rest.isEmpty ? nil : (String(first), rest)
    }

    /// In declaration order, which breaks a tie between two regions named at the same position.
    private static let expressions: [(ProxyRegion, NSRegularExpression)] = allCases.compactMap { region in
        (try? NSRegularExpression(pattern: region.filter)).map { (region, $0) }
    }
}
