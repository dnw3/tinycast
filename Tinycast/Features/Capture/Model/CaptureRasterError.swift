import Foundation

enum CaptureRasterError: Error {
    case invalidSize
    case invalidRow
    case invalidTile
    case compressionFailed

}
