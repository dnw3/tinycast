import Foundation

extension Fallback {
    /// The section header. A long query is elided in the middle, so “with…” always survives.
    static func sectionTitle(query: String, limit: Int = 72) -> String {
        guard query.count > limit else { return String(localized: "Use “\(query)” with…") }
        return String(localized: "Use “\(query.prefix(limit / 2))…\(query.suffix(limit - limit / 2 - 1))” with…")
    }
}
