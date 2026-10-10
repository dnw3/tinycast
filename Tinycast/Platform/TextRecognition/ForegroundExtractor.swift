import CoreImage.CIFilterBuiltins
import Foundation
import ImageIO
import UniformTypeIdentifiers
import Vision

nonisolated enum ForegroundExtractor {
    enum Failure: Error { case unreadable, noSubject }

    static func mask(at url: URL) async throws -> URL {
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true,
            let bytes = values.fileSize, (1...8_000_000).contains(bytes),
            let source = CGImageSourceCreateWithURL(url as CFURL, nil),
            let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
            let width = properties[kCGImagePropertyPixelWidth] as? Int,
            let height = properties[kCGImagePropertyPixelHeight] as? Int,
            (1...1024).contains(width), (1...1024).contains(height),
            let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else { throw Failure.unreadable }
        try Task.checkCancellation()
        let handler = ImageRequestHandler(image)
        guard let result = try await handler.perform(GenerateForegroundInstanceMaskRequest()),
            !result.allInstances.isEmpty
        else { throw Failure.noSubject }
        let buffer = try result.generateScaledMask(for: result.allInstances, scaledToImageFrom: handler)
        try Task.checkCancellation()
        let filter = CIFilter.colorMatrix()
        filter.inputImage = CIImage(cvPixelBuffer: buffer)
        filter.rVector = CIVector(x: 0, y: 0, z: 0, w: 0)
        filter.gVector = filter.rVector
        filter.bVector = filter.rVector
        filter.aVector = CIVector(x: 1, y: 0, z: 0, w: 0)
        filter.biasVector = CIVector(x: 1, y: 1, z: 1, w: 0)
        let context = CIContext(options: [.cacheIntermediates: false])
        let output = url.appendingPathExtension("mask.png")
        guard let mask = filter.outputImage,
            let rendered = context.createCGImage(mask, from: mask.extent, format: .RGBA8,
                colorSpace: CGColorSpace(name: CGColorSpace.sRGB)),
            let destination = CGImageDestinationCreateWithURL(output as CFURL, UTType.png.identifier as CFString, 1, nil)
        else { throw Failure.unreadable }
        CGImageDestinationAddImage(destination, rendered, nil)
        guard CGImageDestinationFinalize(destination) else { throw Failure.unreadable }
        return output
    }
}
