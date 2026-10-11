import Foundation

extension SettingsFileIssue {
    var message: String {
        switch self {
        case .invalidJSON(let detail): String(localized: "not valid JSON — \(detail)")
        case .notAnObject(nil): String(localized: "the file must hold one JSON object")
        case .notAnObject(let path?): String(localized: "“\(path)” must be an object")
        case .unknownSetting(let path): String(localized: "unknown setting “\(path)”")
        case .invalidValue(let key): String(localized: "“\(key.rawValue)” has a value Tinycast can't use")
        case .invalidEntry(let key, let detail): String(localized: "“\(key.rawValue)”: \(detail)")
        case .unreadable: String(localized: "couldn't be read")
        case .unwritable: String(localized: "couldn't be saved")
        }
    }

    /// The HUD's line: the first issue, and how many more there are.
    static func summary(_ issues: [SettingsFileIssue]) -> String? {
        guard let first = issues.first else { return nil }
        guard issues.count > 1 else { return "settings.json: \(first.message)" }
        return String(localized: "settings.json: \(first.message) (+\(issues.count - 1) more)")
    }
}
