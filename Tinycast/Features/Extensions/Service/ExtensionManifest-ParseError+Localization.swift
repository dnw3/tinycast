import Foundation

extension ExtensionManifest.ParseError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .unreadable(let url):
            return String(localized: "Couldn't read \(url.lastPathComponent).")
        case .notAnExtension(let url):
            return String(localized: "\(url.lastPathComponent) doesn't contain a Raycast extension manifest.")
        }
    }
}
