import Foundation

extension ProxyMode {
    var title: String {
        switch self {
        case .rule: String(localized: "Rule")
        case .global: String(localized: "Global")
        case .direct: String(localized: "Direct")
        }
    }

    /// The glyph its launcher command carries too.
    var symbol: String {
        switch self {
        case .rule: "arrow.triangle.branch"
        case .global: "globe"
        case .direct: "arrow.right"
        }
    }

    var explanation: String {
        switch self {
        case .rule: String(localized: "Traffic follows your rules and routes.")
        case .global: String(localized: "Everything goes through the default strategy.")
        case .direct: String(localized: "Everything goes direct, while TUN and DNS stay in place.")
        }
    }
}

extension ProxyManager {
    var statusTitle: String {
        switch status {
        case .off: String(localized: "Disconnected")
        case .starting: String(localized: "Connecting…")
        case .running: String(localized: "Connected")
        case .failed: String(localized: "Not Connected")
        }
    }
}
