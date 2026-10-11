import Foundation

extension AIEndpointPolicy.ValidationError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .invalidURL: return String(localized: "Enter a valid provider base URL.")
        case .insecureRemoteURL: return String(localized: "Remote AI providers require an HTTPS base URL.")
        }
    }
}
