import CoreGraphics
import CoreText
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Scrolling capture end to end on rendered window frames: sampling, tracking, strips and the composite.
/// `TINYCAST_SCROLL_REPLAY=<recorded folder>` replays a Record Diagnostic Frames folder instead.
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
        print("Scrolling replay of a chat window with sidebar, bars, fades, scroller, button and pointer passed")
    }

    /// One sampled frame and what the session knew alongside it.
    struct Shot {
        let image: CGImage
        let top: Int
        let pointer: Int?
        let travel: Int?

        init(_ window: ChatWindow, top: Int, pointer: Int? = nil, travel: Int? = nil, hover: Bool = false) {
            image = window.frame(top: top, pointer: hover ? pointer : nil)
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
            precondition(
                document.size.height == window.height + shots.last!.top,
                "The capture grows by exactly the distance scrolled: \(document.size.height), \(verdicts)")
        }
        guard comparesPixels else { return (document, verdicts) }
        let composite = try CaptureCompositeReader(document: document, directory: directory)
        let columns = window.comparedColumns
        let width = columns.count * 4
        for row in (window.contentTop + window.fade)..<(document.size.height - window.height + window.contentBottom - window.fade) {
            let actual = try composite.read(rect: CGRect(x: columns.lowerBound, y: row, width: columns.count, height: 1))
            let expected = window.pageRow(row - window.contentTop, columns: columns)
            precondition(actual.count == width && actual == expected, "Stitched row \(row) differs from the page, \(verdicts)")
        }
        return (document, verdicts)
    }

    static func stitch(_ shots: [Shot], in directory: URL) throws -> (CaptureDocument, [String]) {
        var tracker = ScrollTracker<CGImage>()
        var document: CaptureDocument?
        var verdicts: [String] = []
        func write(_ strip: ScrollTracker<CGImage>.Strip) throws {
            let size = try CapturePixelSize(width: strip.payload.width, height: strip.payload.height)
            let current = document ?? CaptureDocument(id: UUID(), createdAt: Date(), size: size, pieces: [], axis: .vertical)
            let raster = UUID().uuidString
            let plan = try CaptureScrollAppend.plan(
                document: current, frame: size, raster: raster, offset: strip.offset, trailing: strip.trailing)
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

/// An AI Chat-like window: title bar, sidebar, composer, edge fades, an overlay scroller and a button.
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

    func frame(top: Int, pointer: Int?) -> CGImage {
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
        fill(CGRect(x: 0, y: 0, width: sidebar, height: height), 0.93)
        fill(CGRect(x: 16, y: 180, width: sidebar - 32, height: 44), 0.85)
        let font = CTFontCreateWithName("Helvetica" as CFString, 24, nil)
        let ink = [kCTFontAttributeName: font, kCTForegroundColorAttributeName: CGColor(gray: 0.3, alpha: 1)] as CFDictionary
        for (index, title) in ["Snake Game", "天气查询", "统计代码行数", "文件列表", "FLAC 格式"].enumerated() {
            context.textPosition = CGPoint(x: 28, y: CGFloat(height - 212 - index * 64))
            CTLineDraw(CTLineCreateWithAttributedString(CFAttributedStringCreate(nil, title as CFString, ink)), context)
        }
        fill(CGRect(x: sidebar, y: 0, width: contentWidth, height: contentTop), 0.99)
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
