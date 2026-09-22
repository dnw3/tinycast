import Foundation

enum TranslationTargetPolicy {
    static func selection(in value: String, range: NSRange) -> String? {
        guard range.length > 0, let selection = Range(range, in: value) else { return nil }
        return String(value[selection])
    }

    static func matches(
        original: String, range: NSRange, current: String, currentRange: NSRange
    ) -> Bool {
        original == current && range == currentRange && Range(range, in: original) != nil
    }
}
