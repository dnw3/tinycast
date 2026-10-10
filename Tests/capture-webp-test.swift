import CoreGraphics
import Foundation
import ImageIO

@main
struct CaptureWebPTests {
    static func main() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("capture-webp-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try boundaries()
        let size = try CapturePixelSize(width: 73, height: 61)
        let raster = UUID().uuidString
        try CaptureRasterStore.write(size: size, to: root.appendingPathComponent(raster)) { row, buffer in
            let bytes = buffer.bindMemory(to: UInt8.self)
            for x in 0..<size.width {
                bytes[x * 4] = UInt8((x * 3) % 256)
                bytes[x * 4 + 1] = UInt8((row * 4) % 256)
                bytes[x * 4 + 2] = 128
                bytes[x * 4 + 3] = [0, 64, 128, 255][x % 4]
            }
        }
        var document = CaptureDocument(id: UUID(), createdAt: Date(), size: size,
            pieces: [.init(raster: raster, source: CGRect(x: 0, y: 0, width: size.width, height: size.height), origin: .zero)])
        document.edit.annotations = [.init(id: UUID(), tool: .cover, points: [CGPoint(x: 10, y: 10), CGPoint(x: 30, y: 30)])]
        try pixels(document: document, directory: root)
        try await workerPixels(document: document, directory: root)
        let output = root.appendingPathComponent("repeat.webp")
        for _ in 0..<30 {
            try autoreleasepool {
                try CaptureRenderer.export(document: document, directory: root, to: output,
                    options: .init(format: .webp))
                try expect(try image(output).width == 73)
            }
        }
        try await cancellation(in: root, destination: output)
        try await workerFailures(document: document, directory: root, destination: output)
        print("WebP pixels, ICC, 4 MP, 30 encodes, helper output, cancellation and reaping passed")
    }

    static var helper: URL {
        URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent()
            .appendingPathComponent("CaptureWebPHelper")
    }

    static func workerPixels(document: CaptureDocument, directory: URL) async throws {
        for profile in CaptureExportOptions.Profile.allCases {
            for compression in CaptureExportOptions.WebPCompression.allCases {
                let options = CaptureExportOptions(format: .webp, profile: profile, webPCompression: compression)
                let output = directory.appendingPathComponent("worker-\(profile.rawValue)-\(compression.rawValue).webp")
                let direct = directory.appendingPathComponent("direct.webp")
                try CaptureRenderer.export(document: document, directory: directory, to: direct, options: options)
                try await CaptureWebPWorker.export(document: document, directory: directory, to: output,
                    options: options, executable: helper)
                try expect(try rgba(image(output)) == rgba(image(direct)))
                try expect(try chunk("ICCP", in: Data(contentsOf: output)) == chunk("ICCP", in: Data(contentsOf: direct)))
            }
        }
        let input = directory.appendingPathComponent("invalid-input")
        try FileManager.default.createDirectory(at: input, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: input) }
        let raster = try CaptureRenderer.preview(document: document, directory: directory)
        try CaptureWebPInput.write(raster, quality: 0.92, lossless: true, to: input)
        try Data([0]).write(to: input.appendingPathComponent("pixels.rgba"))
        do {
            _ = try CaptureWebPInput.read(from: input); preconditionFailure("Truncated pixels accepted")
        } catch CaptureRasterError.invalidTile {}
        try Data(repeating: 32, count: 65_537).write(to: input.appendingPathComponent("request.json"))
        do {
            _ = try CaptureWebPInput.read(from: input); preconditionFailure("Unbounded request accepted")
        } catch CaptureRasterError.invalidTile {}
    }

    static func workerFailures(document: CaptureDocument, directory: URL, destination: URL) async throws {
        let original = try Data(contentsOf: destination)
        let sleeper = directory.appendingPathComponent("slow-helper")
        try Data("#!/bin/sh\necho $$ > \"$1/pid\"\nexec /bin/sleep 30\n".utf8).write(to: sleeper)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: sleeper.path)
        for cancel in [true, false] {
            let work = Task {
                try await CaptureWebPWorker.export(document: document, directory: directory, to: destination,
                    options: .init(format: .webp), executable: sleeper,
                    timeout: cancel ? .seconds(30) : .seconds(1))
            }
            let pid = try await workerPID(in: directory)
            if cancel { work.cancel() }
            do {
                try await work.value; preconditionFailure("Unfinished helper published output")
            } catch is CancellationError {
                precondition(cancel)
            } catch CaptureRasterError.compressionFailed { precondition(!cancel) }
            precondition(kill(pid, 0) == -1 && errno == ESRCH, "Helper was not reaped")
            try expect(try Data(contentsOf: destination) == original)
            let names = try FileManager.default.contentsOfDirectory(atPath: directory.path)
            precondition(!names.contains { $0.hasPrefix("webp-") || $0.hasPrefix(".") })
        }
        for executable in [directory.appendingPathComponent("missing-helper"), URL(fileURLWithPath: "/usr/bin/false")] {
            do {
                try await CaptureWebPWorker.export(document: document, directory: directory, to: destination,
                    options: .init(format: .webp), executable: executable)
                preconditionFailure("Failed helper published output")
            } catch {}
            try expect(try Data(contentsOf: destination) == original)
        }
    }

    static func workerPID(in directory: URL) async throws -> Int32 {
        for _ in 0..<100 {
            let children = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            for child in children where child.lastPathComponent.hasPrefix("webp-") {
                if let value = try? String(contentsOf: child.appendingPathComponent("pid"), encoding: .utf8),
                    let pid = Int32(value.trimmingCharacters(in: .whitespacesAndNewlines)) { return pid }
            }
            try await Task.sleep(for: .milliseconds(10))
        }
        throw CaptureRasterError.invalidTile
    }

    static func boundaries() throws {
        func document(_ width: Int, _ height: Int) throws -> CaptureDocument {
            .init(id: UUID(), createdAt: Date(), size: try CapturePixelSize(width: width, height: height), pieces: [])
        }
        let options = CaptureExportOptions(format: .webp)
        precondition(CaptureRenderer.exportFormats.contains(.webp))
        try expect(try options.validatedDimensions(for: document(16_383, 1)).width == 16_383)
        try expect(try options.validatedDimensions(for: document(2000, 2000)).height == 2000)
        for size in [(16_384, 1), (1, 16_384)] {
            do {
                _ = try options.validatedDimensions(for: document(size.0, size.1))
                preconditionFailure("Oversized WebP side accepted")
            } catch CaptureExportOptions.Failure.webPDimensions {}
        }
        do {
            _ = try options.validatedDimensions(for: document(2001, 2000))
            preconditionFailure("Over-budget WebP accepted")
        } catch CaptureExportOptions.Failure.encodingBudget {}
        let long = try document(1600, 30000)
        try expect(try CaptureExportOptions().validatedDimensions(for: long).height == 30000)
        let quarter = try CaptureExportOptions(format: .webp, scale: .quarter).validatedDimensions(for: long)
        precondition(quarter.width == 400 && quarter.height == 7500)
    }

    static func pixels(document: CaptureDocument, directory: URL) throws {
        for profile in CaptureExportOptions.Profile.allCases {
            let png = directory.appendingPathComponent("\(profile.rawValue).png")
            let webp = directory.appendingPathComponent("\(profile.rawValue).webp")
            try CaptureRenderer.export(document: document, directory: directory, to: png,
                options: .init(profile: profile))
            try CaptureRenderer.export(document: document, directory: directory, to: webp,
                options: .init(format: .webp, profile: profile))
            let expected = try rgba(image(png)), actual = try rgba(image(webp))
            precondition(expected.count == actual.count)
            for i in expected.indices {
                precondition(abs(Int(expected[i]) - Int(actual[i])) <= 1, "Lossless WebP changed rendered RGBA")
            }
            let data = try Data(contentsOf: webp)
            precondition(data.prefix(4) == Data("RIFF".utf8) && data[8..<12] == Data("WEBP".utf8))
            let icc = try chunk("ICCP", in: data)
            let space = CGColorSpace(name: profile == .displayP3 ? CGColorSpace.displayP3 : CGColorSpace.sRGB)!
            precondition(icc == space.copyICCData()! as Data)
        }
        let lossy = directory.appendingPathComponent("lossy.webp")
        try CaptureRenderer.export(document: document, directory: directory, to: lossy,
            options: .init(format: .webp, quality: 0.92, webPCompression: .lossy))
        let decoded = try rgba(image(lossy))
        let png = try rgba(image(directory.appendingPathComponent("sRGB.png")))
        var difference = 0
        for i in stride(from: 0, to: decoded.count, by: 4) {
            precondition(decoded[i + 3] == png[i + 3], "Lossy WebP must preserve alpha")
            for channel in 0..<3 { difference += abs(Int(decoded[i + channel]) - Int(png[i + channel])) }
        }
        precondition(Double(difference) / Double(decoded.count / 4 * 3) < 12)
        for y in 14..<26 {
            for x in 14..<26 {
                let offset = (y * 73 + x) * 4
                precondition(decoded[offset + 3] == 255 && decoded[offset...offset + 2].allSatisfy { $0 <= 8 })
            }
        }
    }

    static func cancellation(in root: URL, destination: URL) async throws {
        let original = try Data(contentsOf: destination)
        let size = try CapturePixelSize(width: 2000, height: 2000), raster = UUID().uuidString
        try CaptureRasterStore.write(size: size, to: root.appendingPathComponent(raster), fillRow: CaptureFixture.fillNoise)
        let document = CaptureDocument(id: UUID(), createdAt: Date(), size: size,
            pieces: [.init(raster: raster, source: CGRect(x: 0, y: 0, width: 2000, height: 2000), origin: .zero)])
        let large = root.appendingPathComponent("large.webp")
        try CaptureRenderer.export(document: document, directory: root, to: large, options: .init(format: .webp))
        let decoded = try image(large)
        precondition(decoded.width == size.width && decoded.height == size.height)
        let pixels = try rgba(decoded)
        var expected = [UInt8](repeating: 0, count: size.rowBytes)
        for row in 0..<size.height {
            expected.withUnsafeMutableBytes { CaptureFixture.fillNoise(row: row, buffer: $0) }
            precondition(pixels[(row * size.rowBytes)..<((row + 1) * size.rowBytes)].elementsEqual(expected))
        }
        let workerOutput = root.appendingPathComponent("large-worker.webp")
        try await CaptureWebPWorker.export(document: document, directory: root, to: workerOutput,
            options: .init(format: .webp), executable: helper)
        try expect(try Data(contentsOf: workerOutput) == Data(contentsOf: large))
        let work = Task.detached {
            try CaptureRenderer.export(document: document, directory: root, to: destination, options: .init(format: .webp))
        }
        try await Task.sleep(for: .milliseconds(50))
        work.cancel()
        do { try await work.value; preconditionFailure("Cancelled export published a file") } catch is CancellationError {}
        try expect(try Data(contentsOf: destination) == original)
        try expect(try FileManager.default.contentsOfDirectory(atPath: root.path).allSatisfy { !$0.hasPrefix(".") })
        do {
            try CaptureWebPEncoder.write(image(destination), to: root.appendingPathComponent("missing/out.webp"),
                quality: 0.92, lossless: true)
            preconditionFailure("Unwritable destination accepted")
        } catch is CocoaError {}
        try expect(try Data(contentsOf: destination) == original)
    }

    static func expect(_ condition: @autoclosure () throws -> Bool) throws {
        let passed = try condition()
        precondition(passed)
    }

    static func image(_ url: URL) throws -> CGImage {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
            let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else { throw CaptureRasterError.invalidTile }
        return image
    }

    static func rgba(_ image: CGImage) throws -> [UInt8] {
        guard let context = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8,
            bytesPerRow: image.width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue), let data = context.data
        else { throw CaptureRasterError.invalidSize }
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return Array(UnsafeBufferPointer(start: data.assumingMemoryBound(to: UInt8.self), count: image.width * image.height * 4))
    }

    static func chunk(_ name: String, in data: Data) throws -> Data {
        var offset = 12
        while offset + 8 <= data.count {
            let size = (0..<4).reduce(0) { $0 | Int(data[offset + 4 + $1]) << ($1 * 8) }
            guard size <= data.count - offset - 8 else { throw CaptureRasterError.invalidTile }
            if data[offset..<offset + 4] == Data(name.utf8) { return data.subdata(in: offset + 8..<offset + 8 + size) }
            offset += 8 + size + size % 2
        }
        throw CaptureRasterError.invalidTile
    }
}
