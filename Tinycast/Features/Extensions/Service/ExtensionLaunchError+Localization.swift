import Foundation

extension ExtensionLaunchError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .unknownCommand(let id): return String(localized: "No installed extension provides '\(id)'.")
        case .unsupported(let reason): return reason
        case .notBuilt(let name):
            return String(localized: "\(name) has no built bundle — reinstall the extension.")
        case .missingPreferences(let schemas):
            let names = schemas.map(\.displayTitle).joined(separator: ", ")
            return String(localized: "This command needs its preferences set first: \(names).")
        }
    }
}
