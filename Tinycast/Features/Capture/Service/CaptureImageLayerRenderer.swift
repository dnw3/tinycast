import Accelerate
import CoreGraphics
import Foundation

enum CaptureImageLayerRenderer {
    nonisolated static func composite(
        _ layers: [CaptureImageLayer], directory: URL, rect: CGRect, into pixels: inout Data
    ) throws {
        let visible = layers.filter { $0.opacity > 0 && $0.bounds.intersects(rect) }
        guard !visible.isEmpty else { return }
        try pixels.withUnsafeMutableBytes { bytes in
            var source = vImage_Buffer(data: bytes.baseAddress, height: vImagePixelCount(rect.height),
                width: vImagePixelCount(rect.width), rowBytes: Int(rect.width) * 4)
            var destination = source
            guard vImagePremultiplyData_RGBA8888(&source, &destination, vImage_Flags(kvImageDoNotTile)) == kvImageNoError,
                let context = CGContext(data: bytes.baseAddress, width: Int(rect.width), height: Int(rect.height),
                    bitsPerComponent: 8, bytesPerRow: Int(rect.width) * 4,
                    space: CGColorSpace(name: CGColorSpace.sRGB)!,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { throw CaptureRasterError.invalidTile }
            context.translateBy(x: -rect.minX, y: rect.maxY)
            context.scaleBy(x: 1, y: -1)
            for layer in visible { try draw(layer, directory: directory, rect: rect, context: context) }
            try CapturePixelAlpha.unpremultiply(bytes)
        }
    }

    nonisolated private static func draw(
        _ layer: CaptureImageLayer, directory: URL, rect: CGRect, context: CGContext
    ) throws {
        let size = try CapturePixelSize(width: Int(layer.source.maxX), height: Int(layer.source.maxY))
        let document = CaptureDocument(id: layer.id, createdAt: .distantPast, size: size,
            pieces: [.init(raster: layer.raster,
                source: CGRect(origin: .zero, size: CGSize(width: size.width, height: size.height)), origin: .zero)])
        let reader = try CaptureCompositeReader(document: document, directory: directory)
        let mask = try layer.backgroundMask.flatMap {
            $0.enabled ? try CaptureImageMaskReader($0, directory: directory) : nil
        }
        let transform = CGAffineTransform(translationX: layer.frame.midX, y: layer.frame.midY)
            .rotated(by: layer.rotation * .pi / 180)
            .scaledBy(x: layer.frame.width / layer.source.width * (layer.reflection?.horizontal == true ? -1 : 1),
                y: layer.frame.height / layer.source.height * (layer.reflection?.vertical == true ? -1 : 1))
            .translatedBy(x: -layer.source.midX, y: -layer.source.midY)
        let visible = rect.applying(transform.inverted()).intersection(layer.source).integral
        guard CaptureGeometry.valid(visible) else { return }
        context.saveGState()
        defer { context.restoreGState() }
        context.concatenate(transform)
        context.clip(to: layer.source)
        context.setAlpha(layer.opacity)
        context.interpolationQuality = .high
        for y in stride(from: Int(visible.minY) / 512 * 512, to: Int(visible.maxY), by: 512) {
            for x in stride(from: Int(visible.minX) / 512 * 512, to: Int(visible.maxX), by: 512) {
                try Task.checkCancellation()
                try autoreleasepool {
                    let tile = CGRect(x: x, y: y, width: 512, height: 512).intersection(layer.source)
                    let sample = tile.insetBy(dx: -4, dy: -4).intersection(layer.source).integral
                    var data = try reader.read(rect: sample)
                    mask?.apply(to: &data, rect: sample, source: layer.source)
                    guard let provider = CGDataProvider(data: data as CFData),
                        let image = CGImage(width: Int(sample.width), height: Int(sample.height), bitsPerComponent: 8,
                            bitsPerPixel: 32, bytesPerRow: Int(sample.width) * 4,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue), provider: provider,
                            decode: nil, shouldInterpolate: true, intent: .defaultIntent)
                    else { throw CaptureRasterError.invalidTile }
                    context.saveGState()
                    context.setShouldAntialias(false)
                    context.clip(to: tile)
                    context.translateBy(x: sample.minX, y: sample.maxY)
                    context.scaleBy(x: 1, y: -1)
                    context.draw(image, in: CGRect(origin: .zero, size: sample.size))
                    context.restoreGState()
                }
            }
        }
    }
}
