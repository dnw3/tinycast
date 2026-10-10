import CoreGraphics
import Darwin
import Foundation
import ImageIO

@main
struct CaptureExportPerformance {
    static func main() throws {
        guard (4...6).contains(CommandLine.arguments.count) else {
            print("Usage: capture-export-performance INPUT_IMAGE OUTPUT_DIRECTORY REPEAT_COUNT [FORMAT] [encode-only]")
            exit(2)
        }
        let input = URL(fileURLWithPath: CommandLine.arguments[1])
        let directory = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
        let repeats = Int(CommandLine.arguments[3]) ?? 1
        let format = CommandLine.arguments.count > 4 ? CommandLine.arguments[4] : "all"
        let verify = CommandLine.arguments.last != "encode-only"
        precondition((1...30).contains(repeats))
        precondition(["all", "png", "avif", "webp-lossless", "webp-smaller"].contains(format))
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        let raster = UUID().uuidString
        let size = try CaptureImageSource.load(input, at: directory.appendingPathComponent(raster))
        try report(["stage": "imported", "maximumRSS": maximumRSS()])
        let document = CaptureDocument(id: UUID(), createdAt: Date(), size: size,
            pieces: [.init(raster: raster, source: CGRect(x: 0, y: 0, width: size.width, height: size.height), origin: .zero)])
        let scale: CaptureExportOptions.Scale = size.width * size.height <= 4_000_000 ? .original : .quarter
        let outputs: [(String, CaptureExportOptions)] = [
            ("png", .init(format: .png, scale: scale)),
            ("avif", .init(format: .avif, scale: scale)),
            ("webp-lossless", .init(format: .webp, scale: scale)),
            ("webp-smaller", .init(format: .webp, scale: scale, webPCompression: .lossy))
        ]
        var reference: [UInt8]?
        for (name, options) in outputs where CaptureRenderer.exportFormats.contains(options.format)
            && (format == "all" || format == name) {
            let url = directory.appendingPathComponent("\(name).\(options.format.rawValue)")
            for iteration in 1...(options.format == .webp && options.webPCompression == .lossless ? repeats : 1) {
                try autoreleasepool {
                    let started = ContinuousClock.now
                    try CaptureRenderer.export(document: document, directory: directory, to: url, options: options)
                    let elapsed = started.duration(to: .now).components
                    let milliseconds = Double(elapsed.seconds) * 1000 + Double(elapsed.attoseconds) / 1e15
                    let encodedMaximumRSS = maximumRSS()
                    let bytes = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize!
                    let dimensions = try options.validatedDimensions(for: document)
                    var result: [String: Any] = ["format": name, "iteration": iteration,
                        "width": dimensions.width, "height": dimensions.height, "bytes": bytes,
                        "milliseconds": milliseconds, "maximumRSSAfterEncode": encodedMaximumRSS]
                    if verify {
                        let pixels = try rgba(url, size: dimensions)
                        if name == "png" { reference = pixels }
                        if let reference {
                            let maximum = zip(reference, pixels).reduce(0) { max($0, abs(Int($1.0) - Int($1.1))) }
                            if name == "webp-lossless" { precondition(maximum <= 1) }
                            result["maximumChannelDifferenceFromPNG"] = maximum
                        }
                        result["maximumRSSAfterDecode"] = maximumRSS()
                    }
                    try report(result)
                }
            }
        }
    }

    static func maximumRSS() -> Int64 {
        var usage = rusage()
        precondition(getrusage(RUSAGE_SELF, &usage) == 0)
        return Int64(usage.ru_maxrss)
    }

    static func report(_ values: [String: Any]) throws {
        var data = try JSONSerialization.data(withJSONObject: values, options: [.sortedKeys])
        data.append(10)
        try FileHandle.standardOutput.write(contentsOf: data)
    }

    static func rgba(_ url: URL, size: CapturePixelSize) throws -> [UInt8] {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
            let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
            image.width == size.width, image.height == size.height,
            let context = CGContext(data: nil, width: size.width, height: size.height, bitsPerComponent: 8,
                bytesPerRow: size.rowBytes, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue), let pixels = context.data
        else { throw CaptureRasterError.invalidTile }
        context.draw(image, in: CGRect(x: 0, y: 0, width: size.width, height: size.height))
        return Array(UnsafeBufferPointer(start: pixels.assumingMemoryBound(to: UInt8.self), count: size.byteCount))
    }
}
