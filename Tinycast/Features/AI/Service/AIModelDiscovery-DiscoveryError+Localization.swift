import Foundation

extension AIModelDiscovery.DiscoveryError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .malformedResponse:
            return String(localized: "The provider returned an unreadable model list. Enter a model ID manually.")
        case .rejectedKey:
            return String(localized: "The API key was rejected. Check it and try again.")
        case .unavailable:
            return String(localized: "The provider could not load models right now. Try again or enter one manually.")
        case .unsupported:
            return String(localized: "This endpoint does not expose a model list. Enter a model ID manually.")
        }
    }
}
