import Darwin
import Foundation
import ImageIO
import UniformTypeIdentifiers

struct CaptureRepository: Sendable {
    let root: URL
    var sessions: URL { root.appendingPathComponent("sessions", isDirectory: true) }
    var history: URL { root.appendingPathComponent("history", isDirectory: true) }
    var diagnostics: URL { root.appendingPathComponent("diagnostics", isDirectory: true) }

    /// Diagnostic recordings are screen contents kept only to be replayed: a few, for a few days.
    static let diagnosticsKept = 3
    static let diagnosticsDays = 3

    func create(id: UUID) throws -> URL {
        try reclaimAbandonedSessions(before: Date().addingTimeInterval(-86_400))
        try reclaimDiagnostics(now: Date(), keeping: Self.diagnosticsKept)
        let directory = sessions.appendingPathComponent(id.uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700])
        return directory
    }

    /// Recordings older than `diagnosticsDays`, and all but the newest `keeping`, by last write.
    func reclaimDiagnostics(now: Date, keeping: Int) throws {
        let files = FileManager.default
        guard files.fileExists(atPath: diagnostics.path) else { return }
        let recordings = try files.contentsOfDirectory(
            at: diagnostics, includingPropertiesForKeys: [.contentModificationDateKey, .isSymbolicLinkKey])
            .compactMap { directory -> (URL, Date)? in
                let values = try? directory.resourceValues(forKeys: [.contentModificationDateKey, .isSymbolicLinkKey])
                guard directory.lastPathComponent.hasPrefix("scroll-"), values?.isSymbolicLink != true,
                    let date = values?.contentModificationDate
                else { return nil }
                return (directory, date)
            }
            .sorted { $0.1 > $1.1 }
        let cutoff = now.addingTimeInterval(-Double(Self.diagnosticsDays) * 86_400)
        for (index, recording) in recordings.enumerated() where index >= keeping || recording.1 < cutoff {
            try files.removeItem(at: recording.0)
        }
    }

    func reclaimAbandonedSessions(before cutoff: Date) throws {
        let files = FileManager.default
        guard files.fileExists(atPath: sessions.path) else { return }
        for directory in try files.contentsOfDirectory(
            at: sessions, includingPropertiesForKeys: [.contentModificationDateKey, .isSymbolicLinkKey])
        where UUID(uuidString: directory.lastPathComponent) != nil {
            let values = try directory.resourceValues(forKeys: [
                .contentModificationDateKey, .isSymbolicLinkKey
            ])
            guard values.isSymbolicLink != true, let date = values.contentModificationDate, date < cutoff
            else { continue }
            let descriptor = Darwin.open(
                directory.appendingPathComponent(".lease").path, O_RDWR | O_CREAT | O_CLOEXEC | O_NOFOLLOW,
                0o600)
            guard descriptor >= 0 else { continue }
            defer { Darwin.close(descriptor) }
            guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else { continue }
            try files.removeItem(at: directory)
        }
    }

    func entries() throws -> [CaptureHistoryEntry] {
        guard FileManager.default.fileExists(atPath: history.path) else { return [] }
        return try FileManager.default.contentsOfDirectory(at: history, includingPropertiesForKeys: nil)
            .filter { UUID(uuidString: $0.lastPathComponent) != nil }
            .compactMap { directory in
                guard
                    let data = try? limitedData(
                        directory.appendingPathComponent("entry.json"), maximum: 4096),
                    let entry = try? JSONDecoder().decode(CaptureHistoryEntry.self, from: data),
                    entry.id.uuidString == directory.lastPathComponent, entry.bytes >= 0,
                    entry.bytes <= 2_100_000_000, entry.date.timeIntervalSince1970.isFinite,
                    entry.videoDuration.map({ $0.isFinite && $0 > 0 && $0 <= 28_800 }) ?? true,
                    entry.animationDuration.map({ $0.isFinite && $0 > 0 && $0 <= 30 }) ?? true,
                    entry.videoDuration == nil || entry.animationDuration == nil
                else { return nil }
                return entry
            }.sorted { $0.date > $1.date }
    }

    @discardableResult
    func commit(document: CaptureDocument, directory: URL, png: URL, editable: Bool, draft: Bool) throws -> CaptureHistoryEntry {
        _ = try document.validated()
        let files = FileManager.default
        try files.createDirectory(
            at: history, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let id = UUID()
        let temporary = history.appendingPathComponent(".\(id)", isDirectory: true)
        try files.createDirectory(
            at: temporary, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        defer { try? files.removeItem(at: temporary) }
        try files.copyItem(at: png, to: temporary.appendingPathComponent("image.png"))
        if editable || draft {
            let sources = temporary.appendingPathComponent("source")
            try files.createDirectory(
                at: sources, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
            let archived = try CaptureSourceArchive.copy(document: document, from: directory, to: sources)
            try JSONEncoder().encode(archived).write(
                to: temporary.appendingPathComponent("document.json"), options: .atomic)
        }
        let preview = try CaptureRenderer.preview(document: document, directory: directory, maximum: 256)
        guard
            let destination = CGImageDestinationCreateWithURL(
                temporary.appendingPathComponent("thumbnail.png") as CFURL, UTType.png.identifier as CFString,
                1, nil)
        else { throw CaptureRasterError.invalidTile }
        CGImageDestinationAddImage(destination, preview, nil)
        guard CGImageDestinationFinalize(destination) else { throw CaptureRasterError.invalidTile }
        let size = try CapturePixelSize(
            width: Int(document.outputBounds.width), height: Int(document.outputBounds.height))
        let entry = CaptureHistoryEntry(
            id: id, date: Date(), size: size, editable: editable || draft,
            draft: draft, bytes: try diskBytes(temporary))
        try JSONEncoder().encode(entry).write(
            to: temporary.appendingPathComponent("entry.json"), options: .atomic)
        try files.moveItem(at: temporary, to: history.appendingPathComponent(id.uuidString))
        return entry
    }

    func prune(now: Date, days: Int, maximumBytes: Int) throws {
        var keptBytes = 0
        for entry in try entries() {
            keptBytes += entry.bytes
            if !entry.draft
                && (now.timeIntervalSince(entry.date) > Double(days) * 86400 || keptBytes > maximumBytes)
            {
                try FileManager.default.removeItem(at: history.appendingPathComponent(entry.id.uuidString))
                keptBytes -= entry.bytes
            }
        }
    }

    struct VideoDraft: Sendable {
        let original: URL
        let duration: Double
        let edit: CaptureVideoEdit
    }

    @discardableResult
    func commitVideo(
        _ url: URL, info: CaptureVideoService.Info, preview: CGImage, draft: VideoDraft? = nil
    ) throws -> CaptureHistoryEntry {
        guard info.duration.isFinite, info.duration > 0, info.duration <= 28_800
        else { throw CaptureVideoError.invalidMedia }
        if let draft {
            _ = try draft.edit.validated(duration: draft.duration)
            guard abs(draft.edit.duration - info.duration) < 0.1 else { throw CaptureVideoError.invalidMedia }
        }
        return try commitMedia(url, size: info.size, duration: info.duration, animation: false, preview: preview, draft: draft)
    }

    @discardableResult
    func commitGIF(_ url: URL) throws -> CaptureHistoryEntry {
        let info = try CaptureGIFService.inspect(url)
        return try commitMedia(url, size: info.size, duration: info.duration, animation: true, preview: info.preview)
    }

    private func commitMedia(
        _ url: URL, size: CapturePixelSize, duration: Double, animation: Bool, preview: CGImage, draft: VideoDraft? = nil
    ) throws -> CaptureHistoryEntry {
        try validateFile(url)
        let files = FileManager.default, id = UUID()
        try files.createDirectory(at: history, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let temporary = history.appendingPathComponent(".\(id)", isDirectory: true)
        try files.createDirectory(at: temporary, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        defer { try? files.removeItem(at: temporary) }
        let filename = animation ? "animation.gif" : "video.mp4"
        try files.copyItem(at: url, to: temporary.appendingPathComponent(filename))
        if let draft {
            try validateFile(draft.original)
            try files.copyItem(at: draft.original, to: temporary.appendingPathComponent("original.mp4"))
            try JSONEncoder().encode(draft.edit).write(to: temporary.appendingPathComponent("video-edit.json"), options: .atomic)
        }
        guard let destination = CGImageDestinationCreateWithURL(
            temporary.appendingPathComponent("thumbnail.png") as CFURL, UTType.png.identifier as CFString, 1, nil)
        else { throw CaptureVideoError.invalidMedia }
        CGImageDestinationAddImage(destination, preview, nil)
        guard CGImageDestinationFinalize(destination) else { throw CaptureVideoError.invalidMedia }
        let bytes = try diskBytes(temporary)
        guard bytes <= 2_100_000_000 else { throw CaptureVideoError.invalidMedia }
        let entry = CaptureHistoryEntry(id: id, date: Date(), size: size, editable: draft != nil, draft: draft != nil,
            bytes: bytes, videoDuration: animation ? nil : duration,
            animationDuration: animation ? duration : nil)
        try JSONEncoder().encode(entry).write(to: temporary.appendingPathComponent("entry.json"), options: .atomic)
        try Task.checkCancellation()
        try files.moveItem(at: temporary, to: history.appendingPathComponent(id.uuidString))
        return entry
    }

    func openFile(_ entry: CaptureHistoryEntry, id: UUID) throws -> CaptureSource {
        let file = history.appendingPathComponent(entry.id.uuidString).appendingPathComponent(entry.filename)
        try validateFile(file)
        let source = try CaptureSource(directory: create(id: id))
        try FileManager.default.copyItem(at: file, to: source.directory.appendingPathComponent(entry.filename))
        try Task.checkCancellation()
        return source
    }

    func openVideo(_ entry: CaptureHistoryEntry, id: UUID) throws -> (CaptureSource, CaptureVideoEdit?) {
        let source = try openFile(entry, id: id)
        guard entry.draft, entry.videoDuration != nil else { return (source, nil) }
        let directory = history.appendingPathComponent(entry.id.uuidString)
        let edit = try JSONDecoder().decode(CaptureVideoEdit.self,
            from: limitedData(directory.appendingPathComponent("video-edit.json"), maximum: 512_000))
        let original = directory.appendingPathComponent("original.mp4")
        try validateFile(original)
        try FileManager.default.copyItem(at: original, to: source.directory.appendingPathComponent("original.mp4"))
        try Task.checkCancellation()
        return (source, edit)
    }

    func transfer(_ entry: CaptureHistoryEntry, now: Date, keeping urls: Set<URL>) throws -> URL {
        let files = FileManager.default
        let file = history.appendingPathComponent(entry.id.uuidString).appendingPathComponent(entry.filename)
        try validateFile(file)
        let transfers = root.appendingPathComponent("transfers", isDirectory: true)
        try files.createDirectory(at: transfers, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        for directory in try files.contentsOfDirectory(at: transfers,
            includingPropertiesForKeys: [.contentModificationDateKey, .isSymbolicLinkKey])
        where UUID(uuidString: directory.lastPathComponent) != nil {
            let values = try directory.resourceValues(forKeys: [.contentModificationDateKey, .isSymbolicLinkKey])
            guard values.isSymbolicLink != true, let date = values.contentModificationDate,
                now.timeIntervalSince(date) > 86_400,
                !urls.contains(where: { $0.deletingLastPathComponent().standardizedFileURL == directory.standardizedFileURL })
            else { continue }
            try files.removeItem(at: directory)
        }
        let directory = transfers.appendingPathComponent(entry.id.uuidString, isDirectory: true)
        let destination = directory.appendingPathComponent(entry.filename)
        if files.fileExists(atPath: directory.path) {
            let values = try directory.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            guard values.isDirectory == true, values.isSymbolicLink != true else { throw CaptureVideoError.invalidMedia }
            try validateFile(destination)
            try files.setAttributes([.modificationDate: now], ofItemAtPath: directory.path)
            return destination
        }
        try files.createDirectory(at: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        do {
            try files.copyItem(at: file, to: destination)
            try Task.checkCancellation()
            return destination
        } catch {
            try? files.removeItem(at: directory)
            throw error
        }
    }

    private func validateFile(_ url: URL) throws {
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true,
            let bytes = values.fileSize, (1...2_100_000_000).contains(bytes)
        else { throw CaptureVideoError.invalidMedia }
    }

    func open(_ entry: CaptureHistoryEntry, id: UUID) throws -> (CaptureDocument, URL) {
        let source = history.appendingPathComponent(entry.id.uuidString)
        let directory = try create(id: id)
        do {
            if entry.editable,
                let data = try? limitedData(
                    source.appendingPathComponent("document.json"), maximum: 4_000_000),
                let original = try? JSONDecoder().decode(CaptureDocument.self, from: data).validated(),
                original.rasterRegions.allSatisfy({ piece in
                    guard
                        let raster = try? CaptureRasterStore.validate(
                            at: source.appendingPathComponent("source/\(piece.raster)"))
                    else { return false }
                    return CGRect(x: 0, y: 0, width: raster.size.width, height: raster.size.height)
                        .contains(piece.source)
                })
            {
                for raster in Set(original.rasterRegions.map(\.raster)) {
                    try FileManager.default.copyItem(
                        at: source.appendingPathComponent("source/\(raster)"),
                        to: directory.appendingPathComponent(raster))
                }
                var document = CaptureDocument(
                    id: id, createdAt: original.createdAt, size: original.size,
                    pieces: original.pieces, axis: original.axis, captureScale: original.captureScale)
                document.edit = original.edit
                return (document, directory)
            }
            let raster = UUID().uuidString
            let size = try CaptureImageSource.load(
                source.appendingPathComponent("image.png"),
                at: directory.appendingPathComponent(raster))
            let bounds = CGRect(x: 0, y: 0, width: size.width, height: size.height)
            return (
                CaptureDocument(
                    id: id, createdAt: entry.date, size: size,
                    pieces: [.init(raster: raster, source: bounds, origin: .zero)]), directory
            )
        } catch {
            try? FileManager.default.removeItem(at: directory)
            throw error
        }
    }

    private func diskBytes(_ url: URL) throws -> Int {
        guard
            let enumerator = FileManager.default.enumerator(
                at: url, includingPropertiesForKeys: [.fileSizeKey])
        else {
            throw CocoaError(.fileReadUnknown)
        }
        var bytes = 0
        for case let file as URL in enumerator {
            bytes += try file.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        }
        return bytes
    }

    private func limitedData(_ url: URL, maximum: Int) throws -> Data {
        let values = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true,
            let size = values.fileSize, (1...maximum).contains(size)
        else { throw CaptureRasterError.invalidTile }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let data = try handle.read(upToCount: maximum + 1) ?? Data()
        guard data.count <= maximum else { throw CaptureRasterError.invalidTile }
        return data
    }
}
