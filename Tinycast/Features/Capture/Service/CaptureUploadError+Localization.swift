import Foundation

extension CaptureUploadError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .configuration: String(localized: "Check the destination settings. Google Drive needs a Desktop OAuth client ID.")
        case .credential: String(localized: "Add an upload credential in Capture settings.")
        case .unsupported: String(localized: "This destination does not accept the file type or size. imgbb accepts images up to 32 MB.")
        case .response: String(localized: "The upload destination returned an invalid response. The local file is safe.")
        case .responseLimit: String(localized: "The upload response exceeded its size limit. The local file is safe.")
        case .authorization: String(localized: "Google Drive sign-in did not finish. Reconnect in Capture settings and retry.")
        case .http(let status): String(localized: "Upload failed (HTTP \(status)). Check the destination and its credentials.")
        }
    }
}
