import CoreGraphics
import CoreText
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Scrolling capture end to end on rendered frames; `TINYCAST_SCROLL_REPLAY` replays a recording.
@main
struct CaptureScrollReplayTests {
    static func main() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("capture-scroll-replay-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        if let folder = ProcessInfo.processInfo.environment["TINYCAST_SCROLL_REPLAY"] {
            try replay(URL(fileURLWithPath: folder), in: root)
            return
        }
        let window = ChatWindow()
        // A flick in steps up to half the viewport, a pause, a faster run, and rest at the end.
        let tops = [0, 0, 40, 130, 280, 480, 480, 480, 720, 1_000, 1_380, 1_760, 2_140, 2_140, 2_520, 2_900, 2_900]
        let steady = [0, 0, 40, 130, 280, 480, 480, 720, 960, 1_200, 1_440, 1_440]
        let quick = [0, 0, 380, 760, 1_140, 1_520, 1_900, 1_900]
        if ProcessInfo.processInfo.environment["TINYCAST_SCROLL_GAPS"] != nil {
            try gaps(window, tops: [steady, quick], in: root)
            return
        }
        let stitched = try verify(window, tops.map { Shot(window, top: $0) }, in: root.appendingPathComponent("flick"))
        // A pointer mid-region hides most of a large step's overlap; the scroll events vouch for the rest.
        for (name, steps) in [("steady", steady), ("quick", quick)] {
            try verify(window, steps.map { Shot(window, top: $0, pointer: 600, travel: $0) }, in: root.appendingPathComponent(name))
        }
        let lit = quick.enumerated().map { Shot(window, top: $1, pointer: 600, travel: $1 + $0 % 2 * 50, hover: true) }
        try verify(window, lit, in: root.appendingPathComponent("hover"), comparesPixels: false)
        // Rendered glass passes either way; its tolerance was set on recorded AI Chat frames, kept local.
        try verify(window, tops.map { Shot(window, top: $0, glass: true) }, in: root.appendingPathComponent("glass"))
        // The window turns key a moment into the capture: nothing scrolled, so it is the same place.
        let turning = [0, 0, 0].map { Shot(window, top: $0, travel: 0, key: false) }
            + ([0, 0, 0] + tops.dropFirst(2)).map { Shot(window, top: $0, travel: $0) }
        try verify(window, turning, in: root.appendingPathComponent("key"), comparesPixels: false)
        // Started at the bottom and scrolled back: the frames turn over and the result grows at its start.
        let back = tops.map { 2_900 - $0 }
        let (_, backVerdicts) = try verify(window, back.map { Shot(window, top: $0, travel: $0) }, in: root.appendingPathComponent("back"))
        precondition(backVerdicts.contains { $0.hasPrefix("reversing") }, "Scrolling back turns the capture: \(backVerdicts)")
        try verify(window, back.map { Shot(window, top: $0, pointer: 600, travel: $0) }, in: root.appendingPathComponent("back-pointer"))
        // The seam moves off a line of text onto the blank between lines.
        func blank(_ retaken: Int) -> Bool {
            let row = window.pageRow(window.height - retaken - 1 - window.contentTop, columns: window.comparedColumns)
            return Set(stride(from: 0, to: row.count, by: 4).map { row[$0] }).count == 1
        }
        let inked = (200..<300).first { !blank($0) }!
        let extra = ScrollFrameReader.seam(
            previous: window.frame(top: 0, pointer: nil), current: window.frame(top: 280, pointer: nil), shift: 280,
            retaken: inked, axis: .vertical, atStart: false)
        precondition(
            extra > 0 && extra <= ScrollFrameReader.seamReach && blank(inked + extra),
            "A seam through text moves to a blank line: \(inked) + \(extra)")
        // Back well past what the last strip reaches, then on again: matching follows the reader both ways.
        let roundTrip = [0, 0, 300, 600, 900, 1_200, 1_200, 1_000, 800, 600, 400, 200, 200, 400, 600, 900, 1_200, 1_500, 1_500]
        try verify(window, roundTrip.map { Shot(window, top: $0, travel: $0) }, in: root.appendingPathComponent("round"))
        // A jump past the frame matched from lands within an earlier strip, which places it again.
        let jump = [0, 0, 300, 600, 900, 900, 100, 100, 400, 700, 1_000, 1_300, 1_300]
        let (_, jumpVerdicts) = try verify(window, jump.map { Shot(window, top: $0) }, in: root.appendingPathComponent("jump"))
        precondition(!jumpVerdicts.contains { $0.contains("lost") }, "\(jumpVerdicts)")
        // Past any overlap, the reader may go on and leave a gap, which is then plain to see.
        var tracker = ScrollTracker<Int>()
        for top in [0, 0] { _ = tracker.observe(try ScrollFrameReader.sample(window.frame(top: top, pointer: nil), axis: .vertical), payload: top, match: ScrollStitchPolicy.match) }
        let distant = try ScrollFrameReader.sample(window.frame(top: 2_000, pointer: nil), axis: .vertical)
        _ = tracker.observe(distant, payload: 2_000, match: ScrollStitchPolicy.match)
        let lost = tracker.observe(distant, payload: 2_000, match: ScrollStitchPolicy.match)
        precondition(lost.contains { if case .lost = $0 { true } else { false } }, "\(lost)")
        guard let bridged = tracker.bridge(distant, payload: 2_000), bridged.offset == window.height, bridged.trailing == 0
        else { preconditionFailure("Going on past a gap adds the frame whole after the result's end") }
        let after = tracker.observe(try ScrollFrameReader.sample(window.frame(top: 2_300, pointer: nil), axis: .vertical), payload: 2_300, match: ScrollStitchPolicy.match)
        precondition(!after.contains { if case .lost = $0 { true } else { false } } && tracker.pending?.offset == 300, "and matching goes on from it: \(after)")
        // A step past the overlap is lost, never taken at whatever shift fits a little.
        let far = [0, 0, 480, 480].map { Shot(window, top: $0, pointer: 600, travel: $0) }
        let (_, farVerdicts) = try verify(window, far, in: root.appendingPathComponent("far"), allowsLoss: true)
        precondition(!farVerdicts.contains { $0.hasPrefix("commit") && !$0.contains("whole") }, "\(farVerdicts)")
        // An app that scrolls at its own ratio to the events loses the second witness, never the seam.
        for ratio in [2.0, 0.5] {
            let scaled = { (top: Int) in Int(Double(top) * ratio) }
            try verify(window, steady.map { Shot(window, top: $0, travel: scaled($0)) }, in: root.appendingPathComponent("ratio\(ratio)"))
            try verify(
                window, steady.map { Shot(window, top: $0, pointer: 600, travel: scaled($0)) },
                in: root.appendingPathComponent("ratio-pointer\(ratio)"), allowsLoss: true)
        }
        precondition(
            ScrollStitchPolicy.agrees(250, expected: 320) && ScrollStitchPolicy.agrees(390, expected: 320)
                && !ScrollStitchPolicy.agrees(230, expected: 320) && !ScrollStitchPolicy.agrees(410, expected: 320)
                && ScrollStitchPolicy.agrees(-300, expected: -320) && !ScrollStitchPolicy.agrees(300, expected: -320)
                && ScrollStitchPolicy.agrees(20, expected: 0),
            "A confirmed shift lies within a quarter of what the events said, either way, and a little more")

        let recorder = try ScrollDiagnosticsRecorder.create(in: root, date: Date())
        for (index, top) in tops.enumerated() {
            try recorder.record(
                window.frame(top: top, pointer: nil), index: index + 1, pointer: index == 3 ? 42 : nil, travel: top,
                verdict: "")
        }
        precondition(ScrollDiagnosticsRecorder.marks(inFrameNamed: "00004_p42_t130.png") == (42, 130))
        precondition(ScrollDiagnosticsRecorder.marks(inFrameNamed: "00005_p-1.png") == (nil, nil))
        let replayed = try replay(recorder.directory, in: root.appendingPathComponent("replay"))
        precondition(replayed.size.height == stitched.document.size.height, "A recording replays as it was captured")
        let trace = try String(contentsOf: recorder.directory.appendingPathComponent("trace.tsv"), encoding: .utf8)
        precondition(
            FileManager.default.fileExists(atPath: recorder.directory.appendingPathComponent("replay.png").path)
                && trace.split(separator: "\n").count == tops.count,
            "and leaves its stitched result and one trace line per frame beside the frames")
        let repository = CaptureRepository(root: root.appendingPathComponent("repository"))
        for day in 0..<6 {
            let folder = repository.diagnostics.appendingPathComponent("scroll-\(day)")
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try FileManager.default.setAttributes(
                [.modificationDate: Date().addingTimeInterval(-Double(day) * 86_400 - 60)], ofItemAtPath: folder.path)
        }
        try FileManager.default.createDirectory(
            at: repository.diagnostics.appendingPathComponent("unrelated"), withIntermediateDirectories: true)
        _ = try repository.create(id: UUID())
        let kept = try FileManager.default.contentsOfDirectory(atPath: repository.diagnostics.path).sorted()
        precondition(
            kept == ["scroll-0", "scroll-1", "scroll-2", "unrelated"],
            "Recordings past three days, or past the newest three, go when a capture starts: \(kept)")
        try repository.reclaimDiagnostics(now: Date(), keeping: 1)
        let left = try FileManager.default.contentsOfDirectory(atPath: repository.diagnostics.path).sorted()
        precondition(left == ["scroll-0", "unrelated"], "and a new recording makes room for itself: \(left)")
        print("Scrolling replay of a chat window with sidebar, bars, fades, scroller, button and pointer passed")
    }

    /// One sampled frame and what the session knew alongside it.
    struct Shot {
        let image: CGImage
        let top: Int
        let pointer: Int?
        let travel: Int?

        init(
            _ window: ChatWindow, top: Int, pointer: Int? = nil, travel: Int? = nil, hover: Bool = false,
            glass: Bool = false, key: Bool = true
        ) {
            image = window.frame(top: top, pointer: hover ? pointer : nil, glass: glass, key: key)
            self.top = top
            self.pointer = pointer
            self.travel = travel
        }

        init(image: CGImage, pointer: Int?, travel: Int?) {
            self.image = image
            top = 0
            self.pointer = pointer
            self.travel = travel
        }
    }

    /// Without scroll events, a pointer mid-region still loses large steps; printed, not asserted.
    static func gaps(_ window: ChatWindow, tops: [[Int]], in root: URL) throws {
        for steps in tops {
            let directory = root.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let (document, verdicts) = try stitch(steps.map { Shot(window, top: $0, pointer: 600) }, in: directory)
            let right = document.size.height == window.height + steps.last!
            print(verdicts.contains { $0.contains("lost") } ? "LOST" : right ? "ok  " : "WRONG", document.size.height, steps, verdicts)
        }
    }

    /// Every frame lines up, and the stitched column is the page itself wherever nothing covers it.
    @discardableResult
    static func verify(
        _ window: ChatWindow, _ shots: [Shot], in directory: URL, comparesPixels: Bool = true, allowsLoss: Bool = false
    ) throws -> (document: CaptureDocument, verdicts: [String]) {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let (document, verdicts) = try stitch(shots, in: directory)
        if !allowsLoss {
            precondition(!verdicts.contains { $0.contains("lost") }, "A frame lost the overlap: \(verdicts)")
            let reach = shots.map(\.top).max()! - shots.map(\.top).min()!
            precondition(
                document.size.height == window.height + reach,
                "The capture grows by exactly the distance scrolled: \(document.size.height), \(verdicts)")
        }
        guard comparesPixels else { return (document, verdicts) }
        let composite = try CaptureCompositeReader(document: document, directory: directory)
        let columns = window.comparedColumns
        let width = columns.count * 4
        for row in (window.contentTop + window.fade)..<(document.size.height - window.height + window.contentBottom - window.fade) {
            let actual = try composite.read(rect: CGRect(x: columns.lowerBound, y: row, width: columns.count, height: 1))
            let expected = window.pageRow(shots.map(\.top).min()! + row - window.contentTop, columns: columns)
            precondition(actual.count == width && actual == expected, "Stitched row \(row) differs from the page, \(verdicts)")
        }
        return (document, verdicts)
    }

    static func stitch(_ shots: [Shot], in directory: URL) throws -> (CaptureDocument, [String]) {
        var tracker = ScrollTracker<CGImage>()
        var document: CaptureDocument?
        var verdicts: [String] = []
        var before: CGImage?
        func write(_ strip: ScrollTracker<CGImage>.Strip) throws {
            let size = try CapturePixelSize(width: strip.payload.width, height: strip.payload.height)
            let current = document ?? CaptureDocument(id: UUID(), createdAt: Date(), size: size, pieces: [], axis: .vertical)
            let raster = UUID().uuidString
            // As the session does: a seam moved between lines must not change a pixel of the result.
            let extra = before.flatMap { before in strip.offset.map { offset in
                ScrollFrameReader.seam(
                    previous: before, current: strip.payload, shift: offset, retaken: strip.trailing, axis: .vertical,
                    atStart: strip.reversed)
            } } ?? 0
            let plan = try CaptureScrollAppend.plan(
                document: current, frame: size, raster: raster, offset: strip.offset, trailing: strip.trailing + extra,
                atStart: strip.reversed)
            before = strip.payload
            try ScrollFrameReader.strip(strip.payload, rect: plan.source, to: directory.appendingPathComponent(raster))
            document = plan.document
        }
        for shot in shots {
            var frame = try ScrollFrameReader.sample(shot.image, axis: .vertical)
            frame.pointer = shot.pointer
            frame.travel = shot.travel
            let steps = tracker.observe(frame, payload: shot.image, match: ScrollStitchPolicy.match)
            for step in steps { if case .commit(let strip) = step { try write(strip) } }
            verdicts.append(steps.map { step in
                switch step {
                case .commit(let strip): "commit \(strip.offset.map(String.init) ?? "whole") trailing \(strip.trailing)"
                case .backward: "backward"
                case .lost: "lost"
                case .found: "found"
                case .reversing: "reversing"
                }
            }.joined(separator: " "))
        }
        if let strip = tracker.flush() { try write(strip) }
        guard let document else { preconditionFailure("Nothing was captured: \(verdicts)") }
        return (document, verdicts)
    }

    /// A recorded folder, replayed frame by frame; the stitched result is written beside the frames.
    @discardableResult
    static func replay(_ folder: URL, in root: URL) throws -> CaptureDocument {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let names = try FileManager.default.contentsOfDirectory(atPath: folder.path)
            .filter { $0.hasSuffix(".png") && $0 != "replay.png" }.sorted()
        let frames = names.compactMap { name -> Shot? in
            guard let source = CGImageSourceCreateWithURL(folder.appendingPathComponent(name) as CFURL, nil),
                let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
            else { return nil }
            let marks = ScrollDiagnosticsRecorder.marks(inFrameNamed: name)
            return Shot(image: image, pointer: marks.pointer, travel: marks.travel)
        }
        let (document, verdicts) = try stitch(frames, in: root)
        for (name, verdict) in zip(names, verdicts) where !verdict.isEmpty { print(name, verdict) }
        print("Stitched \(document.size.width) × \(document.size.height) from \(document.pieces.count) strips")
        let composite = try CaptureCompositeReader(document: document, directory: root)
        var pixels = Data()
        for row in stride(from: 0, to: document.size.height, by: 256) {
            pixels += try composite.read(rect: CGRect(
                x: 0, y: row, width: document.size.width, height: min(256, document.size.height - row)))
        }
        let image = CGImage(
            width: document.size.width, height: document.size.height, bitsPerComponent: 8, bitsPerPixel: 32,
            bytesPerRow: document.size.width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: CGDataProvider(data: pixels as CFData)!, decode: nil, shouldInterpolate: false,
            intent: .defaultIntent)!
        let destination = CGImageDestinationCreateWithURL(
            folder.appendingPathComponent("replay.png") as CFURL, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, image, nil)
        precondition(CGImageDestinationFinalize(destination))
        return document
    }
}

/// Like AI Chat: title bar, sidebar, composer, edge fades, overlay scroller and floating button.
struct ChatWindow {
    let width = 1_400, height = 1_000
    let sidebar = 340, contentTop = 100, contentBottom = 840, fade = 48
    let button = CGRect(x: 1_020, y: 720, width: 72, height: 72)
    let pageHeight = 4_400
    private let page: [UInt8]
    private let pageImage: CGImage
    private let background: (CGFloat, CGFloat, CGFloat) = (0.98, 0.98, 0.99)

    var contentWidth: Int { width - sidebar }
    /// The page column clear of the scroller and the floating button, where a strip is the page itself.
    var comparedColumns: Range<Int> { (sidebar + 8)..<(Int(button.minX) - 8) }

    init() {
        let context = ChatWindow.context(width: width - sidebar, height: pageHeight)
        context.setFillColor(red: 0.98, green: 0.98, blue: 0.99, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width - sidebar, height: pageHeight))
        let font = CTFontCreateWithName("Menlo" as CFString, 22, nil)
        let words = ["const", "snake", "direction", "=", "{", "x:", "1,", "y:", "0", "}", "function", "draw()",
            "ctx.fillRect(", "size", "+", "return;", "if", "(paused", "||", "ended)", "score", "+=", "10;", "//", "食物"]
        let colors: [CGColor] = [
            CGColor(red: 0.62, green: 0.13, blue: 0.48, alpha: 1), CGColor(red: 0.13, green: 0.36, blue: 0.62, alpha: 1),
            CGColor(red: 0.12, green: 0.12, blue: 0.14, alpha: 1), CGColor(red: 0.75, green: 0.18, blue: 0.12, alpha: 1)
        ]
        var seed: UInt32 = 7
        func next() -> Int { seed = seed &* 1_103_515_245 &+ 12_345; return Int(seed >> 16) }
        for line in 0..<(pageHeight / 38) {
            guard next() % 6 != 0 else { continue }
            var x = CGFloat(40 + (next() % 4) * 28)
            for _ in 0..<(1 + next() % 7) {
                let attributes = [kCTFontAttributeName: font, kCTForegroundColorAttributeName: colors[next() % colors.count]]
                    as CFDictionary
                let text = CTLineCreateWithAttributedString(
                    CFAttributedStringCreate(nil, (words[next() % words.count] + " ") as CFString, attributes))
                context.textPosition = CGPoint(x: x, y: CGFloat(pageHeight - line * 38 - 30))
                CTLineDraw(text, context)
                x += CGFloat(CTLineGetTypographicBounds(text, nil, nil, nil))
            }
        }
        pageImage = context.makeImage()!
        page = ChatWindow.pixels(pageImage)
    }

    /// The page's straight RGBA in the window's columns, for one page line.
    func pageRow(_ line: Int, columns: Range<Int>) -> Data {
        let start = (line * contentWidth + columns.lowerBound - sidebar) * 4
        return Data(page[start..<(start + columns.count * 4)])
    }

    /// `glass` tints the title bar with the page; `key` false greys the sidebar, as before activation.
    func frame(top: Int, pointer: Int?, glass: Bool = false, key: Bool = true) -> CGImage {
        let context = ChatWindow.context(width: width, height: height)
        func fill(_ rect: CGRect, _ gray: CGFloat, alpha: CGFloat = 1) {
            context.setFillColor(red: gray, green: gray, blue: gray + 0.01, alpha: alpha)
            context.fill(CGRect(x: rect.minX, y: CGFloat(height) - rect.maxY, width: rect.width, height: rect.height))
        }
        let viewport = contentBottom - contentTop
        let visible = pageImage.cropping(to: CGRect(x: 0, y: top, width: contentWidth, height: viewport))!
        context.interpolationQuality = .none
        context.draw(visible, in: CGRect(x: sidebar, y: height - contentBottom, width: contentWidth, height: viewport))
        // A hovered row lights in place under a resting pointer.
        if let pointer { fill(CGRect(x: sidebar, y: pointer - 20, width: contentWidth, height: 40), 0.9, alpha: 0.5) }
        for step in 0..<fade {
            let alpha = CGFloat(fade - step) / CGFloat(fade + 1)
            fill(CGRect(x: sidebar, y: contentTop + step, width: contentWidth, height: 1), background.0, alpha: alpha)
            fill(CGRect(x: sidebar, y: contentBottom - 1 - step, width: contentWidth, height: 1), background.0, alpha: alpha)
        }
        fill(CGRect(x: 0, y: 0, width: sidebar, height: height), key ? 0.93 : 0.97)
        fill(CGRect(x: 16, y: 180, width: sidebar - 32, height: 44), 0.85)
        let font = CTFontCreateWithName("Helvetica" as CFString, 24, nil)
        let ink = [kCTFontAttributeName: font, kCTForegroundColorAttributeName: CGColor(gray: key ? 0.3 : 0.6, alpha: 1)]
            as CFDictionary
        for (index, title) in ["Snake Game", "天气查询", "统计代码行数", "文件列表", "FLAC 格式"].enumerated() {
            context.textPosition = CGPoint(x: 28, y: CGFloat(height - 212 - index * 64))
            CTLineDraw(CTLineCreateWithAttributedString(CFAttributedStringCreate(nil, title as CFString, ink)), context)
        }
        fill(CGRect(x: sidebar, y: 0, width: contentWidth, height: contentTop), 0.99)
        if glass, top > 0 {
            let beneath = pageImage.cropping(to: CGRect(x: 0, y: max(0, top - contentTop), width: contentWidth, height: contentTop))!
            context.setAlpha(0.08)
            context.draw(beneath, in: CGRect(x: sidebar, y: height - contentTop, width: contentWidth, height: contentTop))
            context.setAlpha(1)
        }
        context.textPosition = CGPoint(x: CGFloat(sidebar + 40), y: CGFloat(height - 62))
        CTLineDraw(CTLineCreateWithAttributedString(CFAttributedStringCreate(nil, "Snake Game Code" as CFString, ink)), context)
        fill(CGRect(x: sidebar, y: contentBottom, width: contentWidth, height: height - contentBottom), 0.99)
        fill(CGRect(x: sidebar + 40, y: contentBottom + 30, width: contentWidth - 80, height: 110), 0.95)
        fill(button, 0.8)
        let thumb = contentTop + top * (viewport - 160) / (pageHeight - viewport)
        fill(CGRect(x: width - 16, y: thumb, width: 10, height: 160), 0.55)
        return context.makeImage()!
    }

    private static func context(width: Int, height: Int) -> CGContext {
        CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    }

    private static func pixels(_ image: CGImage) -> [UInt8] {
        var pixels = [UInt8](repeating: 0, count: image.width * image.height * 4)
        pixels.withUnsafeMutableBytes { buffer in
            let context = CGContext(
                data: buffer.baseAddress, width: image.width, height: image.height, bitsPerComponent: 8,
                bytesPerRow: image.width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        }
        return pixels
    }
}
