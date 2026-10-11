import CoreImage.CIFilterBuiltins
import CoreText
import Foundation
import ImageIO

@main
struct CaptureOCRTests {
    static func main() async throws {
        if CommandLine.arguments.count == 3 {
            let url = URL(fileURLWithPath: CommandLine.arguments[2])
            if CommandLine.arguments[1] == "foreground" {
                _ = try await ForegroundExtractor.mask(at: url)
                try FileHandle.standardOutput.write(contentsOf: Data("ok".utf8))
                return
            }
            if url.lastPathComponent.hasPrefix("hang") {
                signal(SIGTERM, SIG_IGN)
                try String(getpid()).write(to: url, atomically: true, encoding: .utf8)
                while true { try await Task.sleep(for: .seconds(60)) }
            }
            if url.lastPathComponent == "overflow" {
                try FileHandle.standardOutput.write(contentsOf: Data(repeating: 65, count: 2_000_000))
                return
            }
            if url.lastPathComponent == "immediate" {
                let result = TextRecognitionResult(requestID: UUID(), revision: 0, boxes: [], truncated: false)
                try FileHandle.standardOutput.write(contentsOf: JSONEncoder().encode(result))
                return
            }
            do {
                let result = try await TextRecognitionExtractor.capture(at: url)
                try FileHandle.standardOutput.write(contentsOf: JSONEncoder().encode(result))
            } catch { exit(1) }
            return
        }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("capture-ocr-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        deduplication()
        try await vision(in: root)
        try await smallText(in: root)
        try await qrCodes(in: root)
        try await people(in: root)
        try await foreground(in: root)
        try await cancellation(in: root)
        print(
            "Capture OCR pixels, redaction, overlapping tiles, repeated text, bounds and process cleanup passed"
        )
    }

    static func foreground(in root: URL) async throws {
        let fixture = URL(fileURLWithPath: "Tests/Fixtures/capture/nasa-portrait.jpg")
        let raster = UUID().uuidString
        let size = try CaptureImageSource.load(fixture, at: root.appendingPathComponent(raster))
        let bounds = CGRect(x: 0, y: 0, width: size.width, height: size.height)
        var layer = CaptureImageLayer(id: UUID(), raster: raster, source: bounds, frame: bounds)
        let input = root.appendingPathComponent("portrait.png")
        try CaptureForegroundService.input(for: layer, directory: root, to: input)
        let output = try await TextRecognitionWorker.foreground(at: input,
            executable: URL(fileURLWithPath: CommandLine.arguments[0]))
        let mask = UUID().uuidString
        let maskSize = try CaptureImageSource.load(output, at: root.appendingPathComponent(mask))
        precondition(maskSize == size)
        layer.backgroundMask = .init(raster: mask, size: maskSize)
        var document = CaptureDocument(id: UUID(), createdAt: Date(), size: size, pieces: [])
        document.edit.imageLayers = [layer]
        let result = try CaptureRenderer.image(document: document, directory: root, rect: bounds)
        let pixels = result.dataProvider!.data! as Data
        precondition(pixels[3] == 0 && pixels[(300 * size.width + 400) * 4 + 3] > 200,
            "Foreground mask must remove the backdrop and retain the subject")
        precondition((0..<(size.width * size.height)).filter { pixels[$0 * 4 + 3] == 0 }.count > 100_000)
        let noSubject = root.appendingPathComponent("invalid.png")
        try Data(repeating: 0, count: 128).write(to: noSubject)
        do {
            _ = try await TextRecognitionWorker.foreground(at: noSubject,
                executable: URL(fileURLWithPath: CommandLine.arguments[0]))
            preconditionFailure("Invalid mask inputs must not return a valid output path")
        } catch TextRecognitionWorker.Failure.foreground {}
    }

    static func deduplication() {
        let top = TextRecognitionResult.Request.Tile(filename: "top.png", rect: CGRect(x: 0, y: 0, width: 1024, height: 1024))
        let bottom = TextRecognitionResult.Request.Tile(filename: "bottom.png",
            rect: CGRect(x: 0, y: 896, width: 1024, height: 1024))
        precondition(top.readingRange(among: [top, bottom]) == 0..<960)
        precondition(bottom.readingRange(among: [top, bottom]) == 960..<1920)
        precondition(!top.readingRange(among: [top, bottom]).contains(1018))
        precondition(bottom.readingRange(among: [top, bottom]).contains(1018))
        var result = TextRecognitionResult(requestID: UUID(), revision: 9, boxes: [], truncated: false)
        result.append(.init(text: "Same sentence", rect: CGRect(x: 20, y: 920, width: 200, height: 24)))
        result.append(.init(text: "Same sentence", rect: CGRect(x: 21, y: 921, width: 200, height: 24)))
        result.append(.init(text: "Same sentence", rect: CGRect(x: 20, y: 1820, width: 200, height: 24)))
        precondition(result.boxes.count == 2)
        result.append(
            .init(
                text: String(repeating: "界", count: 11_000), rect: CGRect(x: 0, y: 0, width: 100, height: 20))
        )
        precondition(result.truncated && result.boxes.count == 2)
        var fragments = TextRecognitionResult(requestID: UUID(), revision: 0, boxes: [], truncated: false)
        let line = TextRecognitionResult.Box(text: "Cover Review Fixture", rect: CGRect(x: 30, y: 20, width: 950, height: 80))
        let fragment = TextRecognitionResult.Box(text: "re", rect: CGRect(x: 902, y: 21, width: 75, height: 78))
        fragments.append(line, mergingTextFragments: true)
        fragments.append(fragment, mergingTextFragments: true)
        precondition(fragments.boxes.count == 1 && fragments.text == line.text)
        fragments.boxes = []
        fragments.append(fragment, mergingTextFragments: true)
        fragments.append(line, mergingTextFragments: true)
        precondition(fragments.boxes.count == 1 && fragments.text == line.text)
        fragments.append(.init(text: "re", rect: CGRect(x: 30, y: 130, width: 75, height: 78)), mergingTextFragments: true)
        precondition(fragments.boxes.count == 2)
        fragments.boxes = []
        fragments.append(line)
        fragments.append(fragment)
        precondition(fragments.boxes.count == 2, "Non-text payloads must match exactly")
        fragments.boxes = []
        fragments.append(.init(text: "Keep the clipboard and history un", rect: CGRect(x: 20, y: 40, width: 980, height: 50)),
            mergingTextFragments: true)
        fragments.append(.init(text: "history unchanged.", rect: CGRect(x: 850, y: 41, width: 490, height: 49)),
            mergingTextFragments: true)
        precondition(fragments.boxes.count == 1 && fragments.text == "Keep the clipboard and history unchanged.")
        fragments.append(.init(text: "nchanged.", rect: CGRect(x: 1110, y: 43, width: 215, height: 45)),
            mergingTextFragments: true)
        precondition(fragments.boxes.count == 1)
        fragments.append(.init(text: "lata.", rect: CGRect(x: 900, y: 43, width: 100, height: 45)), mergingTextFragments: true)
        precondition(fragments.boxes.count == 1, "Clipped OCR spelling differences must not duplicate a complete line")
        let sentence = TextRecognitionResult.Box(text: "All values on this page are synthetic test data.",
            rect: CGRect(x: 43.915, y: 749.937, width: 940.185, height: 49.455))
        let clipped = TextRecognitionResult.Box(text: "lata.",
            rect: CGRect(x: 892.134, y: 748.893, width: 97.415, height: 49.180))
        for order in [[sentence, clipped], [clipped, sentence]] {
            fragments.boxes = []
            for box in order { fragments.append(box, mergingTextFragments: true) }
            precondition(fragments.boxes.count == 1 && fragments.text == sentence.text,
                "Native Vision bounds can extend a few pixels beyond the complete line")
            fragments.append(.init(text: "lata.", rect: clipped.rect.offsetBy(dx: 85, dy: 0)),
                mergingTextFragments: true)
            fragments.append(.init(text: sentence.text, rect: sentence.rect.offsetBy(dx: 0, dy: 60)),
                mergingTextFragments: true)
            precondition(fragments.boxes.count == 3, "Adjacent labels and repeated lines must survive")
        }
    }

    static func vision(in root: URL) async throws {
        let directory = root.appendingPathComponent("document")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let source = try CaptureSource(directory: directory)
        let context = CGContext(
            data: nil, width: 720, height: 2400, bitsPerComponent: 8, bytesPerRow: 2880,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 720, height: 2400))
        for (text, y, fontSize) in [
            ("VISIBLE RECEIPT 7391", 90, 28), ("REPEATED LINE 4826", 930, 28),
            ("REPEATED LINE 4826", 1810, 28), ("SECRET TOKEN 9182", 500, 28),
            ("qa@example.test", 210, 28),
            ("EDGE LINE 5738", 1028, 16),
            ("中文长截图测试 Mixed Text 6284", 1430, 20)
        ] {
            let attributes: [NSAttributedString.Key: Any] = [
                .init(kCTFontAttributeName as String): CTFontCreateWithName(
                    "Helvetica" as CFString, CGFloat(fontSize), nil),
                .init(kCTForegroundColorAttributeName as String): CGColor(gray: 0, alpha: 1)
            ]
            context.textPosition = CGPoint(x: 30, y: 2400 - y)
            CTLineDraw(
                CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes)),
                context)
        }
        let raster = UUID().uuidString
        let size = try CaptureImageSource.store(
            context.makeImage()!, at: directory.appendingPathComponent(raster))
        var document = CaptureDocument(
            id: UUID(), createdAt: Date(), size: size,
            pieces: [
                .init(raster: raster, source: CGRect(x: 0, y: 0, width: 720, height: 2400), origin: .zero)
            ])
        document.edit.annotations = [
            .init(
                id: UUID(), tool: .cover, points: [CGPoint(x: 0, y: 450), CGPoint(x: 720, y: 520)])
        ]
        let input = try CaptureTextInput.prepare(
            document: document, source: source, at: root.appendingPathComponent("input"))
        let executable = URL(fileURLWithPath: CommandLine.arguments[0])
        let result = try await TextRecognitionWorker.recognize(at: input, executable: executable)
        precondition(result.requestID == document.id && result.revision == document.revision)
        precondition(result.text.contains("7391") && !result.text.contains("9182"))
        precondition(result.boxes.filter { $0.text.contains("4826") }.count == 2)
        precondition(result.boxes.contains { $0.text.contains("4826") && $0.rect.minY > 1700 })
        precondition(result.text.contains("中文") && result.text.contains("6284"))
        let receipt = result.boxes.first { $0.text.contains("7391") }!.rect
        let highlight = CaptureTextHighlight(document: document, lines: result.boxes.map(\.rect))
        let markers = highlight.annotations(
            from: CGPoint(x: receipt.minX + receipt.width * 0.2, y: receipt.midY),
            to: CGPoint(x: receipt.minX + receipt.width * 0.7, y: receipt.midY), ink: .yellow, color: nil)
        precondition(markers.count == 1 && markers[0].points[0].y == receipt.midY)
        var highlighted = document
        highlighted.edit.annotations += markers
        let highlightInput = try CaptureTextInput.prepare(document: highlighted, source: source,
            at: root.appendingPathComponent("highlighted"))
        let afterHighlight = try await TextRecognitionWorker.recognize(at: highlightInput, executable: executable)
        precondition(afterHighlight.text.contains("7391") && !afterHighlight.text.contains("9182"),
            "Snapped highlighter must leave recognized text readable and existing covers opaque")
        let edgeLines = result.boxes.filter { $0.rect.midY > 995 && $0.rect.midY < 1060 }
        precondition(edgeLines.count == 1 && edgeLines[0].text == "EDGE LINE 5738",
            "Only the complete line may survive a vertical tile boundary")
        let candidates = CaptureRedactionPolicy.personalInfo.candidates(
            in: result.boxes.map { ($0.text, $0.rect) }, bounds: document.outputBounds)
        precondition(candidates.contains { $0.label.contains("qa@example.test") })
        document.edit.annotations += candidates.map {
            .init(id: UUID(), tool: .cover, points: [$0.rect.origin, .init(x: $0.rect.maxX, y: $0.rect.maxY)])
        }
        let redacted = try CaptureTextInput.prepare(document: document, source: source,
            at: root.appendingPathComponent("suggested-covers"))
        let afterCover = try await TextRecognitionWorker.recognize(at: redacted, executable: executable)
        precondition(!afterCover.text.contains("qa@example.test") && afterCover.text.contains("7391"))
        var textOnly = document
        let textCandidates = CaptureRedactionPolicy.allText.candidates(
            in: afterCover.boxes.map { ($0.text, $0.rect) }, bounds: textOnly.outputBounds)
        precondition(!textCandidates.isEmpty)
        textOnly.edit.annotations += textCandidates.map {
            .init(id: UUID(), tool: .cover, points: [$0.rect.origin, .init(x: $0.rect.maxX, y: $0.rect.maxY)])
        }
        let textOnlyInput = try CaptureTextInput.prepare(document: textOnly, source: source,
            at: root.appendingPathComponent("text-only"))
        let afterTextOnly = try await TextRecognitionWorker.recognize(at: textOnlyInput, executable: executable)
        precondition(afterTextOnly.text.isEmpty, "Text Only must conceal the reviewed OCR boxes")
        document.edit.presentation = .init(padding: 57, windowFrame: true)
        let styled = try CaptureTextInput.prepare(document: document, source: source,
            at: root.appendingPathComponent("styled"))
        let styledText = try await TextRecognitionWorker.recognize(at: styled, executable: executable)
        precondition(styledText.text.contains("7391") && !styledText.text.contains("9182"))
        precondition(!styledText.text.contains("qa@example.test"))
        precondition(styledText.boxes.contains { $0.text.contains("4826") && $0.rect.minY > 1700 })
        document.edit.presentation = nil
        document.edit.translation = .init(target: "en", blocks: [
            .init(id: UUID(), source: "VISIBLE RECEIPT 7391", text: "REPLACED PARAGRAPH 6284",
                rect: .init(x: 25, y: 55, width: 690, height: 65), background: .init(red: 255, green: 255, blue: 255)),
            .init(id: UUID(), source: "Covered paragraph", text: "KEEP THIS HIDDEN 5533",
                rect: .init(x: 25, y: 455, width: 690, height: 60), background: .init(red: 255, green: 255, blue: 255))])
        let translated = try CaptureTextInput.prepare(document: document, source: source,
            at: root.appendingPathComponent("translated"))
        let translatedText = try await TextRecognitionWorker.recognize(at: translated, executable: executable)
        precondition(translatedText.text.contains("REPLACED PARAGRAPH 6284") && !translatedText.text.contains("7391"))
        precondition(!translatedText.text.contains("5533") && !translatedText.text.contains("9182"))
        let invalid = TextRecognitionResult.Request(
            requestID: document.id, revision: 0,
            tiles: [.init(filename: "0.png", rect: CGRect(x: 0, y: 0, width: 40, height: 40))])
        try JSONEncoder().encode(invalid).write(to: input)
        do {
            _ = try await TextRecognitionWorker.recognize(at: input, executable: executable)
            preconditionFailure("mismatched image dimensions accepted")
        } catch TextRecognitionWorker.Failure.recognition {}
    }

    static func smallText(in root: URL) async throws {
        let directory = root.appendingPathComponent("small-text")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let source = try CaptureSource(directory: directory)
        let context = CGContext(data: nil, width: 720, height: 4200, bitsPerComponent: 8,
            bytesPerRow: 2880, space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 720, height: 4200))
        let corpus: [(String, CGFloat, String)] = [
            ("SMALL TEXT TOTAL 6284", 12, "Helvetica"),
            ("中文截图金额7391元", 12, "PingFangSC-Regular"),
            ("订单 Order 4826 已完成", 12, "PingFangSC-Regular"),
            ("File capture_output_5738.png", 12, "Menlo-Regular"),
            ("Email qa@example.test", 14, "Helvetica"),
            ("含税价格 128.50 CNY", 14, "PingFangSC-Regular"),
            ("REPEATED RECEIPT 9157", 12, "Helvetica"),
            ("REPEATED RECEIPT 9157", 12, "Helvetica")
        ]
        for (index, row) in corpus.enumerated() {
            let y = 120 + index * 560, dark = index.isMultiple(of: 2)
            if dark {
                context.setFillColor(CGColor(gray: 0.12, alpha: 1))
                context.fill(CGRect(x: 0, y: 4200 - y - 100, width: 720, height: 200))
            }
            let attributes: [NSAttributedString.Key: Any] = [
                .init(kCTFontAttributeName as String): CTFontCreateWithName(row.2 as CFString, row.1, nil),
                .init(kCTForegroundColorAttributeName as String): CGColor(gray: dark ? 0.95 : 0.05, alpha: 1)
            ]
            context.textPosition = CGPoint(x: 35, y: 4200 - y)
            CTLineDraw(CTLineCreateWithAttributedString(NSAttributedString(string: row.0, attributes: attributes)), context)
        }
        let raster = UUID().uuidString
        let size = try CaptureImageSource.store(context.makeImage()!, at: directory.appendingPathComponent(raster))
        let document = CaptureDocument(id: UUID(), createdAt: Date(), size: size,
            pieces: [.init(raster: raster, source: CGRect(x: 0, y: 0, width: 720, height: 4200), origin: .zero)])
        let input = try CaptureTextInput.prepare(document: document, source: source,
            at: root.appendingPathComponent("small-text-input"))
        let result = try await TextRecognitionWorker.recognize(at: input,
            executable: URL(fileURLWithPath: CommandLine.arguments[0]))
        let expected = corpus.map { $0.0.filter { !$0.isWhitespace } }
        let actual = result.boxes.map { $0.text.filter { !$0.isWhitespace } }
        precondition(actual == expected, "Small text corpus differs: \(actual)")
    }

    static func people(in root: URL) async throws {
        let input = URL(fileURLWithPath: "Tests/Fixtures/capture/nasa-portrait.jpg")
        let image = CGImageSourceCreateImageAtIndex(CGImageSourceCreateWithURL(input as CFURL, nil)!, 0, nil)!
        let directory = root.appendingPathComponent("people-source")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let source = try CaptureSource(directory: directory), raster = UUID().uuidString
        let size = try CaptureImageSource.store(image, at: directory.appendingPathComponent(raster))
        var document = CaptureDocument(id: UUID(), createdAt: Date(), size: size,
            pieces: [.init(raster: raster, source: CGRect(x: 0, y: 0, width: size.width, height: size.height), origin: .zero)])
        let executable = URL(fileURLWithPath: CommandLine.arguments[0])
        for policy in [CaptureRedactionPolicy.faces, .people] {
            document.edit.annotations = []
            let request = try CaptureTextInput.prepare(document: document, source: source,
                at: root.appendingPathComponent(policy.rawValue), content: policy.content)
            let result = try await TextRecognitionWorker.recognize(at: request, executable: executable)
            let candidates = policy.candidates(in: result.boxes.map { ($0.text, $0.rect) }, bounds: document.outputBounds)
            precondition(candidates.count == 1, "Overlapping detections must be presented once for review")
            let candidate = candidates[0]
            precondition(candidate.rect.contains(CGPoint(x: 470, y: 210)), "Upper-left image coordinates must include the face")
            if policy == .people { precondition(candidate.rect.height > 750 && candidate.rect.width > 450) }
            document.edit.annotations = [.init(id: UUID(), tool: .cover,
                points: [candidate.rect.origin, .init(x: candidate.rect.maxX, y: candidate.rect.maxY)])]
            let covered = try CaptureTextInput.prepare(document: document, source: source,
                at: root.appendingPathComponent("\(policy.rawValue)-covered"), content: policy.content)
            let after = try await TextRecognitionWorker.recognize(at: covered, executable: executable)
            precondition(after.boxes.isEmpty, "Detection must read the covered output, never the retained original")
        }
    }

    static func cancellation(in root: URL) async throws {
        let executable = URL(fileURLWithPath: CommandLine.arguments[0])
        for _ in 0..<16 {
            let result = try await TextRecognitionWorker.recognize(
                at: root.appendingPathComponent("immediate"), executable: executable)
            precondition(result.boxes.isEmpty)
        }
        let url = root.appendingPathComponent("hang-cancel")
        let task = Task { try await TextRecognitionWorker.recognize(at: url, executable: executable) }
        let pid = try await waitForPID(url)
        task.cancel()
        do {
            _ = try await task.value; preconditionFailure("cancelled worker succeeded")
        } catch is CancellationError {}
        precondition(kill(pid, 0) == -1 && errno == ESRCH)
        let timed = root.appendingPathComponent("hang-timeout")
        let deadline = Task {
            try await TextRecognitionWorker.recognize(at: timed, executable: executable, timeout: .seconds(1))
        }
        let timedPID = try await waitForPID(timed)
        do {
            _ = try await deadline.value; preconditionFailure("deadline worker succeeded")
        } catch TextRecognitionWorker.Failure.recognition {}
        precondition(kill(timedPID, 0) == -1 && errno == ESRCH)
        do {
            _ = try await TextRecognitionWorker.recognize(
                at: root.appendingPathComponent("overflow"), executable: executable)
            preconditionFailure("unbounded helper output accepted")
        } catch TextRecognitionWorker.Failure.outputLimit {}
    }

    static func qrCodes(in root: URL) async throws {
        let payload = "https://example.com/tinycast-capture-qa"
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(payload.utf8)
        filter.correctionLevel = "H"
        let image = filter.outputImage!
        let qr = CIContext().createCGImage(image, from: image.extent)!
        let context = CGContext(data: nil, width: 1500, height: 1300, bitsPerComponent: 8, bytesPerRow: 6000,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 1500, height: 1300))
        context.interpolationQuality = .none
        context.draw(qr, in: CGRect(x: 790, y: 250, width: 360, height: 360))
        let directory = root.appendingPathComponent("qr-document")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        let source = try CaptureSource(directory: directory), raster = UUID().uuidString
        let size = try CaptureImageSource.store(context.makeImage()!, at: directory.appendingPathComponent(raster))
        var document = CaptureDocument(id: UUID(), createdAt: Date(), size: size,
            pieces: [.init(raster: raster, source: CGRect(x: 0, y: 0, width: 1500, height: 1300), origin: .zero)])
        let executable = URL(fileURLWithPath: CommandLine.arguments[0])
        let input = try CaptureTextInput.prepare(document: document, source: source,
            at: root.appendingPathComponent("qr-input"), content: .qr)
        let result = try await TextRecognitionWorker.recognize(at: input, executable: executable)
        precondition(result.boxes.count == 1 && result.boxes[0].text == payload)
        precondition((770...820).contains(result.boxes[0].rect.minX))
        precondition((670...720).contains(result.boxes[0].rect.minY))
        document.edit.annotations = [.init(id: UUID(), tool: .cover,
            points: [.init(x: 780, y: 680), .init(x: 1160, y: 1060)])]
        let hidden = try CaptureTextInput.prepare(document: document, source: source,
            at: root.appendingPathComponent("qr-covered"), content: .qr)
        let covered = try await TextRecognitionWorker.recognize(at: hidden, executable: executable)
        precondition(covered.boxes.isEmpty, "QR scanning bypassed the exported redaction")
    }

    static func waitForPID(_ url: URL) async throws -> pid_t {
        for _ in 0..<200 {
            if let text = try? String(contentsOf: url, encoding: .utf8), let pid = pid_t(text) { return pid }
            try await Task.sleep(for: .milliseconds(10))
        }
        throw CocoaError(.fileReadUnknown)
    }
}
