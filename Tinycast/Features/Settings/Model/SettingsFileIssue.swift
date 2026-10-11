import Foundation

/// Something in settings.json Tinycast could not use, said the way the HUD says it.
enum SettingsFileIssue: Error, Equatable, Sendable {
    /// `JSONSerialization`'s own account, which names the line and column.
    case invalidJSON(String)
    /// The path whose value had to be an object; nil is the file itself.
    case notAnObject(String?)
    case unknownSetting(String)
    case invalidValue(SettingsFileKey)
    /// One record or entry inside a list or map, described for the person who wrote it.
    case invalidEntry(SettingsFileKey, String)
    case unreadable
    case unwritable

}
