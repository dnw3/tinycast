import AppKit
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

final class Pixels {
    let width: Int
    init(width: Int) { self.width = width }
    func read(_ buffer: UnsafeMutableRawPointer, offset: Int, count: Int) -> Int {
        let bytes = buffer.assumingMemoryBound(to: UInt8.self)
        for index in 0..<count {
            let position = offset + index
            let x = (position / 4) % width
            let y = position / (4 * width)
            switch position % 4 {
            case 0: bytes[index] = UInt8((x / 11 + y / 29) % 256)
            case 1: bytes[index] = UInt8((x / 17 + y / 7) % 256)
            case 2: bytes[index] = UInt8((x / 31 + y / 13) % 256)
            default: bytes[index] = 255
            }
        }
        return count
    }
}

@main struct CaptureImageIOPerformance {
    @MainActor static func main() throws {
        guard (4...5).contains(CommandLine.arguments.count) else {
            print("Usage: capture-imageio-performance WIDTH HEIGHT OUTPUT_FILE [pasteboard]")
            exit(2)
        }
        let size = try CapturePixelSize(
            width: Int(CommandLine.arguments[1]) ?? 0, height: Int(CommandLine.arguments[2]) ?? 0)
        let width = size.width
        let height = size.height
        let url = URL(fileURLWithPath: CommandLine.arguments[3])
        var callbacks = CGDataProviderDirectCallbacks(
            version: 0, getBytePointer: nil, releaseBytePointer: nil,
            getBytesAtPosition: { info, buffer, offset, count in
                Unmanaged<Pixels>.fromOpaque(info!).takeUnretainedValue().read(buffer, offset: Int(offset), count: count)
            },
            releaseInfo: { info in Unmanaged<Pixels>.fromOpaque(info!).release() }
        )
        let source = Unmanaged.passRetained(Pixels(width: width)).toOpaque()
        let provider = CGDataProvider(directInfo: source, size: off_t(width * height * 4), callbacks: &callbacks)!
        let image = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
            bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
        let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { fatalError("encode failed") }
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        print("output", width, height, data.count)
        if CommandLine.arguments.contains("pasteboard") {
            let board = NSPasteboard.withUniqueName()
            defer { board.releaseGlobally() }
            print("pasteboardWrite", board.setData(data, forType: .png))
            print("pasteboardRoundTrip", board.data(forType: .png) == data)
        }
    }
}
