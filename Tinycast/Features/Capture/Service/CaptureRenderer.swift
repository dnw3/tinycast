import Accelerate
import CoreGraphics
import Foundation
import ImageIO

enum CaptureRenderer {
    nonisolated static func scrollPreview(
        previous: CGImage?, previousSize: CapturePixelSize, document: CaptureDocument, directory: URL
    ) throws -> CGImage {
        guard let piece = document.pieces.last else { throw CaptureRasterError.invalidTile }
        let scale = min(1, 240 / max(document.bounds.width, document.bounds.height))
        let width = max(1, Int(document.bounds.width * scale)),
            height = max(1, Int(document.bounds.height * scale))
        guard
            let context = CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { throw CaptureRasterError.invalidSize }
        if let previous {
            context.draw(
                previous,
                in: CGRect(
                    x: 0, y: CGFloat(height) - CGFloat(previousSize.height) * scale,
                    width: CGFloat(previousSize.width) * scale, height: CGFloat(previousSize.height) * scale))
        }
        let size = try CapturePixelSize(width: Int(piece.source.width), height: Int(piece.source.height))
        let strip = CaptureDocument(
            id: document.id, createdAt: document.createdAt, size: size,
            pieces: [.init(raster: piece.raster, source: piece.source, origin: .zero)])
        let image = try preview(document: strip, directory: directory, maximum: 240)
        context.clear(
            CGRect(
                x: piece.origin.x * scale, y: CGFloat(height) - piece.bounds.maxY * scale,
                width: piece.source.width * scale, height: piece.source.height * scale))
        context.draw(
            image,
            in: CGRect(
                x: piece.origin.x * scale, y: CGFloat(height) - piece.bounds.maxY * scale,
                width: piece.source.width * scale, height: piece.source.height * scale))
        guard let result = context.makeImage() else { throw CaptureRasterError.invalidSize }
        return result
    }

    nonisolated static func image(
        document: CaptureDocument, directory: URL, rect: CGRect, includingVectorAnnotations: Bool = true
    ) throws -> CGImage {
        if document.edit.presentation != nil {
            return try CapturePresentationRenderer.image(
                document: document, directory: directory,
                rect: rect, includingVectorAnnotations: includingVectorAnnotations)
        }
        return try contentImage(
            document: document, directory: directory, rect: rect,
            includingVectorAnnotations: includingVectorAnnotations)
    }

    nonisolated static func contentImage(
        document: CaptureDocument, directory: URL, rect: CGRect, includingVectorAnnotations: Bool
    ) throws -> CGImage {
        let reader = try CaptureCompositeReader(document: document, directory: directory)
        var pixels = try CaptureImageProcessing.pixels(
            reader: reader, rect: rect, bounds: document.bounds,
            adjustments: document.edit.adjustments)
        return try pixels.withUnsafeMutableBytes { bytes in
            var source = vImage_Buffer(
                data: bytes.baseAddress, height: vImagePixelCount(rect.height),
                width: vImagePixelCount(rect.width), rowBytes: Int(rect.width) * 4)
            var destination = source
            guard
                vImagePremultiplyData_RGBA8888(&source, &destination, vImage_Flags(kvImageDoNotTile))
                    == kvImageNoError
            else { throw CaptureRasterError.invalidTile }
            guard
                let context = CGContext(
                    data: bytes.baseAddress, width: Int(rect.width), height: Int(rect.height),
                    bitsPerComponent: 8, bytesPerRow: Int(rect.width) * 4,
                    space: CGColorSpace(name: CGColorSpace.sRGB)!,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { throw CaptureRasterError.invalidSize }
            context.translateBy(x: -rect.minX, y: rect.height + rect.minY)
            context.scaleBy(x: 1, y: -1)
            try CaptureTranslationRenderer.draw(document.edit.translation, in: context)
            for annotation in document.edit.annotations {
                if [.spotlight, .pixelate, .magnifier].contains(annotation.tool) { continue }
                if annotation.tool == .blur {
                    try blur(annotation, rect: rect, reader: reader, document: document, context: context)
                } else if includingVectorAnnotations {
                    CaptureAnnotationRenderer.draw([annotation], in: context)
                }
            }
            if includingVectorAnnotations {
                CaptureAnnotationRenderer.spotlight(document.edit.annotations, in: context)
            }
            for annotation in document.edit.annotations where annotation.tool == .magnifier {
                try CaptureMagnifierRenderer.draw(
                    annotation, document: document, directory: directory,
                    rect: rect, context: context)
            }
            for annotation in document.edit.annotations where annotation.tool == .pixelate {
                try pixelate(annotation, rect: rect, reader: reader, document: document, context: context)
            }
            CaptureAnnotationRenderer.draw(
                document.edit.annotations.filter { $0.tool == .cover || $0.tool == .erase }, in: context)
            guard let image = context.makeImage() else { throw CaptureRasterError.invalidSize }
            return image
        }
    }

    nonisolated private static func blur(
        _ annotation: CaptureAnnotation, rect: CGRect, reader: CaptureCompositeReader,
        document: CaptureDocument, context: CGContext
    ) throws {
        let intersection = annotation.bounds.intersection(rect).intersection(document.bounds).integral
        guard CaptureGeometry.valid(intersection) else { return }
        let data = try CaptureImageProcessing.blurred(
            reader: reader, rect: intersection, bounds: document.bounds,
            adjustments: document.edit.adjustments, radius: min(24, max(2, Int(annotation.width * 2))))
        guard let provider = CGDataProvider(data: data as CFData),
            let image = CGImage(
                width: Int(intersection.width), height: Int(intersection.height), bitsPerComponent: 8,
                bitsPerPixel: 32, bytesPerRow: Int(intersection.width) * 4,
                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                provider: provider,
                decode: nil, shouldInterpolate: false, intent: .defaultIntent)
        else { throw CaptureRasterError.invalidTile }
        context.saveGState()
        context.clip(to: annotation.bounds)
        context.translateBy(x: intersection.minX, y: intersection.maxY)
        context.scaleBy(x: 1, y: -1)
        context.draw(image, in: CGRect(origin: .zero, size: intersection.size))
        context.restoreGState()
    }

    nonisolated static func color(
        document: CaptureDocument, directory: URL, at point: CGPoint
    ) throws -> CaptureColor {
        let bounds = document.outputBounds
        guard point.x.isFinite, point.y.isFinite else { throw CaptureRasterError.invalidRow }
        let rect = CGRect(
            x: min(bounds.maxX - 1, max(bounds.minX, floor(point.x))),
            y: min(bounds.maxY - 1, max(bounds.minY, floor(point.y))), width: 1, height: 1)
        let image = try image(document: document, directory: directory, rect: rect)
        guard let data = image.dataProvider?.data, CFDataGetLength(data) >= 4,
            let bytes = CFDataGetBytePtr(data)
        else { throw CaptureRasterError.invalidTile }
        let alpha = Double(bytes[3])
        func channel(_ index: Int) -> UInt8 {
            alpha > 0 ? UInt8(min(255, (Double(bytes[index]) * 255 / alpha).rounded())) : 0
        }
        return CaptureColor(red: channel(0), green: channel(1), blue: channel(2))
    }

    nonisolated private static func pixelate(
        _ annotation: CaptureAnnotation, rect: CGRect, reader: CaptureCompositeReader,
        document: CaptureDocument, context: CGContext
    ) throws {
        let bounds = annotation.bounds
        let intersection = bounds.intersection(rect).intersection(document.bounds)
        guard CaptureGeometry.valid(intersection) else { return }
        let side = 16
        let anchorX = annotation.reflection?.horizontal == true ? ceil(bounds.maxX) : floor(bounds.minX)
        let anchorY = annotation.reflection?.vertical == true ? ceil(bounds.maxY) : floor(bounds.minY)
        let startX = Int(anchorX) + Int(floor((intersection.minX - anchorX) / CGFloat(side))) * side
        let startY = Int(anchorY) + Int(floor((intersection.minY - anchorY) / CGFloat(side))) * side
        context.saveGState()
        context.clip(to: bounds)
        defer { context.restoreGState() }
        for y in stride(from: startY, to: Int(intersection.maxY), by: side) {
            for x in stride(from: startX, to: Int(intersection.maxX), by: side) {
                let block = CGRect(x: x, y: y, width: side, height: side).intersection(document.bounds)
                    .integral
                let pixels = try CaptureImageProcessing.pixels(
                    reader: reader, rect: block, bounds: document.bounds,
                    adjustments: document.edit.adjustments)
                var totals = [Double](repeating: 0, count: 4)
                for offset in stride(from: 0, to: pixels.count, by: 4) {
                    for channel in 0..<4 { totals[channel] += Double(pixels[offset + channel]) }
                }
                let divisor = Double(pixels.count / 4) * 255
                context.setFillColor(
                    CGColor(
                        colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
                        components: totals.map { CGFloat($0 / divisor) })!)
                context.fill(block)
            }
        }
    }

    nonisolated static func png(document: CaptureDocument, directory: URL, to url: URL) throws {
        let rect = document.outputBounds
        let size = try CapturePixelSize(width: Int(rect.width), height: Int(rect.height))
        var band = -1
        var bandOffset = 0
        var imageData: CFData?
        let bandHeight = max(1, min(32, 1_048_576 / size.rowBytes))
        try CapturePNGWriter.write(size: size, to: url) { row, buffer in
            let next = row / bandHeight
            if next != band {
                band = next
                let top = max(rect.minY, rect.minY + CGFloat(band * bandHeight) - 1)
                let bottom = min(rect.maxY, rect.minY + CGFloat((band + 1) * bandHeight) + 1)
                bandOffset = Int(rect.minY + CGFloat(band * bandHeight) - top)
                imageData = try autoreleasepool {
                    let image = try image(
                        document: document, directory: directory,
                        rect: CGRect(
                            x: rect.minX, y: top, width: rect.width, height: bottom - top))
                    return image.dataProvider?.data
                }
            }
            guard let imageData, let start = CFDataGetBytePtr(imageData) else {
                throw CaptureRasterError.invalidTile
            }
            buffer.copyMemory(
                from: UnsafeRawBufferPointer(
                    start: start.advanced(by: (row % bandHeight + bandOffset) * size.rowBytes),
                    count: size.rowBytes))
            try CapturePixelAlpha.unpremultiply(buffer)
        }
    }

    nonisolated static func preview(
        document: CaptureDocument, directory: URL, maximum: Int = 900, includingVectorAnnotations: Bool = true
    ) throws -> CGImage {
        let bounds = document.outputBounds
        let scale = min(1, CGFloat(maximum) / max(bounds.width, bounds.height))
        let width = max(1, Int(bounds.width * scale)), height = max(1, Int(bounds.height * scale))
        guard
            let context = CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { throw CaptureRasterError.invalidSize }
        for y in stride(from: Int(bounds.minY), to: Int(bounds.maxY), by: 512) {
            for x in stride(from: Int(bounds.minX), to: Int(bounds.maxX), by: 512) {
                try Task.checkCancellation()
                try autoreleasepool {
                    let rect = CGRect(
                        x: x, y: y, width: min(512, Int(bounds.maxX) - x),
                        height: min(512, Int(bounds.maxY) - y))
                    let tile = try image(
                        document: document, directory: directory, rect: rect,
                        includingVectorAnnotations: includingVectorAnnotations)
                    let left = ((rect.minX - bounds.minX) * CGFloat(width) / bounds.width).rounded()
                    let right = ((rect.maxX - bounds.minX) * CGFloat(width) / bounds.width).rounded()
                    let top = ((rect.minY - bounds.minY) * CGFloat(height) / bounds.height).rounded()
                    let bottom = ((rect.maxY - bounds.minY) * CGFloat(height) / bounds.height).rounded()
                    context.draw(
                        tile,
                        in: CGRect(
                            x: left, y: CGFloat(height) - bottom,
                            width: right - left, height: bottom - top))
                }
            }
        }
        guard let result = context.makeImage() else { throw CaptureRasterError.invalidSize }
        return result
    }

    nonisolated static var exportFormats: [CaptureExportOptions.Format] {
        let identifiers = CGImageDestinationCopyTypeIdentifiers() as? [String] ?? []
        return CaptureExportOptions.Format.allCases.filter {
            $0 == .webp || identifiers.contains($0.identifier)
        }
    }

    nonisolated static func export(
        document: CaptureDocument, directory: URL, to url: URL, options: CaptureExportOptions
    ) throws {
        guard exportFormats.contains(options.format)
        else { throw Failure.unsupportedFormat }
        let size = try options.validatedDimensions(for: document)
        if options.format == .png, options.scale == .original, options.profile == .sRGB {
            try png(document: document, directory: directory, to: url)
            return
        }
        let image = try exportImage(document: document, directory: directory, size: size, options: options)
        let temporary = url.deletingLastPathComponent().appendingPathComponent(
            ".\(UUID()).\(options.format.rawValue)")
        defer { try? FileManager.default.removeItem(at: temporary) }
        if options.format == .webp {
            try CaptureWebPEncoder.write(
                image, to: temporary, quality: options.quality,
                lossless: options.webPCompression == .lossless)
        } else {
            try imageIO(image, to: temporary, options: options)
        }
        try Task.checkCancellation()
        guard rename(temporary.path, url.path) == 0 else { throw CocoaError(.fileWriteUnknown) }
    }

    nonisolated static func exportImage(
        document: CaptureDocument, directory: URL, size: CapturePixelSize, options: CaptureExportOptions
    ) throws -> CGImage {
        let source = try preview(
            document: document, directory: directory, maximum: max(size.width, size.height))
        if options.format == .webp, options.profile == .sRGB, source.width == size.width,
            source.height == size.height
        {
            return source
        }
        let colorSpace = options.profile == .displayP3 ? CGColorSpace.displayP3 : CGColorSpace.sRGB
        guard
            let context = CGContext(
                data: nil, width: size.width, height: size.height, bitsPerComponent: 8,
                bytesPerRow: size.rowBytes, space: CGColorSpace(name: colorSpace)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { throw CaptureRasterError.invalidSize }
        let rect = CGRect(x: 0, y: 0, width: size.width, height: size.height)
        if options.format == .jpeg {
            context.setFillColor(CGColor(gray: 1, alpha: 1))
            context.fill(rect)
        }
        context.draw(source, in: rect)
        guard let image = context.makeImage() else { throw CaptureRasterError.invalidSize }
        return image
    }

    nonisolated private static func imageIO(
        _ image: CGImage, to url: URL, options: CaptureExportOptions
    ) throws {
        guard
            let destination = CGImageDestinationCreateWithURL(
                url as CFURL, options.format.identifier as CFString, 1, nil)
        else { throw CaptureRasterError.invalidTile }
        CGImageDestinationAddImage(
            destination, image, [kCGImageDestinationLossyCompressionQuality: options.quality] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw CaptureRasterError.invalidTile }
    }

    enum Failure: LocalizedError {
        case unsupportedFormat
        var errorDescription: String? {
            switch self {
            case .unsupportedFormat:
                String(localized: "This format or quality is unavailable. Choose another export format.")
            }
        }
    }
}
