import Foundation

enum CaptureVideoError: Error, LocalizedError {
    case invalidConfiguration, invalidMedia

    var errorDescription: String? {
        switch self {
        case .invalidConfiguration: "Choose a valid recording size and time range."
        case .invalidMedia: "The video is incomplete or could not be read. Your source recording is still available."
        }
    }
}
