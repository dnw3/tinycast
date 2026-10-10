import Foundation

enum CaptureRasterError: Error, LocalizedError {
    case invalidSize
    case invalidRow
    case invalidTile
    case compressionFailed

    var errorDescription: String? {
        switch self {
        case .invalidSize: "The image exceeds the capture size limit."
        case .invalidRow: "The image row is outside the captured content."
        case .invalidTile: "The captured image is incomplete or damaged."
        case .compressionFailed: "The image could not be encoded."
        }
    }
}
