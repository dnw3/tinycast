import CoreMedia
import CoreVideo
import ScreenCaptureKit
import Synchronization

/// The region as the display redraws it, so a fast scroll is never between two captures.
@MainActor
final class ScrollFrameStream {
    nonisolated struct Frame: Sendable {
        let image: CGImage
        /// The pointer in global display points as the frame arrived, and the scroll travel by then.
        let pointer: CGPoint?
        let travel: Double?
        let arrived: ContinuousClock.Instant
    }

    /// Frames waiting to be taken; past this the oldest go, which matching would not reach back to.
    nonisolated static let limit = 16

    private let output = Output()
    private var stream: SCStream?
    var running: Bool { stream != nil }
    /// Why the stream stopped on its own, as ScreenCaptureKit put it.
    var failure: String? { output.failure.withLock { $0 } }

    func start(filter: SCContentFilter, region: CGRect, size: CapturePixelSize) async throws {
        guard stream == nil else { return }
        let configuration = SCStreamConfiguration()
        configuration.sourceRect = region
        configuration.width = size.width
        configuration.height = size.height
        configuration.scalesToFit = false
        // A ProMotion display redraws up to 120 times a second while scrolling; others cap it lower.
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: 120)
        configuration.queueDepth = 5
        configuration.pixelFormat = kCVPixelFormatType_32BGRA
        configuration.colorSpaceName = CGColorSpace.sRGB
        configuration.captureDynamicRange = .SDR
        configuration.showsCursor = false
        output.reset(size: size)
        let stream = SCStream(filter: filter, configuration: configuration, delegate: output)
        try stream.addStreamOutput(output, type: .screen, sampleHandlerQueue: Output.queue)
        try await stream.startCapture()
        self.stream = stream
    }

    /// Every frame since the last take, oldest first.
    func take() -> [Frame] {
        output.frames.withLock { frames in
            defer { frames.removeAll() }
            return frames
        }
    }

    /// Scroll travel stamped on frames from now on; nil for good once a wheel's notches end it.
    func travel(_ change: (Double?) -> Double?) {
        output.travel.withLock { $0 = change($0) }
    }

    func stop() {
        output.frames.withLock { $0.removeAll() }
        guard let stream else { return }
        self.stream = nil
        Task { try? await stream.stopCapture() }
    }

    nonisolated private final class Output: NSObject, SCStreamOutput, SCStreamDelegate, Sendable {
        static let queue = DispatchQueue(label: "Tinycast.ScrollFrameStream", qos: .userInteractive)
        let frames = Mutex<[Frame]>([])
        let travel = Mutex<Double?>(0)
        let failure = Mutex<String?>(nil)
        private let size = Mutex<CapturePixelSize?>(nil)

        func reset(size: CapturePixelSize) {
            self.size.withLock { $0 = size }
            failure.withLock { $0 = nil }
            frames.withLock { $0.removeAll() }
        }

        func stream(
            _ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType
        ) {
            guard type == .screen, sampleBuffer.isValid,
                let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false)
                    as? [[SCStreamFrameInfo: Any]],
                let raw = attachments.first?[.status] as? Int, SCFrameStatus(rawValue: raw) == .complete,
                let buffer = sampleBuffer.imageBuffer, let size = size.withLock({ $0 }),
                CVPixelBufferGetWidth(buffer) == size.width, CVPixelBufferGetHeight(buffer) == size.height,
                let image = Self.image(buffer)
            else { return }
            let frame = Frame(
                image: image, pointer: CGEvent(source: nil)?.location, travel: travel.withLock { $0 },
                arrived: .now)
            frames.withLock { frames in
                frames.append(frame)
                if frames.count > ScrollFrameStream.limit { frames.removeFirst(frames.count - ScrollFrameStream.limit) }
            }
        }

        func stream(_ stream: SCStream, didStopWithError error: any Error) {
            failure.withLock { $0 = error.localizedDescription }
        }

        /// A copy: ScreenCaptureKit reuses its buffers, and a frame may wait in a strip long after.
        private static func image(_ buffer: CVPixelBuffer) -> CGImage? {
            CVPixelBufferLockBaseAddress(buffer, .readOnly)
            defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
            guard let base = CVPixelBufferGetBaseAddress(buffer) else { return nil }
            let rowBytes = CVPixelBufferGetBytesPerRow(buffer), height = CVPixelBufferGetHeight(buffer)
            guard let provider = CGDataProvider(data: Data(bytes: base, count: rowBytes * height) as CFData)
            else { return nil }
            return CGImage(
                width: CVPixelBufferGetWidth(buffer), height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                bytesPerRow: rowBytes, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGBitmapInfo(
                    rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue),
                provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
        }
    }
}
