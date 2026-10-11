import Foundation

@main
struct CaptureQuickSaveTests {
    static func main() async throws {
        let files = FileManager.default
        let root = files.temporaryDirectory.appendingPathComponent("capture-quick-save-\(UUID())")
        defer { try? files.removeItem(at: root) }
        let directory = root.appendingPathComponent("output")
        let now = Date(timeIntervalSince1970: 0), id = UUID()
        let first = try CaptureQuickSave(directory: directory, createDirectory: true, format: .png, now: now, id: id)
        let size = try CapturePixelSize(width: 32, height: 16)
        let raster = UUID().uuidString
        try CaptureRasterStore.write(size: size, to: root.appendingPathComponent(raster), fillRow: CaptureFixture.fill)
        var document = CaptureDocument(id: UUID(), createdAt: now, size: size,
            pieces: [.init(raster: raster, source: CGRect(x: 0, y: 0, width: 32, height: 16), origin: .zero)])
        document.edit.annotations = [.init(id: UUID(), tool: .cover,
            points: [.zero, CGPoint(x: 32, y: 16)])]
        try CaptureRenderer.export(document: document, directory: root, to: first.staging, options: .init())
        try first.publish()
        precondition(!files.fileExists(atPath: first.staging.path))
        try CaptureFixture.verifyPNG(at: first.destination, size: size) { _, buffer in
            let bytes = buffer.bindMemory(to: UInt8.self)
            for index in bytes.indices { bytes[index] = index % 4 == 3 ? 255 : 0 }
        }
        let original = try Data(contentsOf: first.destination)
        let collision = try CaptureQuickSave(directory: directory, createDirectory: false, format: .png, now: now, id: id)
        try Data("replacement".utf8).write(to: collision.staging)
        do {
            try collision.publish()
            preconditionFailure("Existing output must survive a collision")
        } catch { precondition(error is POSIXError) }
        collision.discard()
        let preserved = try Data(contentsOf: first.destination)
        precondition(preserved == original)
        precondition(!files.fileExists(atPath: collision.staging.path))

        let second = try CaptureQuickSave(directory: directory, createDirectory: false, format: .png, now: now)
        try original.write(to: second.staging)
        try second.publish()
        precondition(second.destination != first.destination)
        try CaptureFixture.verifyPNG(at: second.destination, size: size) { _, buffer in
            let bytes = buffer.bindMemory(to: UInt8.self)
            for index in bytes.indices { bytes[index] = index % 4 == 3 ? 255 : 0 }
        }

        let cancelled = try CaptureQuickSave(directory: directory, createDirectory: false, format: .png, now: now)
        try original.write(to: cancelled.staging)
        await Task {
            withUnsafeCurrentTask { $0?.cancel() }
            do {
                try cancelled.publish()
                preconditionFailure("Cancelled save must not publish")
            } catch { precondition(error is CancellationError) }
            cancelled.discard()
        }.value
        precondition(!files.fileExists(atPath: cancelled.staging.path))
        precondition(!files.fileExists(atPath: cancelled.destination.path))
        let missing = root.appendingPathComponent("missing")
        do {
            _ = try CaptureQuickSave(directory: missing, createDirectory: false, format: .png, now: now)
            preconditionFailure("A missing chosen folder must fail")
        } catch { precondition(!files.fileExists(atPath: missing.path)) }
        do {
            _ = try CaptureQuickSave(directory: first.destination, createDirectory: false, format: .png, now: now)
            preconditionFailure("A regular file is not a destination folder")
        } catch {}
        let remaining = try files.contentsOfDirectory(atPath: directory.path)
        precondition(remaining.count == 2 && !remaining.contains { $0.hasPrefix(".") })
        print("Quick save: decoded redaction, repeat, collision, cancellation and folder errors passed")
    }
}
