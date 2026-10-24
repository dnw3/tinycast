import Foundation

extension ProxyRegion {
    /// The system's own name for the region, in the language the app is shown in.
    var title: String {
        switch self {
        case .hongKong: String(localized: "Hong Kong")
        case .macau: String(localized: "Macau")
        case .mainlandChina: String(localized: "Mainland China")
        default: Self.locale.localizedString(forRegionCode: regionCode) ?? regionCode
        }
    }

    /// The flag and name together, for a header or a chip.
    var label: String { flag.map { "\($0) \(title)" } ?? title }

    /// The section a node that names no region falls into.
    static var otherTitle: String { String(localized: "Other Regions") }

    /// Not `Locale.current`, whose language can be one the app has no translation for.
    private static let locale = Locale(identifier: Bundle.main.preferredLocalizations.first ?? "en")
}
