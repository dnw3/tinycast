import Foundation

enum ProxyPrompt {
    /// Marks a placeholder as an example, so it does not read as a value already filled in.
    static func example(_ value: String) -> String {
        String(localized: "e.g. \(value)")
    }
}
