import Foundation

extension CustomWindowSize {
    var summary: String {
        let base = "\(width.label) × \(height.label) · \(Bundle.main.localizedString(forKey: anchor.title, value: nil, table: nil))"
        return offset == .zero ? base : String(localized: "\(base) · Offset \(offset.x), \(offset.y) pt")
    }
}
