import CoreImage.CIFilterBuiltins
import CoreMedia
import CoreText

final class CaptureRecordingRenderer {
    private let context = CIContext(options: [.cacheIntermediates: false])
    private let pool: CVMutablePixelBuffer.Pool
    private let bounds: CGRect
    private let options: CaptureRecordingOptions
    private let overlays: CaptureRecordingOverlays
    private var caption: (text: String, image: CIImage)?

    init(size: CapturePixelSize, options: CaptureRecordingOptions, overlays: CaptureRecordingOverlays) throws {
        bounds = CGRect(x: 0, y: 0, width: size.width, height: size.height)
        self.options = options; self.overlays = overlays
        pool = try CVMutablePixelBuffer.Pool(pixelBufferAttributes: .init(
            pixelFormatType: .init(rawValue: kCVPixelFormatType_32BGRA), size: .init(width: size.width, height: size.height)))
    }

    func render(_ sample: CaptureRecordingBuffers.Sample) throws -> CaptureRecordingBuffers.Sample {
        guard case .pixelBuffer(let screen) = sample.content else { throw CaptureVideoError.invalidMedia }
        var image = screen.withUnsafeBuffer { CIImage(cvPixelBuffer: $0) }
        let layers = overlays.snapshot(at: sample.presentationTimeStamp)
        if options.camera, let camera = layers.camera, case .pixelBuffer(let pixels) = camera.content {
            let source = pixels.withUnsafeBuffer { CIImage(cvPixelBuffer: $0) }
            image = cameraImage(source).composited(over: image)
        }
        if let key = layers.key, options.keys != .off {
            if caption?.text != key { caption = (key, try label(key)) }
            if let caption { image = caption.image.composited(over: image) }
        } else { caption = nil }
        let buffer = try pool.makeMutablePixelBuffer(.init(allocationThreshold: 3))
        buffer.withUnsafeBuffer {
            context.render(image, to: $0, bounds: bounds, colorSpace: CGColorSpace(name: CGColorSpace.sRGB))
        }
        return .init(CMReadySampleBuffer(pixelBuffer: CVReadOnlyPixelBuffer(buffer),
            presentationTimeStamp: sample.presentationTimeStamp, duration: sample.duration))
    }

    private func cameraImage(_ source: CIImage) -> CIImage {
        let side = min(bounds.width, bounds.height) * options.cameraFraction
        let margin = min(bounds.width, bounds.height) * 0.025
        let left = options.cameraPosition == .topLeft || options.cameraPosition == .bottomLeft
        let bottom = options.cameraPosition == .bottomLeft || options.cameraPosition == .bottomRight
        let rect = CGRect(x: left ? margin : bounds.maxX - side - margin,
            y: bottom ? margin : bounds.maxY - side - margin, width: side, height: side)
        let cropSize = min(source.extent.width, source.extent.height)
        let crop = CGRect(x: source.extent.midX - cropSize / 2, y: source.extent.midY - cropSize / 2,
            width: cropSize, height: cropSize)
        var image = source.cropped(to: crop)
            .transformed(by: .init(translationX: -crop.minX, y: -crop.minY))
            .transformed(by: .init(scaleX: side / cropSize, y: side / cropSize))
        if options.mirrorCamera {
            image = image.transformed(by: CGAffineTransform(a: -1, b: 0, c: 0, d: 1, tx: side, ty: 0))
        }
        image = image.transformed(by: .init(translationX: rect.minX, y: rect.minY))
        let mask = CIFilter.roundedRectangleGenerator()
        mask.extent = rect; mask.radius = Float(side / 2); mask.color = .white
        let blend = CIFilter.blendWithMask()
        blend.inputImage = image; blend.backgroundImage = CIImage.empty(); blend.maskImage = mask.outputImage
        return blend.outputImage?.cropped(to: rect) ?? image
    }

    private func label(_ text: String) throws -> CIImage {
        let height = max(16, min(72, bounds.height * 0.06)), font = CTFontCreateUIFontForLanguage(.system, height * 0.5, nil)!
        let attributes = [kCTFontAttributeName: font, kCTForegroundColorAttributeName: CGColor(gray: 1, alpha: 1)] as CFDictionary
        let line = CTLineCreateWithAttributedString(CFAttributedStringCreate(nil, text as CFString, attributes)!)
        let width = min(bounds.width * 0.7, ceil(CTLineGetTypographicBounds(line, nil, nil, nil)) + height)
        guard let bitmap = CGContext(data: nil, width: Int(ceil(width)), height: Int(ceil(height)),
            bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { throw CaptureVideoError.invalidMedia }
        bitmap.setFillColor(CGColor(gray: 0.05, alpha: 0.85))
        bitmap.addPath(CGPath(roundedRect: CGRect(x: 0, y: 0, width: width, height: height),
            cornerWidth: height / 2, cornerHeight: height / 2, transform: nil))
        bitmap.fillPath()
        bitmap.textPosition = CGPoint(x: height / 2, y: height * 0.28)
        CTLineDraw(line, bitmap)
        guard let image = bitmap.makeImage() else { throw CaptureVideoError.invalidMedia }
        return CIImage(cgImage: image).transformed(by: .init(translationX: (bounds.width - width) / 2,
            y: max(4, bounds.height * 0.04)))
    }
}
