import Foundation

/// One case per cause: a single "nothing selected" tells a reader to select what they selected.
enum QuickActionFailure: Error, Equatable {
    case needsAccessibility
    case noTarget
    /// The app answered but exposes no focused text element — Chromium before its tree is built.
    case unreadableApp(String)
    case noSelection
    case tooLong


    /// The only failure with somewhere to send the reader, and so the only one worth a dialog.
    var opensAccessibilitySettings: Bool { self == .needsAccessibility }
}
