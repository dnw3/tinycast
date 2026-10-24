import Foundation

extension ProxySource {
    /// What brings the nodes in, as the Subscriptions page tags each source.
    var kindTitle: String {
        switch kind {
        case .subscription: String(localized: "Subscription")
        case .file: String(localized: "Local File")
        }
    }

    /// Where a node came from, for a line under its name.
    var origin: String {
        String(localized: "From \(name)") + " · " + kindTitle
    }
}
