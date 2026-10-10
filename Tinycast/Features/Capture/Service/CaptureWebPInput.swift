import CoreGraphics
import Foundation

nonisolated struct CaptureWebPInput: Codable {
    let size: CapturePixelSize
    let profile: Data
    let quality: Double
    let lossless: Bool

    static func write(_ image: CGImage, quality: Double, lossless: Bool, to directory: URL) throws {
        let size = try CapturePixelSize(width: image.width, height: image.height)
        guard size.width * size.height <= 4_000_000, image.bitsPerPixel == 32,
            image.bytesPerRow == size.rowBytes, image.alphaInfo == .premultipliedLast,
            let profile = image.colorSpace?.copyICCData(), let data = image.dataProvider?.data,
            CFDataGetLength(data) == size.byteCount, let bytes = CFDataGetBytePtr(data)
        else { throw CaptureRasterError.invalidTile }
        defer { withExtendedLifetime(data) {} }
        try Task.checkCancellation()
        try Data(bytesNoCopy: UnsafeMutableRawPointer(mutating: bytes), count: size.byteCount, deallocator: .none)
            .write(to: directory.appendingPathComponent("pixels.rgba"))
        let request = Self(size: size, profile: profile as Data, quality: quality, lossless: lossless)
        try JSONEncoder().encode(request).write(to: directory.appendingPathComponent("request.json"))
    }

    static func read(from directory: URL) throws -> (Self, CGImage) {
        let requestURL = directory.appendingPathComponent("request.json")
        guard try requestURL.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? Int.max <= 65_536
        else { throw CaptureRasterError.invalidTile }
        let request = try JSONDecoder().decode(Self.self, from: Data(contentsOf: requestURL))
        let size = request.size, pixelsURL = directory.appendingPathComponent("pixels.rgba")
        guard size.width <= 16_383, size.height <= 16_383, size.width * size.height <= 4_000_000,
            request.quality.isFinite, (0...1).contains(request.quality),
            try pixelsURL.resourceValues(forKeys: [.fileSizeKey]).fileSize == size.byteCount,
            let space = CGColorSpace(iccData: request.profile as CFData), space.model == .rgb,
            let provider = CGDataProvider(url: pixelsURL as CFURL),
            let image = CGImage(width: size.width, height: size.height, bitsPerComponent: 8,
                bitsPerPixel: 32, bytesPerRow: size.rowBytes, space: space,
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
        else { throw CaptureRasterError.invalidTile }
        return (request, image)
    }
}
