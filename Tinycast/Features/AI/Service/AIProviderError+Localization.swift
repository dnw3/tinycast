import Foundation

extension AIProviderError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .unavailable(let message), .responseFailed(let message): return message
        case .malformedResponse:
            return String(localized: "The provider returned malformed streaming data.")
        case .incompleteResponse:
            return String(localized: "The provider stopped before completing the response. Retry with shorter text.")
        case .responseStopped:
            return String(localized: "The provider stopped the response with an error.")
        }
    }
}
