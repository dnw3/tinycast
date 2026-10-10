import AppKit
import Foundation

@main
struct CaptureRasterPerformance {
    @MainActor static func main() throws {
        guard (4...5).contains(CommandLine.arguments.count) else {
            print("Usage: capture-raster-performance WIDTH HEIGHT OUTPUT_DIRECTORY [MODE]")
            print("Modes: verify, noise, noise-file, verify-noise, pasteboard, source")
            exit(2)
        }
        let size = try CapturePixelSize(
            width: Int(CommandLine.arguments[1]) ?? 0, height: Int(CommandLine.arguments[2]) ?? 0)
        let root = URL(fileURLWithPath: CommandLine.arguments[3], isDirectory: true)
        let mode = CommandLine.arguments.count == 5 ? CommandLine.arguments[4] : "pattern"
        let fill = mode.contains("noise") ? CaptureFixture.fillNoise : CaptureFixture.fill
        if mode == "pasteboard" {
            let url = root.appendingPathComponent("output.png")
            let board = NSPasteboard.withUniqueName()
            defer { board.releaseGlobally() }
            let data = try Data(contentsOf: url, options: .mappedIfSafe)
            precondition(board.setData(data, forType: .png))
            print("privatePasteboardWriteOnly=true pngBytes=\(data.count)")
            return
        }
        if mode.hasPrefix("verify") {
            try CaptureFixture.verifyPNG(at: root.appendingPathComponent("output.png"), size: size, fillRow: fill)
            print("verifiedPixels=\(size.width * size.height)")
            return
        }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        if mode == "source" { try sourceImage(size: size, at: root); return }
        let raster = root.appendingPathComponent("raster", isDirectory: true)
        let output = root.appendingPathComponent("output.png")
        let start = ContinuousClock.now
        try CaptureRasterStore.write(size: size, to: raster, fillRow: fill)
        let stored = ContinuousClock.now
        try CapturePNGWriter.write(raster: raster, to: output)
        let encoded = ContinuousClock.now
        let fileSize = try output.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        print("size=\(size.width)x\(size.height) pngBytes=\(fileSize) fixture=\(mode)")
        print("tileWrite=\(start.duration(to: stored)) pngExport=\(stored.duration(to: encoded))")
        if mode == "noise-file" { return }
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        let data = try Data(contentsOf: output, options: .mappedIfSafe)
        precondition(board.setData(data, forType: .png))
        precondition(board.data(forType: .png) == data)
        print("privatePasteboardRoundTrip=true")
    }

    static func sourceImage(size: CapturePixelSize, at directory: URL) throws {
        let context = CGContext(
            data: nil, width: size.width, height: size.height, bitsPerComponent: 8, bytesPerRow: size.rowBytes,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: size.width, height: size.height))
        for row in 0..<32 {
            context.setFillColor(CGColor(red: CGFloat(row % 5) / 5, green: 0.5, blue: 0.3, alpha: 0.7))
            context.fill(CGRect(x: 0, y: row * 70, width: size.width, height: 35))
        }
        let image = context.makeImage()!, raster = UUID().uuidString
        let start = ContinuousClock.now
        _ = try CaptureImageSource.store(image, at: directory.appendingPathComponent(raster))
        let stored = ContinuousClock.now
        let document = CaptureDocument(id: UUID(), createdAt: Date(), size: size,
            pieces: [.init(raster: raster, source: CGRect(x: 0, y: 0, width: size.width, height: size.height), origin: .zero)])
        let preview = try CaptureRenderer.preview(document: document, directory: directory)
        let rendered = ContinuousClock.now
        let frozen = try CaptureImageSource.preview(image)
        print("size=\(size.width)x\(size.height) preview=\(preview.width)x\(preview.height)")
        print("sourceWrite=\(start.duration(to: stored)) documentPreview=\(stored.duration(to: rendered))")
        print("frozenPreview=\(rendered.duration(to: .now)) pixels=\(frozen.width)x\(frozen.height)")
    }
}
