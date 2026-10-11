import Foundation

struct CaptureVideoExportOptions: Equatable, Sendable {
    enum Format: String, CaseIterable, Sendable { case mp4, gif }
    enum Quality: String, CaseIterable, Sendable { case compact, balanced, high }
    var format = Format.mp4
    var maximumDimension = 640
    var framesPerSecond = 10
    var videoMaximumDimension = 0
    var videoFramesPerSecond = 30
    var quality = Quality.balanced

    func bitRate(size: CapturePixelSize) -> Int {
        let factor: Double = switch quality {
        case .compact: 0.04
        case .balanced: 0.1
        case .high: 0.2
        }
        return min(60_000_000, max(256_000, Int(Double(size.width * size.height * videoFramesPerSecond) * factor)))
    }

    func videoSize(_ size: CapturePixelSize) throws -> CapturePixelSize {
        guard [0, 640, 1280, 1920, 2560, 3840].contains(videoMaximumDimension),
            [15, 30, 60].contains(videoFramesPerSecond) else { throw CaptureVideoError.invalidConfiguration }
        if format == .gif, ![320, 480, 640, 960].contains(maximumDimension) {
            throw CaptureVideoError.invalidConfiguration
        }
        let maximum = format == .gif ? maximumDimension : videoMaximumDimension
        let scale = maximum == 0 ? 1 : min(1, Double(maximum) / Double(max(size.width, size.height)))
        return try CapturePixelSize(width: max(2, Int(Double(size.width) * scale) / 2 * 2),
            height: max(2, Int(Double(size.height) * scale) / 2 * 2))
    }

    func gifFrames(size: CapturePixelSize, duration: Double) throws -> Int {
        guard [320, 480, 640, 960].contains(maximumDimension), [5, 10, 15].contains(framesPerSecond),
            duration.isFinite, duration > 0, duration <= 30
        else { throw Failure.limit }
        let scale = min(1, Double(maximumDimension) / Double(max(size.width, size.height)))
        let frames = Int(ceil(duration * Double(framesPerSecond)))
        guard frames <= 450, Double(size.width) * Double(size.height) * scale * scale * Double(frames) <= 64_000_000 else {
            throw Failure.limit
        }
        return frames
    }

    enum Failure: Error {
        case limit

    }
}
