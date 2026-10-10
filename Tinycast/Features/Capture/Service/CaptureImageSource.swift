import Accelerate
import CoreGraphics
import Foundation
import ImageIO

enum CaptureImageSource {
    nonisolated static func store(_ image: CGImage, at directory: URL) throws -> CapturePixelSize {
        let size = try CapturePixelSize(width: image.width, height: image.height)
        let bandHeight = max(1, min(64, 1_048_576 / size.rowBytes))
        guard
            let context = CGContext(
                data: nil, width: size.width, height: bandHeight, bitsPerComponent: 8,
                bytesPerRow: size.rowBytes, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { throw CaptureRasterError.invalidSize }
        var band = -1
        try CaptureRasterStore.write(size: size, to: directory) { row, buffer in
            let next = row / bandHeight
            if band != next {
                band = next
                context.clear(CGRect(x: 0, y: 0, width: size.width, height: bandHeight))
                context.draw(
                    image,
                    in: CGRect(
                        x: 0, y: bandHeight - size.height + band * bandHeight,
                        width: size.width, height: size.height))
            }
            let offset = (row % bandHeight) * size.rowBytes
            buffer.copyMemory(
                from: UnsafeRawBufferPointer(
                    start: context.data!.advanced(by: offset), count: size.rowBytes))
            try CapturePixelAlpha.unpremultiply(buffer)
        }
        return size
    }

    nonisolated static func preview(_ image: CGImage, maximum: Int = 900) throws -> CGImage {
        let scale = min(1, Double(maximum) / Double(max(image.width, image.height)))
        let width = max(1, Int(Double(image.width) * scale)), height = max(1, Int(Double(image.height) * scale))
        guard let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { throw CaptureRasterError.invalidSize }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let result = context.makeImage() else { throw CaptureRasterError.invalidSize }
        return result
    }

    nonisolated static func load(_ url: URL, at directory: URL) throws -> CapturePixelSize {
        do {
            let reader = try CapturePNGReader(url: url)
            try CaptureRasterStore.write(size: reader.size, to: directory, fillRow: reader.read)
            return reader.size
        } catch CapturePNGReader.Failure.unsupported {
        }
        guard
            let source = CGImageSourceCreateWithURL(
                url as CFURL,
                [
                    kCGImageSourceShouldCache: false
                ] as CFDictionary),
            let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
            let width = properties[kCGImagePropertyPixelWidth] as? Int,
            let height = properties[kCGImagePropertyPixelHeight] as? Int
        else { throw CaptureRasterError.invalidTile }
        let size = try CapturePixelSize(width: width, height: height)
        guard size.byteCount <= 48_000_000 else { throw Failure.importBudget }
        guard
            let image = CGImageSourceCreateThumbnailAtIndex(
                source, 0,
                [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: max(size.width, size.height)
                ] as CFDictionary)
        else {
            throw CaptureRasterError.invalidTile
        }
        return try store(image, at: directory)
    }

    enum Failure: LocalizedError {
        case importBudget
        var errorDescription: String? {
            "This image exceeds the safe decoding budget. Open a smaller region of the image."
        }
    }
}
