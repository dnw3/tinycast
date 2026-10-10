import AVFoundation
import ImageIO
import UniformTypeIdentifiers

enum CaptureGIFService {
    struct Info: Sendable {
        let size: CapturePixelSize
        let duration: Double
        let frames: Int
        let preview: CGImage
    }

    nonisolated static func frames(_ url: URL) -> AsyncThrowingStream<CGImage, Error> {
        AsyncThrowingStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            let worker = Task.detached(priority: .userInitiated) {
                do {
                    let info = try inspect(url)
                    guard let source = CGImageSourceCreateWithURL(url as CFURL,
                        [kCGImageSourceShouldCache: false] as CFDictionary)
                    else { throw CaptureVideoError.invalidMedia }
                    var deadline = ContinuousClock.now
                    for index in 0..<info.frames {
                        try Task.checkCancellation()
                        let image = try autoreleasepool {
                            guard let image = CGImageSourceCreateImageAtIndex(source, index,
                                [kCGImageSourceShouldCache: false] as CFDictionary)
                            else { throw CaptureVideoError.invalidMedia }
                            return image
                        }
                        if case .terminated = continuation.yield(image) { return }
                        deadline += .seconds(try delay(source, at: index))
                        try await Task.sleep(until: deadline, clock: .continuous)
                    }
                    continuation.finish()
                } catch { continuation.finish(throwing: error) }
            }
            continuation.onTermination = { _ in worker.cancel() }
        }
    }

    nonisolated static func inspect(_ url: URL) throws -> Info {
        guard let source = CGImageSourceCreateWithURL(url as CFURL,
            [kCGImageSourceShouldCache: false] as CFDictionary),
            CGImageSourceGetType(source) as String? == UTType.gif.identifier
        else { throw CaptureVideoError.invalidMedia }
        let count = CGImageSourceGetCount(source)
        guard (1...450).contains(count),
            let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any],
            let width = properties[kCGImagePropertyPixelWidth as String] as? Int,
            let height = properties[kCGImagePropertyPixelHeight as String] as? Int,
            width > 0, height > 0, width <= 960, height <= 960, width * height * count <= 64_000_000
        else { throw CaptureVideoError.invalidMedia }
        var duration = 0.0
        for index in 0..<count {
            try Task.checkCancellation()
            duration += try delay(source, at: index)
        }
        guard duration <= 30.001, let preview = CGImageSourceCreateThumbnailAtIndex(source, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: 256
        ] as CFDictionary) else { throw CaptureVideoError.invalidMedia }
        return try Info(size: CapturePixelSize(width: width, height: height),
            duration: min(duration, 30), frames: count, preview: preview)
    }

    nonisolated private static func delay(_ source: CGImageSource, at index: Int) throws -> Double {
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [String: Any],
            let gif = properties[kCGImagePropertyGIFDictionary as String] as? [String: Any],
            let delay = (gif[kCGImagePropertyGIFUnclampedDelayTime as String]
                ?? gif[kCGImagePropertyGIFDelayTime as String]) as? Double,
            delay.isFinite, delay > 0
        else { throw CaptureVideoError.invalidMedia }
        return delay
    }

    nonisolated static func render(
        _ url: URL, edit: CaptureVideoEdit, options: CaptureVideoExportOptions, to destination: URL,
        progress: @escaping @Sendable (Double) async -> Void
    ) async throws {
        let worker = Task.detached(priority: .userInitiated) {
            let info = try await CaptureVideoService.inspect(url)
            let edit = try edit.validated(duration: info.duration)
            let count = try options.gifFrames(size: info.size, duration: edit.duration)
            let prepared = try await CaptureVideoService.prepare(url, edit: edit, options: options)
            let generator = AVAssetImageGenerator(asset: prepared.asset)
            generator.videoComposition = prepared.video
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: options.maximumDimension, height: options.maximumDimension)
            generator.requestedTimeToleranceBefore = .zero
            generator.requestedTimeToleranceAfter = .zero
            guard let output = CGImageDestinationCreateWithURL(
                destination as CFURL, UTType.gif.identifier as CFString, count, nil)
            else { throw CaptureVideoError.invalidMedia }
            var complete = false
            defer { if !complete { try? FileManager.default.removeItem(at: destination) } }
            CGImageDestinationSetProperties(output,
                [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
            let interval = 1 / Double(options.framesPerSecond)
            for index in 0..<count {
                try Task.checkCancellation()
                let position = Double(index) * interval
                let time = CaptureVideoService.time(position)
                let (image, _) = try await generator.image(at: time)
                let delay = min(interval, edit.duration - position)
                let properties = [kCGImagePropertyGIFDictionary: [
                    kCGImagePropertyGIFDelayTime: delay, kCGImagePropertyGIFUnclampedDelayTime: delay
                ]] as CFDictionary
                autoreleasepool { CGImageDestinationAddImage(output, image, properties) }
                await progress(Double(index + 1) / Double(count))
            }
            try Task.checkCancellation()
            guard CGImageDestinationFinalize(output) else { throw CaptureVideoError.invalidMedia }
            complete = true
        }
        try await withTaskCancellationHandler { try await worker.value } onCancel: { worker.cancel() }
    }
}
