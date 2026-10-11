import Foundation

extension MCPOAuth.Failure: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .invalidMetadata: return String(localized: "The server's OAuth metadata is invalid.")
        case .unsupportedPKCE: return String(localized: "The authorization server must advertise PKCE S256 support.")
        case .clientRequired:
            return String(localized: "Enter a registered client ID. This server cannot register Tinycast automatically.")
        case .issuerChanged:
            return String(localized: "The authorization server changed. Enter client credentials for the new server.")
        case .invalidCallback: return String(localized: "The sign-in response could not be verified.")
        case .denied: return String(localized: "Sign-in was declined.")
        case .invalidToken: return String(localized: "The authorization server did not return a usable bearer token.")
        case .signInRequired: return String(localized: "Sign-in required. Open this MCP server in Settings to sign in.")
        case .network: return String(localized: "The OAuth request failed. Check the connection and try again.")
        case .registration:
            return String(localized: "Client registration failed. Enter a registered client ID and try again.")
        case .listenerUnavailable:
            return String(localized: "Sign-in could not open loopback port 4962. Close the app using it and retry.")
        case .signInInProgress: return String(localized: "Another sign-in is still waiting. Finish it first.")
        case .timedOut: return String(localized: "Sign-in timed out. Try again.")
        }
    }
}
