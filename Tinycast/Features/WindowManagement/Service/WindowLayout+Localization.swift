import Foundation

extension WindowLayout {
    func summary(in bundle: Bundle = .main, locale: Locale = .current) -> String {
        let displays = Set(entries.map(\.display.uuid)).count
        let windows = String(localized: "\(entries.count) windows", bundle: bundle, locale: locale)
        return displays > 1 ? String(localized: "\(windows) · \(displays) displays", bundle: bundle, locale: locale) : windows
    }
}
