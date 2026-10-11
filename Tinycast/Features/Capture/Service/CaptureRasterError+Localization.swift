import Foundation

extension CaptureRasterError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .invalidSize: String(localized: "The image exceeds the capture size limit.")
        case .invalidRow: String(localized: "The image row is outside the captured content.")
        case .invalidTile: String(localized: "The captured image is incomplete or damaged.")
        case .compressionFailed: String(localized: "The image could not be encoded.")
        }
    }
}
