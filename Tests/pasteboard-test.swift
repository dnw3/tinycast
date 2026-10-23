// Standalone test for clipboard capture and paste, compiling the real sources rather than copies.
// Every case drives `NSPasteboard.withUniqueName()`: writing to `.general` would land in the
// reader's own running Tinycast as a genuine copy.
import AppKit
import ImageIO

@main
@MainActor
struct PasteboardTests {
    static var failures = 0
    static var passes = 0
    static let cap = ClipboardManager.maxCapturedFiles

    static func main() async throws {
        finderCopyReadsAsAFileNotItsName()
        everyFileFlavourIsRead()
        multipleFilesReadNewestLast()
        linksAndTextAreNotFiles()
        volatileAndMissingFilesFallThrough()
        theBatchIsCapped()
        rejectedFilesDoNotCountTowardTheCap()
        theBoundedReaderStopsAtItsLimit()
        aModernFileURLSuppressesTheLegacyFallback()
        fileEntriesWriteBackAsFiles()
        aVanishedFileWritesNothing()
        try await captureRecordingRespectsSettings()
        try await pausedRecordingDiscardsLateImages()
        everyImageFlavourBecomesPNG()
        longTextFitsUnderTheCap()
        secretMarkersAreSkipped()
        richTextIsReadOnlyWithinTheCap()
        try await richEntriesPasteBothFlavours()
        imageEntriesWriteBackWithTheirFile()

        print("\(passes)/\(passes + failures) passed")
        if failures > 0 { exit(1) }
    }

    // MARK: - Reading
    /// One reader, every flavour: a board naming a file must never fall through to its name.
    static func everyFileFlavourIsRead() {
        withScratch { dir in
            let file = dir.appendingPathComponent("Tinycast-Settings-2026-08-20.json")
            try? Data("{}".utf8).write(to: file)

            // Finder's real shape: one item carrying the URL and the display name together.
            let item = NSPasteboardItem()
            item.setData(file.dataRepresentation, forType: .fileURL)
            item.setString(file.lastPathComponent, forType: .string)
            let single = board()
            single.writeObjects([item])
            expect(
                PasteboardFiles.urls(on: single) == [file],
                "a URL and a display name on one item reads as the file")

            // Some boards carry the URL as a string rather than as UTF-8 data.
            let asString = NSPasteboardItem()
            asString.setString(file.absoluteString, forType: .fileURL)
            let stringBoard = board()
            stringBoard.writeObjects([asString])
            expect(
                PasteboardFiles.urls(on: stringBoard) == [file],
                "and so does one carrying the URL as a string")

            // The pre-UTI flavour, still written by plenty of apps.
            let legacy = board()
            legacy.declareTypes([.init("NSFilenamesPboardType")], owner: nil)
            legacy.setPropertyList([file.path], forType: .init("NSFilenamesPboardType"))
            expect(
                PasteboardFiles.urls(on: legacy) == [file],
                "the legacy filenames flavour is read when no file URL is present")

            let text = board()
            text.declareTypes([.string], owner: nil)
            text.setString("Tinycast-Settings-2026-08-20.json", forType: .string)
            expect(
                PasteboardFiles.urls(on: text).isEmpty,
                "a bare file name is text, not a file")
        }
    }

    /// The reported bug: Finder puts the display name on `.string` beside `public.file-url`.
    static func finderCopyReadsAsAFileNotItsName() {
        withScratch { dir in
            let file = dir.appendingPathComponent("Screen Recording.mov")
            try? Data("movie".utf8).write(to: file)
            let pb = board()
            pb.declareTypes([.fileURL, .string], owner: nil)
            pb.setData(file.dataRepresentation, forType: .fileURL)
            pb.setString("Screen Recording.mov", forType: .string)

            expect(
                ClipboardManager.fileURLs(on: pb, volatileRoots: []) == [file.path],
                "a Finder copy reads as its path, never as its name")
        }
    }

    static func multipleFilesReadNewestLast() {
        withScratch { dir in
            let urls = ["a.txt", "b.txt", "c.txt"].map { name -> URL in
                let url = dir.appendingPathComponent(name)
                try? Data(name.utf8).write(to: url)
                return url
            }
            let pb = board()
            pb.writeObjects(urls as [NSURL])
            // Reversed, so inserting in order leaves the first file copied leading the history.
            expect(
                ClipboardManager.fileURLs(on: pb, volatileRoots: []) == urls.map(\.path).reversed(),
                "three files read back reversed")
        }
    }

    /// Only a real file URL counts, so a copied link stays a link.
    static func linksAndTextAreNotFiles() {
        let pb = board()
        pb.declareTypes([.string], owner: nil)
        pb.setString("https://example.com/report.pdf", forType: .string)
        expect(ClipboardManager.fileURLs(on: pb) == nil, "an http URL is not a file")

        let plain = board()
        plain.declareTypes([.string], owner: nil)
        plain.setString("just some prose", forType: .string)
        expect(ClipboardManager.fileURLs(on: plain) == nil, "and neither is prose")

        expect(ClipboardManager.fileURLs(on: board()) == nil, "an empty pasteboard reads as nil")
    }

    /// An app that stages a temp file beside better inline content must keep the inline content.
    static func volatileAndMissingFilesFallThrough() {
        let temp = URL(fileURLWithPath: "/private/tmp/tinycast-volatile-\(UUID().uuidString).png")
        try? Data("x".utf8).write(to: temp)
        defer { try? FileManager.default.removeItem(at: temp) }
        let pb = board()
        pb.writeObjects([temp as NSURL])
        expect(
            ClipboardManager.fileURLs(on: pb) == nil,
            "a file under /private/tmp is not durable, against the shipped roots")

        let gone = board()
        gone.writeObjects([URL(fileURLWithPath: "/nowhere/\(UUID().uuidString).txt") as NSURL])
        expect(ClipboardManager.fileURLs(on: gone) == nil, "and neither is one that is not there")
    }

    static func theBatchIsCapped() {
        withScratch { dir in
            let urls = (0..<40).map { index -> URL in
                let url = dir.appendingPathComponent("f\(index).txt")
                try? Data("x".utf8).write(to: url)
                return url
            }
            for legacy in [false, true] {
                for count in [1, cap - 1, cap, cap + 1, 40] {
                    let pb = fileBoard(Array(urls.prefix(count)), legacy: legacy)
                    defer { pb.releaseGlobally() }
                    expect(
                        ClipboardManager.fileURLs(on: pb, volatileRoots: [])
                            == Array(urls.prefix(min(count, cap)).map(\.path).reversed()),
                        "the first durable files stay reversed at the \(count)-file boundary (legacy: \(legacy))"
                    )
                }
            }
        }
    }

    static func rejectedFilesDoNotCountTowardTheCap() {
        withScratch { dir in
            let volatile = dir.appendingPathComponent("volatile", isDirectory: true)
            let staged = volatile.appendingPathComponent("staged.txt")
            let missing = dir.appendingPathComponent("missing.txt")
            let durableLink = dir.appendingPathComponent("durable-link")
            let volatileLink = dir.appendingPathComponent("volatile-link")
            let brokenLink = dir.appendingPathComponent("broken-link")
            let files = (0..<40).map { dir.appendingPathComponent("f\($0).txt") }
            do {
                try FileManager.default.createDirectory(at: volatile, withIntermediateDirectories: true)
                try Data("staged".utf8).write(to: staged)
                for file in files { try Data("file".utf8).write(to: file) }
                try FileManager.default.createSymbolicLink(at: durableLink, withDestinationURL: files[0])
                try FileManager.default.createSymbolicLink(at: volatileLink, withDestinationURL: staged)
                try FileManager.default.createSymbolicLink(at: brokenLink, withDestinationURL: missing)
            } catch {
                fail("cannot create file capture fixtures: \(error)")
                return
            }
            var root = volatile.resolvingSymlinksInPath().path
            if root.hasPrefix("/private/") { root.removeFirst("/private".count) }
            let rejected = [missing, staged, volatileLink, brokenLink]
            let accepted = [durableLink, files[0]] + files
            let mixed = Array(repeating: missing, count: 40) + rejected + accepted
            for legacy in [false, true] {
                let empty = fileBoard(rejected, legacy: legacy)
                defer { empty.releaseGlobally() }
                expect(
                    ClipboardManager.fileURLs(on: empty, volatileRoots: [root + "/"]) == nil,
                    "missing, volatile and broken targets fall through (legacy: \(legacy))")
                let pb = fileBoard(mixed, legacy: legacy)
                defer { pb.releaseGlobally() }
                expect(
                    ClipboardManager.fileURLs(on: pb, volatileRoots: [root + "/"])
                        == Array(accepted.prefix(cap).map(\.standardizedFileURL.path).reversed()),
                    "rejected files do not consume the cap; links and duplicates keep their order (legacy: \(legacy))"
                )
            }
        }
    }

    /// Bounding lives in the reader now, so both the limit and the predicate must stop exactly.
    static func theBoundedReaderStopsAtItsLimit() {
        let urls = (0..<100).map { URL(fileURLWithPath: "/fixture/\($0).txt") }
        let pb = fileBoard(urls, legacy: false)
        defer { pb.releaseGlobally() }
        expect(PasteboardFiles.urls(on: pb) == urls, "the attachment reader stays uncapped")
        for limit in [-1, 0, 1, cap - 1, cap, cap + 1, 100, Int.max] {
            var visited: [URL] = []
            let matched = PasteboardFiles.urls(on: pb, limit: limit) { url in
                visited.append(url)
                return true
            }
            let expected = Array(urls.prefix(max(0, limit)))
            expect(matched == expected, "a limit of \(limit) bounds the result in board order")
            expect(visited == expected, "and nothing is decoded past a limit of \(limit)")
        }
        var visited: [URL] = []
        let afterRejections = PasteboardFiles.urls(on: pb, limit: cap) { url in
            visited.append(url)
            return visited.count > 40
        }
        expect(
            afterRejections == Array(urls[40..<(40 + cap)]),
            "rejected URLs do not consume the limit")
        expect(
            visited == Array(urls.prefix(40 + cap)),
            "and every URL is tested once, with testing stopping at the limit")
    }

    /// A board naming a file in the modern flavour must never fall back, even when we reject it.
    static func aModernFileURLSuppressesTheLegacyFallback() {
        withScratch { dir in
            let legacy = dir.appendingPathComponent("legacy.txt")
            let modern = dir.appendingPathComponent("modern.txt")
            let missing = dir.appendingPathComponent("missing.txt")
            try? Data("legacy".utf8).write(to: legacy)
            try? Data("modern".utf8).write(to: modern)
            for url in [modern, missing, URL(string: "https://example.com/file")!] {
                let type = NSPasteboard.PasteboardType("NSFilenamesPboardType")
                let pb = board()
                defer { pb.releaseGlobally() }
                pb.declareTypes([type, .fileURL], owner: nil)
                pb.setPropertyList([legacy.path], forType: type)
                pb.setData(url.dataRepresentation, forType: .fileURL)

                let named = url.isFileURL ? [url] : [legacy]
                expect(
                    PasteboardFiles.urls(on: pb) == named,
                    "a modern file URL outranks the legacy paths beside it")
                var visited: [URL] = []
                let rejected = PasteboardFiles.urls(on: pb, limit: cap) { candidate in
                    visited.append(candidate)
                    return false
                }
                expect(rejected.isEmpty, "rejecting every candidate names no file")
                expect(visited == named, "and a rejected modern URL still suppresses the fallback")
                expect(
                    ClipboardManager.fileURLs(on: pb, volatileRoots: [])
                        == (url == missing ? nil : named.map(\.path)),
                    "so a missing modern file never captures the legacy path instead")
            }
        }
    }

    static func fileBoard(_ urls: [URL], legacy: Bool) -> NSPasteboard {
        let pb = board()
        if legacy {
            let type = NSPasteboard.PasteboardType("NSFilenamesPboardType")
            pb.declareTypes([type], owner: nil)
            expect(pb.setPropertyList(urls.map(\.path), forType: type), "legacy fixture is written")
        } else {
            expect(pb.writeObjects(urls as [NSURL]), "file URL fixture is written")
        }
        return pb
    }

    // MARK: - Writing

    /// The round trip: what Finder handed us goes back out as a file, plus the path as text.
    static func fileEntriesWriteBackAsFiles() {
        withScratch { dir in
            let file = dir.appendingPathComponent("report.pdf")
            try? Data("pdf".utf8).write(to: file)
            let store = ClipboardStore(directory: dir.appendingPathComponent("store"))
            store.addFiles([file.path], sourceBundleID: nil)
            let pb = board()

            expect(Paster.write(store.items[0], store: store, to: pb), "a present file writes")
            let read = pb.readObjects(forClasses: [NSURL.self]) as? [URL]
            expect(read?.first?.path == file.path, "and reads back as the same file URL")
            expect(pb.string(forType: .string) == file.path, "with the path as text, not the name")
            expect(
                pb.types?.contains(ClipboardManager.internalType) == true,
                "marked, so the poller skips our own write")
        }
    }

    static func aVanishedFileWritesNothing() {
        withScratch { dir in
            let store = ClipboardStore(directory: dir.appendingPathComponent("store"))
            store.addFiles(["/nowhere/\(UUID().uuidString).txt"], sourceBundleID: nil)
            let pb = board()
            pb.declareTypes([.string], owner: nil)
            pb.setString("untouched", forType: .string)

            expect(!Paster.write(store.items[0], store: store, to: pb), "a vanished file refuses")
            expect(pb.string(forType: .string) == "untouched", "and leaves the pasteboard alone")
        }
    }

    static func captureRecordingRespectsSettings() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "capture-pasteboard-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        do {
            let store = ClipboardStore(directory: directory.appendingPathComponent("capture"))
            let settings = AppSettings()
            let manager = ClipboardManager(store: store, settings: settings)
            let image = NSBitmapImageRep(
                bitmapDataPlanes: nil, pixelsWide: 12, pixelsHigh: 12, bitsPerSample: 8, samplesPerPixel: 4,
                hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 48, bitsPerPixel: 32
            )!
            memset(image.bitmapData!, 255, 576)
            let data = image.representation(using: .png, properties: [:])!
            manager.recordCapture(data, sourceBundleID: "fixture")
            expect(store.items.isEmpty, "stopped capture never records")
            manager.start()
            defer { manager.stop() }
            settings.clipboardEnabled = false
            manager.recordCapture(data, sourceBundleID: "fixture")
            expect(store.items.isEmpty, "disabled history never records a Capture result")
            settings.clipboardEnabled = true
            settings.clipboardDisabledApps = ["fixture"]
            manager.recordCapture(data, sourceBundleID: "fixture")
            expect(store.items.isEmpty, "excluded source never records a Capture result")
            settings.clipboardDisabledApps = []
            manager.recordCapture(data, sourceBundleID: "fixture")
            manager.stop()
            for _ in 0..<200 where store.items.isEmpty { try await Task.sleep(for: .milliseconds(10)) }
            expect(
                store.items.count == 1 && store.items[0].kind == .image, "only the final image enters history"
            )
        }
    }

    /// A pause landing while the PNG is written must drop the row and the blob alike.
    static func pausedRecordingDiscardsLateImages() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "capture-paused-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ClipboardStore(directory: directory)
        let manager = ClipboardManager(store: store, settings: AppSettings())
        manager.start()
        defer { manager.stop() }
        let data = Data(pngSignature + [1, 2, 3])

        manager.setRecordingPaused(true)
        expect(manager.isRecordingPaused, "the pause is reported")
        manager.recordCapture(data, sourceBundleID: nil)
        try await Task.sleep(for: .milliseconds(200))
        expect(store.items.isEmpty, "a paused history records nothing")

        manager.setRecordingPaused(false)
        manager.recordCapture(data, sourceBundleID: nil)
        manager.setRecordingPaused(true)
        try await Task.sleep(for: .milliseconds(300))
        let blobs = (try? FileManager.default.contentsOfDirectory(atPath: store.imagesDir.path)) ?? []
        expect(store.items.isEmpty, "a pause during the write keeps the row out")
        expect(blobs.isEmpty, "and deletes the blob it would have stranded")
    }

    static let pngSignature: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]

    static func everyImageFlavourBecomesPNG() {
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: 8, pixelsHigh: 8, bitsPerSample: 8, samplesPerPixel: 4,
            hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 32, bitsPerPixel: 32)!
        memset(rep.bitmapData!, 128, 256)
        let flavours: [(String, Data?)] = [
            ("TIFF", rep.tiffRepresentation),
            ("JPEG", rep.representation(using: .jpeg, properties: [:])),
            ("HEIC", heic(rep))
        ]
        for (name, data) in flavours {
            guard let data else {
                print("skip  \(name): this Mac cannot encode it")
                continue
            }
            let png = ClipboardManager.pngData(from: data)
            expect(png.map { Array($0.prefix(8)) == pngSignature } == true, "\(name) converts to PNG")
        }
        expect(ClipboardManager.pngData(from: Data("not an image".utf8)) == nil, "junk is refused")
        expect(
            ClipboardManager.imageTypes.contains(.init("public.heic"))
                && ClipboardManager.imageTypes.contains(.init("public.jpeg")),
            "the poller asks for JPEG and HEIC")
    }

    static func heic(_ rep: NSBitmapImageRep) -> Data? {
        let data = NSMutableData()
        guard let image = rep.cgImage,
            let destination = CGImageDestinationCreateWithData(
                data, "public.heic" as CFString, 1, nil)
        else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        return CGImageDestinationFinalize(destination) ? data as Data : nil
    }

    static func longTextFitsUnderTheCap() {
        let cap = ClipboardStore.maxTextLength
        expect(ClipboardStore.fitsTextLimit(String(repeating: "a", count: 40_000)), "40k is kept")
        expect(ClipboardStore.fitsTextLimit(String(repeating: "a", count: cap)), "the cap is kept")
        expect(!ClipboardStore.fitsTextLimit(String(repeating: "a", count: cap + 1)), "past it is not")
        expect(
            ClipboardStore.fitsTextLimit(String(repeating: "é", count: cap / 2 + 1)),
            "the cap counts characters, not UTF-8 bytes")
    }

    static func secretMarkersAreSkipped() {
        for type in [
            "org.nspasteboard.AutoGeneratedType", "de.petermaurer.TransientPasteboardType",
            "com.agilebits.onepassword", "com.typeit4me.clipping", "net.antelle.keeweb",
            "Pasteboard generator type"
        ] {
            expect(ClipboardManager.sensitiveTypes.contains(.init(type)), "\(type) is never recorded")
        }
    }

    static let rtf = Data(#"{\rtf1\ansi{\fonttbl\f0 Helvetica;}\f0\b bold\b0 text}"#.utf8)

    static func richTextIsReadOnlyWithinTheCap() {
        let rich = board()
        rich.declareTypes([.rtf, .string], owner: nil)
        rich.setData(rtf, forType: .rtf)
        rich.setString("bold text", forType: .string)
        expect(ClipboardManager.richText(on: rich) == rtf, "RTF beside the text is read")

        let plain = board()
        plain.declareTypes([.string], owner: nil)
        plain.setString("bold text", forType: .string)
        expect(ClipboardManager.richText(on: plain) == nil, "plain text carries no RTF")

        let html = board()
        html.declareTypes([.html, .string], owner: nil)
        html.setString("<b>bold</b>", forType: .html)
        html.setString("bold", forType: .string)
        expect(ClipboardManager.richText(on: html) == nil, "HTML is never taken for rich text")

        let huge = board()
        huge.declareTypes([.rtf, .string], owner: nil)
        huge.setData(Data(count: ClipboardStore.maxRichTextBytes + 1), forType: .rtf)
        huge.setString("huge", forType: .string)
        expect(ClipboardManager.richText(on: huge) == nil, "oversized RTF is skipped")
        expect(huge.string(forType: .string) == "huge", "while its text is still there to record")
    }

    /// Paste declares RTF and text together; Paste as Plain Text writes the text alone.
    static func richEntriesPasteBothFlavours() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "rich-paste-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ClipboardStore(directory: directory)
        store.addText("bold text", richText: rtf, sourceBundleID: nil)
        let captured = store.items[0]
        for _ in 0..<200 where store.items.first?.hasRichText != true {
            try await Task.sleep(for: .milliseconds(10))
        }

        let pasted = board()
        expect(Paster.write(captured, store: store, to: pasted), "a rich entry writes")
        let types = pasted.types ?? []
        expect(types.contains(.rtf) && types.contains(.string), "as RTF and text together")
        expect(types.contains(ClipboardManager.internalType), "stamped so it is not re-captured")
        expect(pasted.data(forType: .rtf) == rtf, "carrying the stored RTF")
        expect(pasted.string(forType: .string) == "bold text", "and the plain text beside it")

        let plain = board()
        expect(Paster.writePlainText(store.items[0], to: plain), "plain paste writes")
        expect(!(plain.types ?? []).contains(.rtf), "without the RTF")
        expect(plain.string(forType: .string) == "bold text", "only the text")

        try? FileManager.default.removeItem(atPath: store.items[0].richTextPath ?? "")
        let fallback = board()
        expect(Paster.write(store.items[0], store: store, to: fallback), "a lost sidecar still pastes")
        expect(fallback.types?.contains(.rtf) == false, "as text alone")
    }

    /// A text-only receiver ignores image data, so the stored file goes out beside it.
    static func imageEntriesWriteBackWithTheirFile() {
        withScratch { dir in
            let image = dir.appendingPathComponent("shot.png")
            let bytes = Data("png".utf8)
            try? bytes.write(to: image)
            let store = ClipboardStore(directory: dir.appendingPathComponent("store"))
            store.importEntries([ClipboardItem(imagePath: image.path, sourceBundleID: nil)])
            let pb = board()

            expect(Paster.write(store.items[0], store: store, to: pb), "a present image writes")
            expect(pb.data(forType: .png) == bytes, "as its image data")
            let read = pb.readObjects(forClasses: [NSURL.self]) as? [URL]
            expect(read?.first?.path == image.path, "and as its stored file")
            expect(
                pb.string(forType: .string) == nil,
                "but not as text, which a rich text field would take over the image")
            expect(
                pb.types?.contains(ClipboardManager.internalType) == true,
                "marked, so the poller skips our own write")
        }
    }

    // MARK: - Harness

    static func board() -> NSPasteboard { NSPasteboard.withUniqueName() }

    static func withScratch(_ body: (URL) -> Void) {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("tinycast-pasteboard-test-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        body(dir)
    }

    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        if condition() {
            passes += 1
        } else {
            fail(message)
        }
    }

    static func fail(_ message: String) {
        failures += 1
        print("FAIL: \(message)")
    }
}

// MARK: - Stubs for what the shipped sources reach that this harness does not exercise

@MainActor
final class AppSettings {
    var clipboardEnabled = true
    var clipboardDisabledApps: Set<String> = []
}

enum Permissions {
    static func ensureAccessibility() -> Bool { false }
}

final class NotificationToken {
    init(_ observer: Any, center: NotificationCenter) {}
}
