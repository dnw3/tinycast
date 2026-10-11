import CoreGraphics
import Foundation

enum CaptureScreenSample {
    nonisolated static func pixel(at point: CGPoint, in bounds: CGRect, image: CGImage) -> CGPoint? {
        guard bounds.width > 0, bounds.height > 0, point.x.isFinite, point.y.isFinite,
            bounds.contains(point) else { return nil }
        return CGPoint(x: min(image.width - 1, Int((point.x - bounds.minX) / bounds.width * Double(image.width))),
            y: min(image.height - 1, Int((bounds.maxY - point.y) / bounds.height * Double(image.height))))
    }

    nonisolated static func hex(image: CGImage, pixel: CGPoint) -> String? {
        guard let sample = image.cropping(to: CGRect(origin: pixel, size: CGSize(width: 1, height: 1))),
            let context = CGContext(data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue), let data = context.data
        else { return nil }
        context.draw(sample, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        let bytes = data.assumingMemoryBound(to: UInt8.self)
        return String(format: "#%02X%02X%02X", bytes[0], bytes[1], bytes[2])
    }
}
