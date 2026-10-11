import Foundation

extension ExtensionStoreError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .malformedResponse:
            return String(localized: "The server answered with something this version doesn't understand.")
        case .rejected(let message):
            return message
        case .downloadFailed(let reason):
            return String(localized: "Download failed: \(reason)")
        case .noPackageManager:
            return
                String(localized: "No package manager was found. Install pnpm, npm, Yarn or Bun, or add the folder it lives in to Custom search paths.")
        case .noNode:
            return
                String(localized: "Node wasn't found. Install Node.js, add the folder it lives in to Custom search paths, or install this extension from the Raycast Store instead.")
        case .buildFailed(let output):
            return String(localized: "The extension didn't build: \(output)")
        case .notAnExtension:
            return String(localized: "That download didn't contain a Raycast extension.")
        }
    }
}
