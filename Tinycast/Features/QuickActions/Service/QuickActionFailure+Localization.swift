import Foundation

extension QuickActionFailure: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .needsAccessibility:
            return String(localized: "Tinycast needs the Accessibility permission to read the selected text.")
        case .noTarget:
            return String(localized: "Select text in another app first.")
        case .unreadableApp(let name):
            return String(localized: "\(name) doesn't share its text with Tinycast.")
        case .noSelection:
            return String(localized: "Select some text first.")
        case .tooLong:
            return String(localized: "That selection is too long to work on.")
        }
    }
}
