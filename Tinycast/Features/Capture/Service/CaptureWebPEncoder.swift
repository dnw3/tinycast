import CaptureWebP
import CoreGraphics
import Foundation

enum CaptureWebPEncoder {
    nonisolated static func write(_ image: CGImage, to url: URL, quality: Double, lossless: Bool) throws {
        try Task.checkCancellation()
        var writer = WebPMemoryWriter()
        WebPMemoryWriterInit(&writer)
        defer { WebPMemoryWriterClear(&writer) }
        let profile = try encode(image, quality: quality, lossless: lossless, writer: &writer)
        guard let bytes = writer.mem else { throw CaptureRasterError.invalidTile }
        try mux(bytes: bytes, count: writer.size, profile: profile, to: url)
    }

    nonisolated private static func encode(
        _ image: CGImage, quality: Double, lossless: Bool, writer: inout WebPMemoryWriter
    ) throws -> Data {
        guard image.width <= 16_383, image.height <= 16_383,
            image.width * image.height <= 4_000_000, quality.isFinite, (0...1).contains(quality),
            let space = image.colorSpace, let profile = space.copyICCData(),
            let context = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8,
                bytesPerRow: image.width * 4, space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
            let pixels = context.data
        else { throw CaptureRasterError.invalidSize }
        defer { withExtendedLifetime(context) {} }
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        try CapturePixelAlpha.unpremultiply(.init(start: pixels, count: image.width * image.height * 4))
        var config = WebPConfig(), picture = WebPPicture()
        guard WebPConfigPreset(&config, WEBP_PRESET_DRAWING, Float(quality * 100)) != 0,
            WebPPictureInit(&picture) != 0 else { throw CaptureRasterError.invalidTile }
        defer { WebPPictureFree(&picture) }
        if lossless {
            guard WebPConfigLosslessPreset(&config, 1) != 0 else { throw CaptureRasterError.invalidTile }
        }
        config.exact = 1; config.alpha_quality = 100; config.thread_level = 0; config.low_memory = 1
        guard WebPValidateConfig(&config) != 0 else { throw CaptureRasterError.invalidTile }
        picture.width = Int32(image.width); picture.height = Int32(image.height)
        picture.use_argb = 1
        picture.writer = WebPMemoryWrite
        picture.progress_hook = { _, _ in Task<Never, Never>.isCancelled ? 0 : 1 }
        guard WebPPictureImportRGBA(&picture, pixels.assumingMemoryBound(to: UInt8.self), Int32(image.width * 4)) != 0
        else { throw CaptureRasterError.invalidTile }
        let encoded = withUnsafeMutablePointer(to: &writer) { pointer in
            picture.custom_ptr = UnsafeMutableRawPointer(pointer)
            return WebPEncode(&config, &picture)
        }
        try Task.checkCancellation()
        guard encoded != 0 else { throw CaptureRasterError.invalidTile }
        return profile as Data
    }

    nonisolated private static func mux(bytes: UnsafePointer<UInt8>, count: Int, profile: Data, to url: URL) throws {
        var input = WebPData(bytes: bytes, size: count), output = WebPData()
        guard let mux = WebPMuxCreate(&input, 0) else { throw CaptureRasterError.invalidTile }
        defer { WebPMuxDelete(mux); WebPDataClear(&output) }
        let status = profile.withUnsafeBytes { buffer in
            var data = WebPData(bytes: buffer.baseAddress?.assumingMemoryBound(to: UInt8.self), size: buffer.count)
            return WebPMuxSetChunk(mux, "ICCP", &data, 1)
        }
        guard status == WEBP_MUX_OK, WebPMuxAssemble(mux, &output) == WEBP_MUX_OK, let result = output.bytes
        else { throw CaptureRasterError.invalidTile }
        try Task.checkCancellation()
        try Data(bytesNoCopy: UnsafeMutableRawPointer(mutating: result), count: output.size, deallocator: .none)
            .write(to: url)
    }
}
