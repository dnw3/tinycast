import Foundation

extension CaptureVideoError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .invalidConfiguration: String(localized: "Choose a valid recording size and time range.")
        case .invalidMedia: String(localized: "The video is incomplete or could not be read. Your source recording is still available.")
        }
    }
}
