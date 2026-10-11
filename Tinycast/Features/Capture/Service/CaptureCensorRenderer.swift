import CoreGraphics
import Foundation

enum CaptureCensorRenderer {
    nonisolated static func mask(_ annotations: [CaptureAnnotation], rect: CGRect, pixels: inout Data) throws {
        let masks = annotations.filter { ($0.tool == .cover || $0.tool == .erase) && $0.bounds.intersects(rect) }
        guard !masks.isEmpty else { return }
        let width = Int(rect.width), height = Int(rect.height)
        guard pixels.count == width * height * 4,
            let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue), let bytes = context.data
        else { throw CaptureRasterError.invalidSize }
        context.setShouldAntialias(false)
        context.translateBy(x: -rect.minX, y: rect.maxY)
        context.scaleBy(x: 1, y: -1)
        CaptureAnnotationRenderer.draw(masks, in: context)
        let overlay = bytes.assumingMemoryBound(to: UInt8.self)
        pixels.withUnsafeMutableBytes { destination in
            let output = destination.bindMemory(to: UInt8.self)
            for offset in stride(from: 0, to: output.count, by: 4) where overlay[offset + 3] == 255 {
                for channel in 0..<4 { output[offset + channel] = overlay[offset + channel] }
            }
        }
    }
}
