import Foundation

extension WindowLayoutPlan {
    func skippedSummary(in bundle: Bundle = .main, locale: Locale = .current) -> String? {
        guard !skipped.isEmpty else { return nil }
        let displays = Set(
            skipped.compactMap { skip -> String? in
                guard case .displayDisconnected(let name) = skip.reason else { return nil }
                return name
            })
        if !displays.isEmpty, displays.count == skipped.count {
            return String(localized: "\(displays.count) displays not connected", bundle: bundle, locale: locale)
        }
        return String(localized: "\(skipped.count) entries skipped", bundle: bundle, locale: locale)
    }
}
