import CoreGraphics
import Foundation
import ImageIO

@main
struct CaptureWorkflowTests {
    static func main() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("capture-workflow-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        geometry()
        pinGeometry()
        selectionConstraints()
        alignment()
        redactionCandidates()
        try selection(in: root)
        visibility()
        stitching()
        tracking()
        stillOverlays()
        try liveFrames(in: root)
        try CaptureScrollFixture.verify(in: root)
        try leases(in: root)
        try strips(in: root)
        try output(in: root)
        try alphaRoundTrip(in: root)
        try annotationStyles(in: root)
        try emoji(in: root)
        try imageEffects(in: root)
        try censorIsolation(in: root)
        try erase(in: root)
        try imageAdjustments(in: root)
        try previewSeams(in: root)
        print(
            "Capture geometry, stitch confidence, revision undo, import, cropped redaction and history passed"
        )
    }

    static func pinGeometry() {
        let fitted = CapturePinGeometry.fitted(CGSize(width: 3000, height: 150), maximum: 600)
        precondition(fitted == CGSize(width: 600, height: 30))
        let frame = CGRect(x: 40, y: 50, width: fitted.width, height: fitted.height)
        let anchor = CGPoint(x: 120, y: 15)
        let zoomed = CapturePinGeometry.resized(frame, factor: 4, anchor: anchor, minimum: 80, maximum: 1200)
        precondition(zoomed.size == CGSize(width: 1200, height: 60))
        precondition(zoomed.minX + anchor.x * 2 == frame.minX + anchor.x)
        precondition(zoomed.minY + anchor.y * 2 == frame.minY + anchor.y)
        let small = CapturePinGeometry.resized(frame, factor: 0.01, anchor: .zero, minimum: 80, maximum: 1200)
        precondition(abs(small.width - 80) < 0.001 && abs(small.height - 4) < 0.001)
        for factor in [CGFloat.nan, .infinity, 0, -1] {
            precondition(CapturePinGeometry.resized(frame, factor: factor, anchor: anchor,
                minimum: 80, maximum: 1200) == frame)
        }
    }

    static func censorIsolation(in root: URL) throws {
        let size = try CapturePixelSize(width: 128, height: 96)
        let area = CGRect(x: 40, y: 24, width: 32, height: 40)
        var documents: [CaptureDocument] = []
        for secret: UInt8 in [0, 255] {
            let raster = UUID().uuidString
            try CaptureRasterStore.write(size: size, to: root.appendingPathComponent(raster)) { y, row in
                for x in 0..<size.width {
                    let value: UInt8 = area.contains(CGPoint(x: x, y: y)) ? secret : 180
                    for channel in 0..<3 { row[x * 4 + channel] = value }
                    row[x * 4 + 3] = 255
                }
            }
            documents.append(CaptureDocument(id: UUID(), createdAt: Date(), size: size,
                pieces: [.init(raster: raster, source: CGRect(origin: .zero, size: CGSize(width: 128, height: 96)),
                    origin: .zero)]))
        }
        for censor in [CaptureAnnotation.Tool.cover, .erase] {
            for effect in [CaptureAnnotation.Tool.blur, .pixelate, .magnifier] {
                var outputs: [Data] = []
                for var document in documents {
                    document.edit.annotations = [
                        .init(id: UUID(), tool: censor,
                            points: [area.origin, CGPoint(x: area.maxX, y: area.maxY)],
                            color: censor == .erase ? CaptureColor(red: 238, green: 238, blue: 238) : nil),
                        .init(id: UUID(), tool: effect,
                            points: [CGPoint(x: 16, y: 8), CGPoint(x: 112, y: 88)], width: 8)
                    ]
                    document.edit.adjustments = .init(sharpness: 1)
                    let output = root.appendingPathComponent("isolation-\(UUID()).png")
                    try CaptureRenderer.png(document: document, directory: root, to: output)
                    let source = CGImageSourceCreateWithURL(output as CFURL, nil)!
                    let image = CGImageSourceCreateImageAtIndex(source, 0, nil)!
                    outputs.append(image.dataProvider!.data! as Data)
                    let color = try CaptureRenderer.color(document: document, directory: root,
                        at: CGPoint(x: area.midX, y: area.midY))
                    precondition(color.hex == (censor == .erase ? "#EEEEEE" : "#000000"))
                }
                precondition(outputs[0] == outputs[1],
                    "Hidden source pixels must not affect blur, pixelation, sharpening or magnification")
            }
        }
    }

    static func erase(in root: URL) throws {
        let size = try CapturePixelSize(width: 1080, height: 100), raster = UUID().uuidString
        let area = CGRect(x: 990, y: 20, width: 70, height: 60)
        try CaptureRasterStore.write(size: size, to: root.appendingPathComponent(raster)) { y, row in
            for x in 0..<size.width {
                let secret = area.contains(CGPoint(x: x, y: y))
                for channel in 0..<3 { row[x * 4 + channel] = secret ? UInt8((x + y) % 128) : 238 }
                row[x * 4 + 3] = 255
            }
        }
        var document = CaptureDocument(id: UUID(), createdAt: Date(), size: size,
            pieces: [.init(raster: raster, source: CGRect(x: 0, y: 0, width: size.width, height: size.height), origin: .zero)])
        document.edit.annotations = [.init(id: UUID(), tool: .cover,
            points: [.init(x: 980, y: 14), .init(x: 1010, y: 19)])]
        let color = try CaptureEraseService.color(document: document, directory: root, around: area)
        precondition(color.hex == "#EEEEEE", "Nearby foreground must not dominate a uniform background")
        var undo = CaptureUndoHistory(), edit = document.edit
        edit.annotations.append(.init(id: UUID(), tool: .erase,
            points: [area.origin, .init(x: area.maxX, y: area.maxY)], color: color))
        edit.annotations.append(.init(id: UUID(), tool: .pixelate,
            points: [area.origin, .init(x: area.maxX, y: area.maxY)]))
        undo.commit(edit, to: &document)
        let erased = document.edit
        undo.undo(&document)
        precondition(document.edit.annotations.count == 1)
        undo.redo(&document)
        precondition(document.edit == erased)
        let output = root.appendingPathComponent("erased.png")
        try CaptureRenderer.png(document: document, directory: root, to: output)
        let reader = try CapturePNGReader(url: output)
        var bytes = Data(count: size.byteCount)
        try bytes.withUnsafeMutableBytes { buffer in
            for y in 0..<size.height {
                let row = UnsafeMutableRawBufferPointer(rebasing: buffer[(y * size.rowBytes)..<((y + 1) * size.rowBytes)])
                try reader.read(row: y, into: row)
                if (20..<80).contains(y) {
                    for x in 990..<1060 { precondition(Array(row[(x * 4)..<(x * 4 + 4)]) == [238, 238, 238, 255]) }
                }
            }
        }
        let preview = try CaptureRenderer.preview(document: document, directory: root, maximum: size.width)
        precondition(preview.dataProvider!.data! as Data == bytes, "Erase must match across tile and PNG band boundaries")
        document.edit.crop = area
        do {
            _ = try CaptureEraseService.color(document: document, directory: root, around: area)
            preconditionFailure("A whole-image erase must not sample the content being removed")
        } catch CaptureEraseService.Failure.noSurroundingPixels {}
    }

    static func imageEffects(in root: URL) throws {
        let size = try CapturePixelSize(width: 1051, height: 83), raster = UUID().uuidString
        try CaptureRasterStore.write(size: size, to: root.appendingPathComponent(raster)) { y, row in
            for x in 0..<size.width {
                let value: UInt8 = ((x / 2 + y / 2) % 2 == 0) ? 255 : 0
                for channel in 0..<3 { row[x * 4 + channel] = value }
                row[x * 4 + 3] = 255
            }
        }
        var document = CaptureDocument(id: UUID(), createdAt: Date(), size: size,
            pieces: [.init(raster: raster, source: CGRect(x: 0, y: 0, width: size.width, height: size.height), origin: .zero)])
        let blur = CaptureAnnotation(id: UUID(), tool: .blur,
            points: [.init(x: 10, y: 10), .init(x: 1040, y: 73)], width: 8)
        document.edit.annotations = [blur]
        let output = root.appendingPathComponent("effects.png")
        try CaptureRenderer.png(document: document, directory: root, to: output)
        let reader = try CapturePNGReader(url: output)
        var pixels = Data(count: size.byteCount)
        try pixels.withUnsafeMutableBytes { bytes in
            for y in 0..<size.height {
                let row = (y * size.rowBytes)..<((y + 1) * size.rowBytes)
                try reader.read(row: y, into: UnsafeMutableRawBufferPointer(rebasing: bytes[row]))
            }
        }
        func value(_ x: Int, _ y: Int) -> UInt8 { pixels[(y * size.width + x) * 4] }
        precondition(value(4, 4) == 255 && value(6, 4) == 0)
        for y in 11..<72 {
            for x in 11..<1039 { precondition((100...155).contains(value(x, y))) }
        }
        let whole = try CaptureRenderer.image(document: document, directory: root, rect: document.bounds)
        precondition(whole.dataProvider!.data! as Data == pixels, "Blur must not introduce PNG band seams")
        let preview = try CaptureRenderer.preview(document: document, directory: root, maximum: size.width)
        precondition(preview.dataProvider!.data! as Data == pixels, "Blur must not introduce preview tile seams")
        document.edit.annotations = [
            .init(id: UUID(), tool: .spotlight, points: [.init(x: 20, y: 10), .init(x: 80, y: 60)]),
            .init(id: UUID(), tool: .spotlight, points: [.init(x: 50, y: 20), .init(x: 120, y: 70)])
        ]
        for point in [CGPoint(x: 24, y: 24), CGPoint(x: 60, y: 24), CGPoint(x: 100, y: 24)] {
            let color = try CaptureRenderer.color(document: document, directory: root, at: point)
            precondition(color.hex == "#FFFFFF", "Overlapping spotlights form one illuminated union")
        }
        let dimmed = try CaptureRenderer.color(document: document, directory: root, at: .init(x: 4, y: 4))
        precondition((112...116).contains(dimmed.red) && dimmed.red == dimmed.green)
        let custom = CaptureColor(hex: " #2468aC ")!
        precondition(custom.hex == "#2468AC" && CaptureColor(hex: "#12345") == nil && CaptureColor(hex: "GGGGGG") == nil)
        document.edit.annotations = [.init(id: UUID(), tool: .rectangle,
            points: [.init(x: 10, y: 10), .init(x: 40, y: 40)], filled: true, color: custom)]
        let sampled = try CaptureRenderer.color(document: document, directory: root, at: .init(x: 20, y: 20))
        precondition(sampled == custom)
        let encoded = try JSONEncoder().encode(document)
        let decoded = try JSONDecoder().decode(CaptureDocument.self, from: encoded)
        precondition(decoded.edit == document.edit)
        document.edit.annotations = [
            .init(id: UUID(), tool: .cover, points: [.init(x: 10, y: 10), .init(x: 40, y: 40)]), blur
        ]
        let hidden = try CaptureRenderer.color(document: document, directory: root, at: .init(x: 20, y: 20))
        precondition(hidden.hex == "#000000", "Blur and eyedropper must never bypass a cover")
    }

    static func selectionConstraints() {
        let bounds = CGRect(x: -1920, y: 37, width: 1920, height: 1080)
        for aspect in CaptureSelectionConstraint.Aspect.allCases {
            for point in [CGPoint(x: -2000, y: -300), CGPoint(x: 120, y: 2000), CGPoint(x: -250, y: 190)] {
                let rect = CaptureSelectionConstraint.selection(from: CGPoint(x: -1800, y: 900), to: point,
                    ratio: aspect.ratio, in: bounds)!
                precondition(bounds.contains(rect))
                if let ratio = aspect.ratio { precondition(abs(rect.width / rect.height - ratio) < 0.0001) }
                for handle in CaptureSelectionGeometry.Handle.allCases {
                    let resized = CaptureSelectionConstraint.resized(CGRect(x: -1600, y: 200, width: 640, height: 360),
                        handle: handle, to: point, ratio: aspect.ratio, in: bounds)
                    precondition(bounds.contains(resized))
                    if let ratio = aspect.ratio { precondition(abs(resized.width / resized.height - ratio) < 0.0001) }
                }
            }
        }
        let rect = CGRect(x: -500, y: 900, width: 300, height: 200)
        let sized = CaptureSelectionConstraint.sized(rect, pixels: CGSize(width: 800, height: 600), scale: 2, in: bounds)!
        precondition(sized.size == CGSize(width: 400, height: 300) && sized.maxY == rect.maxY)
        precondition(CaptureSelectionConstraint.sized(
            rect, pixels: CGSize(width: CGFloat.infinity, height: 600), scale: 2, in: bounds) == nil)
        precondition(CaptureSelectionConstraint.sized(
            rect, pixels: CGSize(width: 8000, height: 600), scale: 2, in: bounds) == nil)
        precondition(CaptureSelectionConstraint.snapped(CGPoint(x: -1916, y: 1000), edges: [bounds], tolerance: 6)
            == CGPoint(x: -1920, y: 1000))
        precondition(CaptureSavedRegion(displayID: 1, screenSize: CGSize(width: 100, height: 100),
            rect: CGRect(x: 0, y: 0, width: 101, height: 50)).isValid == false)
    }

    static func alignment() {
        let bounds = CGRect(x: 0, y: 0, width: 800, height: 600)
        let rectangle = CGRect(x: 50, y: 50, width: 100, height: 80)
        let centered = CaptureAnnotationPlacement.moved(rectangle, by: CGSize(width: 296, height: 207),
            in: bounds, aligning: [bounds], tolerance: 6)
        precondition(centered.offset == CGSize(width: 300, height: 210))
        precondition(centered.verticalGuide == 400 && centered.horizontalGuide == 300)
        let free = CaptureAnnotationPlacement.moved(rectangle, by: CGSize(width: 296, height: 207),
            in: bounds, aligning: [], tolerance: 6)
        precondition(free.offset == CGSize(width: 296, height: 207) && free.verticalGuide == nil)
        let neighbor = CGRect(x: 255, y: 170, width: 100, height: 100)
        let aligned = CaptureAnnotationPlacement.moved(rectangle, by: CGSize(width: 200, height: 118),
            in: bounds, aligning: [neighbor], tolerance: 6)
        precondition(aligned.offset == CGSize(width: 205, height: 120))
        let outside = CaptureAnnotationPlacement.moved(rectangle, by: CGSize(width: -100, height: 800),
            in: bounds, aligning: [CGRect(x: -100, y: 602, width: 95, height: 20)], tolerance: 6)
        precondition(outside.offset == CGSize(width: -50, height: 470))
        precondition(outside.verticalGuide == nil && outside.horizontalGuide == nil)
        let far = CaptureAnnotationPlacement.moved(rectangle, by: CGSize(width: 90, height: 70),
            in: bounds, aligning: [bounds], tolerance: 6)
        precondition(far.offset == CGSize(width: 90, height: 70))
    }

    static func redactionCandidates() {
        let bounds = CGRect(x: 10, y: 10, width: 800, height: 600)
        let items: [(text: String, rect: CGRect)] = [
            ("Write to qa@example.test", CGRect(x: 10, y: 10, width: 300, height: 20)),
            ("Phone +1 (415) 555-0100", CGRect(x: 10, y: 40, width: 300, height: 20)),
            ("手机 13800138000", CGRect(x: 10, y: 70, width: 300, height: 20)),
            ("Card 4111 1111 1111 1111", CGRect(x: 10, y: 100, width: 300, height: 20)),
            ("An ordinary paragraph", CGRect(x: 10, y: 130, width: 300, height: 20)),
            ("qa@example.test", CGRect(x: 10, y: 200, width: 300, height: 20)),
            ("Hidden qa@example.test", CGRect(x: 900, y: 10, width: 300, height: 20)),
            ("Invalid qa@example.test", CGRect(x: CGFloat.nan, y: 10, width: 300, height: 20))
        ]
        let personal = CaptureRedactionPolicy.personalInfo.candidates(in: items, bounds: bounds)
        precondition(personal.count == 5 && personal.allSatisfy { bounds.contains($0.rect) && $0.included })
        precondition(personal[0].rect == CGRect(x: 10, y: 10, width: 303, height: 23))
        precondition(CaptureRedactionPolicy.allText.candidates(in: items, bounds: bounds).count == 6)
        let plain = CaptureRedactionPolicy.personalInfo.candidates(
            in: [("Version 2.3.0 · Release Notes", CGRect(x: 10, y: 10, width: 300, height: 20))], bounds: bounds)
        precondition(plain.isEmpty)
        let face = CaptureRedactionPolicy.faces.candidates(
            in: [("Face", CGRect(x: 5, y: 12, width: 100, height: 120))], bounds: bounds)
        precondition(face.count == 1 && face[0].rect == CGRect(x: 10, y: 10, width: 105, height: 132))
        precondition(CaptureRedactionPolicy.faces.content == .faces && CaptureRedactionPolicy.people.content == .people)
    }

    static func geometry() {
        let screen = CGRect(x: -1920, y: 37, width: 1920, height: 1080)
        let selection = CGRect(x: -1800, y: 100, width: 600, height: 400)
        precondition(
            CaptureGeometry.pixels(selection, screen: screen, scale: 2)
                == CGRect(x: 240, y: 1234, width: 1200, height: 800))
        precondition(CaptureGeometry.pixels(selection, screen: screen, scale: .nan) == nil)
        var state = CaptureSessionState(id: UUID())
        let id = state.id
        state.advance(to: .selecting)
        precondition(!state.accepts(id: id, revision: 0))
        state.advance(to: .closed)
        precondition(!state.accepts(id: id, revision: state.revision))
        precondition(!CaptureCopyPolicy.accepts(encodedBytes: 0))
        precondition(CaptureCopyPolicy.accepts(encodedBytes: 1))
        precondition(CaptureCopyPolicy.accepts(encodedBytes: CaptureCopyPolicy.maximumEncodedBytes))
        precondition(!CaptureCopyPolicy.accepts(encodedBytes: CaptureCopyPolicy.maximumEncodedBytes + 1))
        precondition(!CaptureCopyPolicy.accepts(encodedBytes: Int.max))
        let region = CGRect(x: 20, y: 160, width: 1200, height: 700)
        let controls = CaptureControlPlacement.frame(
            region: region, size: CGSize(width: 680, height: 120),
            screens: [CGRect(x: 0, y: 0, width: 1440, height: 900)], gap: 8)!
        precondition(!controls.intersects(region))
        precondition(
            CaptureControlPlacement.frame(
                region: CGRect(x: 0, y: 0, width: 1440, height: 900), size: CGSize(width: 680, height: 120),
                screens: [CGRect(x: 0, y: 0, width: 1440, height: 900)], gap: 8) == nil)
        for scale in [1.0, 1.1, 1.2] {
            let row = CGSize(width: (420 * scale).rounded(), height: (46 * scale).rounded())
            let details = (72 * scale).rounded()
            for visible in [CGRect(x: 0, y: 40, width: 1440, height: 820),
                CGRect(x: -1920, y: -180, width: 1920, height: 1040)] {
                for x in [visible.minX, visible.midX - 100, visible.maxX - 200] {
                    for y in [visible.minY, visible.midY - 100, visible.maxY - 200] {
                        let region = CGRect(x: x, y: y, width: 200, height: 200)
                        let placement = CaptureControlPlacement.scrolling(region: region, row: row,
                            detailsHeight: details, screens: [visible], gap: 8)!
                        precondition(visible.contains(placement.expanded) && visible.contains(placement.collapsed))
                        precondition(!region.intersects(placement.expanded))
                        precondition(placement.expanded.contains(placement.collapsed))
                        precondition(placement.collapsed.maxY == placement.expanded.maxY)
                        precondition(placement.collapsed.minX == placement.expanded.minX)
                    }
                }
                precondition(CaptureControlPlacement.scrolling(region: visible, row: row,
                    detailsHeight: details, screens: [visible], gap: 8) == nil)
            }
        }
        let external = CGRect(x: 1440, y: 40, width: 1920, height: 1040)
        let externalRegion = CGRect(x: 1600, y: 200, width: 1400, height: 600)
        let externalControls = CaptureControlPlacement.scrolling(region: externalRegion,
            row: CGSize(width: 420, height: 46), detailsHeight: 72,
            screens: [external, CGRect(x: 0, y: 40, width: 1440, height: 820)], gap: 8)!
        precondition(external.contains(externalControls.expanded))
        for screen in [CGRect(x: 0, y: 0, width: 1728, height: 1117), screen] {
            for x in [screen.minX, screen.midX, screen.maxX - 2] {
                for y in [screen.minY, screen.midY, screen.maxY - 2] {
                    let tiny = CGRect(x: x, y: y, width: 2, height: 2)
                    let placement = CaptureControlPlacement.workspace(
                        region: tiny, tools: CGSize(width: 680, height: 168),
                        outputs: CGSize(width: 60, height: 312), screen: screen, gap: 8)
                    precondition(screen.contains(placement.tools) && screen.contains(placement.outputs))
                    precondition(!placement.tools.intersects(placement.outputs))
                }
            }
            let full = CaptureControlPlacement.workspace(
                region: screen, tools: CGSize(width: 680, height: 168),
                outputs: CGSize(width: 60, height: 312), screen: screen, gap: 8)
            precondition(screen.contains(full.tools) && screen.contains(full.outputs))
            precondition(!full.tools.intersects(full.outputs))
        }
        let narrowRegion = CGRect(x: 1050, y: 542, width: 300, height: 160)
        let narrow = CaptureControlPlacement.workspace(region: narrowRegion,
            tools: CGSize(width: 680, height: 40), outputs: CGSize(width: 40, height: 264),
            screen: CGRect(x: 0, y: 0, width: 1728, height: 1117), gap: 8)
        precondition(!narrow.outputs.intersects(narrowRegion), "Output controls obscured a narrow selection")
        precondition(narrow.outputs.minX >= narrow.tools.maxX + 8)
        let leftRegion = narrowRegion.offsetBy(dx: 350, dy: 0)
        let left = CaptureControlPlacement.workspace(region: leftRegion,
            tools: CGSize(width: 680, height: 40), outputs: CGSize(width: 40, height: 264),
            screen: CGRect(x: 0, y: 0, width: 1728, height: 1117), gap: 8)
        precondition(!left.outputs.intersects(leftRegion), "Output controls ignored available space on the left")
        let corner = CaptureControlPlacement.workspace(
            region: CGRect(x: 1670, y: 30, width: 40, height: 50),
            tools: CGSize(width: 680, height: 46), outputs: CGSize(width: 60, height: 236),
            screen: CGRect(x: 0, y: 0, width: 1728, height: 1117), gap: 8)
        precondition(!corner.outputs.intersects(CGRect(x: 1670, y: 30, width: 40, height: 50)))
        precondition(!corner.outputs.intersects(corner.tools))
    }

    static func frame(offset: Int, fixed: Int = 0, lanes: Int = 8) -> ScrollStitchPolicy.Frame {
        var rgb: [UInt8] = []
        for y in 0..<300 {
            for x in 0..<lanes {
                let line = y < fixed ? y : y + offset
                var hash = UInt32(line * 7949 + x * 3571 + 127)
                hash = (hash ^ (hash >> 16)) &* 0x45d9f3b
                for channel in 0..<3 { rgb.append(UInt8(truncatingIfNeeded: hash >> (channel * 8))) }
            }
        }
        return .init(length: 300, lanes: lanes, rgb: rgb)
    }

    static func selection(in root: URL) throws {
        let bounds = CGRect(x: -500, y: 40, width: 1000, height: 800)
        let region = CGRect(x: -400, y: 100, width: 200, height: 300)
        precondition(
            CaptureSelectionGeometry.moved(region, by: .init(width: -900, height: 900), in: bounds)
                == CGRect(x: -500, y: 540, width: 200, height: 300))
        for handle in CaptureSelectionGeometry.Handle.allCases {
            let resized = CaptureSelectionGeometry.resized(
                region, handle: handle, to: CGPoint(x: -999, y: 9999), in: bounds)
            precondition(bounds.contains(resized) && resized.width >= 2 && resized.height >= 2)
        }
        let repository = CaptureRepository(root: root.appendingPathComponent("selection"))
        let directory = try repository.create(id: UUID())
        let raster = UUID().uuidString
        let size = try CapturePixelSize(width: 127, height: 211)
        try CaptureRasterStore.write(
            size: size, to: directory.appendingPathComponent(raster), fillRow: CaptureFixture.fill)
        let first = CGRect(x: 10, y: 20, width: 80, height: 100)
        var document = CaptureDocument(
            id: UUID(), createdAt: Date(), size: try CapturePixelSize(width: 80, height: 100),
            pieces: [.init(raster: raster, source: first, origin: .zero)])
        document.edit.annotations = [
            .init(id: UUID(), tool: .arrow, points: [.init(x: 20, y: 30), .init(x: 50, y: 60)])
        ]
        let original = document
        let screen = CGRect(x: 0, y: 0, width: 63.5, height: 105.5)
        let pixels = CGRect(x: 20, y: 40, width: 60, height: 80)
        let frame = CaptureSelectionGeometry.frame(pixels: pixels, in: screen, scale: 2)
        precondition(CaptureGeometry.pixels(frame, screen: screen, scale: 2) == pixels)
        let replacement = try CaptureSelectionGeometry.reframe(
            document, raster: raster, pixels: pixels,
            oldFrame: CaptureSelectionGeometry.frame(pixels: first, in: screen, scale: 2),
            newFrame: frame, oldScale: 2, scale: 2)
        precondition(replacement.edit.annotations[0].points[0] == CGPoint(x: 10, y: 10))
        var undo = CaptureUndoHistory()
        undo.commit(replacement, to: &document)
        undo.undo(&document)
        precondition(document.pieces == original.pieces && document.edit == original.edit)
        precondition(document.size == original.size && document.id == original.id)
        undo.redo(&document)
        precondition(document.pieces == replacement.pieces && document.edit == replacement.edit)
        let png = root.appendingPathComponent("selection.png")
        try CaptureRenderer.png(document: document, directory: directory, to: png)
        try repository.commit(
            document: document, directory: directory, png: png, editable: true, draft: true)
        let entry = try repository.entries().first!
        let (restored, restoredDirectory) = try repository.open(entry, id: UUID())
        precondition(restored.edit == document.edit && restored.pieces[0].source == restored.bounds)
        let metadata = try CaptureRasterStore.validate(
            at: restoredDirectory.appendingPathComponent(restored.pieces[0].raster))
        precondition(metadata.size == document.size, "Draft retained pixels outside the selected region")
        let before = try CaptureCompositeReader(document: document, directory: directory)
            .read(rect: document.bounds)
        let after = try CaptureCompositeReader(document: restored, directory: restoredDirectory)
            .read(rect: restored.bounds)
        precondition(before == after, "Archiving changed the selected source pixels")
    }

    static func visibility() {
        typealias Window = CaptureVisibilityPolicy.Window
        let target = Window(
            id: 15974, pid: 33510, frame: CGRect(x: 0, y: 33, width: 1728, height: 1084), layer: 0)
        let region = CGRect(x: 25, y: 680, width: 1680, height: 420)
        let cursorLayer = Int(CGWindowLevelForKey(.cursorWindow))
        let cursor = Window(
            id: 2, pid: 179, frame: CGRect(x: 651, y: 666, width: 28, height: 40), layer: cursorLayer)
        let controls = Window(id: 23223, pid: 96190, frame: region, layer: 3)
        let occluder = Window(id: 25, pid: 42, frame: region, layer: 3)
        var transparent = occluder
        transparent.alpha = 0
        func visible(_ windows: [Window], frontmostPID: Int32? = 33510) -> Bool {
            CaptureVisibilityPolicy.assess(
                windowID: target.id, pid: target.pid, frame: target.frame, region: region,
                excludedPIDs: [96190], frontmostPID: frontmostPID,
                cursorLayer: cursorLayer, windows: windows).status == .visible
        }
        precondition(visible([target]))
        precondition(visible([cursor, controls, target]), "A cursor inside the region must not pause capture")
        precondition(visible([transparent, target]))
        precondition(!visible([occluder, target]))
        let sibling = Window(id: 26, pid: target.pid, frame: region, layer: 0)
        precondition(!visible([sibling, target]))
        let outside = Window(id: 27, pid: 42, frame: CGRect(x: -900, y: 0, width: 800, height: 600), layer: 3)
        precondition(visible([outside, target]))
        precondition(visible([target, occluder]))
        precondition(!visible([target], frontmostPID: 42))
        precondition(!visible([target], frontmostPID: nil))
        precondition(!visible([cursor, controls]))
        let moved = Window(id: target.id, pid: target.pid, frame: target.frame.offsetBy(dx: 1, dy: 0), layer: 0)
        precondition(!visible([moved]))
        let hidden = Window(id: target.id, pid: target.pid, frame: target.frame, layer: 0, alpha: 0)
        precondition(!visible([hidden]))
        func assessment(_ windows: [Window], frontmostPID: Int32? = 33510) -> CaptureVisibilityPolicy.Assessment {
            CaptureVisibilityPolicy.assess(
                windowID: target.id, pid: target.pid, frame: target.frame, region: region,
                excludedPIDs: [96190], frontmostPID: frontmostPID, cursorLayer: cursorLayer, windows: windows)
        }
        precondition(assessment([target], frontmostPID: 42).status == .inactive)
        precondition(assessment([moved]).status == .moved)
        precondition(assessment([hidden]).status == .missing)
        let obstruction = assessment([occluder, target])
        precondition(obstruction.status == .obscured && obstruction.obstructingWindow?.id == occluder.id)
        let dock = Window(
            id: 94, pid: 3921, frame: CGRect(x: 0, y: 0, width: 1728, height: 1117),
            layer: Int(CGWindowLevelForKey(.dockWindow)))
        func visibleWithDock(_ window: Window, excludedPIDs: Set<Int32>) -> Bool {
            CaptureVisibilityPolicy.assess(
                windowID: target.id, pid: target.pid, frame: target.frame, region: region,
                excludedPIDs: excludedPIDs, frontmostPID: target.pid, cursorLayer: cursorLayer,
                windows: [window, target]).status == .visible
        }
        precondition(visibleWithDock(dock, excludedPIDs: [96190, dock.pid]))
        precondition(!visibleWithDock(dock, excludedPIDs: [96190]), "Only excluded content may be ignored")
        let floating = Window(id: 96, pid: 42, frame: dock.frame, layer: dock.layer)
        precondition(!visibleWithDock(floating, excludedPIDs: [96190, dock.pid]))
        precondition(!visibleWithDock(dock, excludedPIDs: [96190, dock.pid, target.pid]))

        let chat = Window(id: 31, pid: controls.pid, frame: target.frame, layer: 0)
        let settings = Window(id: 32, pid: controls.pid, frame: region, layer: 0)
        func own(_ windows: [Window], included: Set<UInt32>) -> CaptureVisibilityPolicy.Status {
            CaptureVisibilityPolicy.assess(
                windowID: chat.id, pid: chat.pid, frame: chat.frame, region: region,
                excludedPIDs: [controls.pid], includedWindowIDs: included, frontmostPID: chat.pid,
                cursorLayer: cursorLayer, windows: windows
            ).status
        }
        precondition(own([chat], included: []) == .excluded, "Tinycast's own windows stay out unless taken back")
        precondition(
            own([controls, chat], included: [chat.id]) == .visible,
            "AI Chat taken back is a target, and the capture's own controls over it do not cover it")
        precondition(
            own([settings, chat], included: [chat.id, settings.id]) == .obscured,
            "another of Tinycast's windows taken back covers the region like any app's")
        precondition(
            own([settings, chat], included: [chat.id]) == .visible,
            "one the capture leaves out never shows, so it covers nothing")
        precondition(
            CaptureGeometry.innerPixels(CGRect(x: 10.25, y: 5.5, width: 100.5, height: 50.25), scale: 2)
                == CGRect(x: 21, y: 11, width: 200, height: 100),
            "a region trimmed to a window rounds inward, so it never pokes past the window's edge")
    }

    static func stitching() {
        let first = frame(offset: 0), second = frame(offset: 60)
        precondition(ScrollStitchPolicy.match(previous: first, current: first) == .duplicate)
        precondition(
            ScrollStitchPolicy.match(previous: first, current: second)
                == .append(offset: 60, fixedLeading: 0, fixedTrailing: ScrollStitchPolicy.edgeClearance))
        guard case .reverse = ScrollStitchPolicy.match(previous: second, current: first) else { preconditionFailure("Matched the other way, the shift reads back") }
        precondition(ScrollStitchPolicy.match(previous: first, current: frame(offset: 260)) == .uncertain)
        precondition(
            ScrollStitchPolicy.match(
                previous: frame(offset: 0, fixed: 24), current: frame(offset: 80, fixed: 24))
                == .append(offset: 80, fixedLeading: 24, fixedTrailing: ScrollStitchPolicy.edgeClearance))
        let pattern = frame(offset: 0)
        func repeated(_ offset: Int) -> ScrollStitchPolicy.Frame {
            let rgb = (0..<pattern.length).flatMap { row in
                let index = ((row + offset) % 60) * pattern.lanes * 3
                return Array(pattern.rgb[index..<(index + pattern.lanes * 3)])
            }
            return .init(length: pattern.length, lanes: pattern.lanes, rgb: rgb)
        }
        precondition(ScrollStitchPolicy.match(previous: repeated(0), current: repeated(20)) == .uncertain,
            "Identical repeated rows must not acquire false confidence from local patches")
        let wide = frame(offset: 0, lanes: 32), moved = frame(offset: 60, lanes: 32)
        var sidebar = moved.rgb
        for line in 0..<wide.length {
            for channel in 0..<3 { sidebar[line * 96 + channel] = wide.rgb[line * 96 + channel] }
        }
        precondition(
            ScrollStitchPolicy.match(previous: wide, current: .init(length: 300, lanes: 32, rgb: sidebar))
                == .append(offset: 60, fixedLeading: 0, fixedTrailing: ScrollStitchPolicy.edgeClearance),
            "A sidebar that stays put while the page moves is left out of the match")
    }

    /// What sits still over a moving page: an edge fade, a floating button, a pane that never moves.
    static func stillOverlays() {
        func covered(_ top: Int, fade: (top: Int, bottom: Int) = (0, 0), still: (lanes: Range<Int>, lines: Range<Int>)? = nil)
            -> ScrollStitchPolicy.Frame
        {
            let moving = page(top, length: 800, lanes: 32), fixed = page(5_000, length: 800, lanes: 32)
            var rgb = moving.rgb
            for line in 0..<800 {
                let depth = line < fade.top ? fade.top - line : line >= 800 - fade.bottom ? line - (799 - fade.bottom) : 0
                let edge = line < fade.top ? fade.top : fade.bottom
                for lane in 0..<32 {
                    for channel in 0..<3 {
                        let index = (line * 32 + lane) * 3 + channel
                        if let still, still.lanes.contains(lane), still.lines.contains(line) {
                            rgb[index] = fixed.rgb[index]
                        } else if depth > 0 {
                            rgb[index] = UInt8(Int(rgb[index]) + (255 - Int(rgb[index])) * depth / (edge + 1))
                        }
                    }
                }
            }
            return .init(length: 800, lanes: 32, rgb: rgb)
        }
        guard case .append(150, _, let trailing) =
            ScrollStitchPolicy.match(previous: covered(0, fade: (0, 60)), current: covered(150, fade: (0, 60)))
        else { preconditionFailure("A fade over the bottom edge moves with neither the page nor the screen") }
        precondition(
            (60...120).contains(trailing - ScrollStitchPolicy.edgeClearance),
            "and is replaced from the next frame, so no seam keeps the faded lines: \(trailing)")
        guard case .append(150, _, _) =
            ScrollStitchPolicy.match(previous: covered(0, fade: (48, 48)), current: covered(150, fade: (48, 48)))
        else { preconditionFailure("Fades over both edges leave the middle to register") }
        let button = (lanes: 20..<23, lines: 500..<580)
        precondition(
            ScrollStitchPolicy.match(previous: covered(0, still: button), current: covered(150, still: button))
                == .append(offset: 150, fixedLeading: 0, fixedTrailing: ScrollStitchPolicy.edgeClearance),
            "A floating button stays put while the page passes beneath it")
        let sidebar = (lanes: 0..<14, lines: 0..<800)
        precondition(
            ScrollStitchPolicy.match(previous: covered(0, still: sidebar), current: covered(150, still: sidebar))
                == .append(offset: 150, fixedLeading: 0, fixedTrailing: ScrollStitchPolicy.edgeClearance),
            "A sidebar nearly half the window wide stays out of the search and the match")
        let wide = (lanes: 0..<22, lines: 0..<800)
        guard case .append(150, _, _) =
            ScrollStitchPolicy.match(previous: covered(0, still: wide), current: covered(150, still: wide))
        else { preconditionFailure("A sidebar holding seven in ten windows still leaves the page to vouch for the shift") }
        let pane = (lanes: 0..<27, lines: 0..<800)
        if case .append = ScrollStitchPolicy.match(previous: covered(0, still: pane), current: covered(150, still: pane)) {
            preconditionFailure("Past four in five held still, the windows that moved are too few to trust")
        }
        var patch = covered(0, still: (lanes: 0..<32, lines: 0..<800)).rgb
        let moved = covered(150).rgb
        for line in 300..<348 {
            for channel in 0..<3 { patch[(line * 32 + 31) * 3 + channel] = moved[(line * 32 + 31) * 3 + channel] }
        }
        let patched = ScrollStitchPolicy.match(
            previous: covered(0, still: (lanes: 0..<32, lines: 0..<800)), current: .init(length: 800, lanes: 32, rgb: patch))
        if case .append = patched {
            preconditionFailure("A patch a few windows tall is too little that moved to vouch for any shift")
        }
    }

    /// A page taller than any frame, so a frame can be cut at any scroll position.
    static func page(_ top: Int, length: Int = 300, lanes: Int = 8, changed: Range<Int>? = nil)
        -> ScrollStitchPolicy.Frame
    {
        var rgb: [UInt8] = []
        for y in 0..<length {
            for x in 0..<lanes {
                var hash = UInt32((y + top) * 7949 + x * 3571 + 127)
                hash = (hash ^ (hash >> 16)) &* 0x45d9f3b
                for channel in 0..<3 {
                    // A hover lights one lane's short run in place; the page under it did not move.
                    let lit = changed?.contains(y) == true && x == 2
                    rgb.append(lit ? 250 : UInt8(truncatingIfNeeded: hash >> (channel * 8)))
                }
            }
        }
        return .init(length: length, lanes: lanes, rgb: rgb)
    }

    static func tracking() {
        var hovered = page(120, length: 800, changed: 280..<320), still = page(0, length: 800)
        precondition(
            ScrollStitchPolicy.match(previous: still, current: hovered) == .uncertain,
            "Content that changed in place is a mismatch like any other")
        hovered.pointer = 300
        still.pointer = 300
        precondition(
            ScrollStitchPolicy.match(previous: still, current: hovered)
                == .append(offset: 120, fixedLeading: 0, fixedTrailing: ScrollStitchPolicy.edgeClearance),
            "unless the pointer is over it, where a hover lights whatever passes beneath")
        var lit = page(120, lanes: 32).rgb
        for line in 0..<300 {
            for channel in 0..<3 { lit[(line * 32 + 5) * 3 + channel] = page(0, lanes: 32).rgb[(line * 32 + 5) * 3 + channel] }
        }
        precondition(
            ScrollStitchPolicy.match(previous: page(0, lanes: 32), current: .init(length: 300, lanes: 32, rgb: lit))
                == .append(offset: 120, fixedLeading: 0, fixedTrailing: ScrollStitchPolicy.edgeClearance),
            "A lane that never moves is a fixed sidebar, left out while the rest lines up")

        func sparse(_ top: Int) -> ScrollStitchPolicy.Frame {
            var rgb: [UInt8] = []
            for y in 0..<300 {
                for x in 0..<8 {
                    let line = y + top
                    var hash = UInt32((line / 23) * 7949 + x * 3571 + 127)
                    hash = (hash ^ (hash >> 16)) &* 0x45d9f3b
                    rgb += [UInt8](repeating: line % 23 < 3 && hash % 3 != 0 ? 220 : 30, count: 3)
                }
            }
            return .init(length: 300, lanes: 8, rgb: rgb)
        }
        guard case .append(150, _, _) = ScrollStitchPolicy.match(previous: sparse(0), current: sparse(150)) else {
            preconditionFailure("Sparse lines on a plain page register")
        }
        precondition(
            ScrollStitchPolicy.match(previous: sparse(0), current: sparse(195)) == .uncertain,
            "A shift one line past the search range is never taken a line short, however little that line differs")

        var tracker = ScrollTracker<Int>()
        func observe(_ top: Int) -> [ScrollTracker<Int>.Step] {
            tracker.observe(page(top), payload: top, match: ScrollStitchPolicy.match)
        }
        func commits(_ steps: [ScrollTracker<Int>.Step]) -> [Int?] {
            steps.compactMap { if case .commit(let strip) = $0 { strip.offset } else { nil } }
        }
        precondition(observe(0).isEmpty, "A first frame alone never starts a capture")
        precondition(commits(observe(0)) == [nil], "Content at rest starts it whole")
        // One flick moves 600 lines in steps of 150; a frame reaches back about 194.
        var written: [Int?] = []
        for top in [150, 300, 450, 600] { written += commits(observe(top)) }
        precondition(
            written == [150, 150, 150], "The last frame that still lines up is written before the overlap is lost")
        precondition(tracker.pending?.payload == 600, "and the newest waits")
        precondition(commits(observe(600)) == [150], "Rest writes what was waiting")
        precondition(observe(600).isEmpty, "and nothing more while nothing moves")

        precondition(observe(1100).isEmpty, "A frame too far to line up says nothing at first")
        let lost = observe(1200)
        precondition(lost.contains { if case .lost = $0 { true } else { false } }, "A run of them says it lost the overlap")
        let found = observe(700)
        precondition(
            found.contains { if case .found = $0 { true } else { false } } && tracker.pending?.payload == 700,
            "Scrolling back within reach finds it again, and goes on from there")

        precondition(observe(760).isEmpty && observe(730).isEmpty, "Moving on, then back a little")
        precondition(tracker.pending?.payload == 760, "keeps the furthest frame waiting")
        precondition(tracker.flush()?.offset == 160 && tracker.pending == nil, "Finishing writes what was waiting")
        precondition(
            observe(650).contains { if case .backward = $0 { true } else { false } },
            "Scrolling above the last strip asks to scroll forward")
    }

    static func liveFrames(in root: URL) throws {
        let width = 40, height = 120
        var pixels = [UInt8](repeating: 255, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                for channel in 0..<3 { pixels[(y * width + x) * 4 + channel] = UInt8((y * 2 + x + channel * 7) % 256) }
            }
        }
        let provider = CGDataProvider(data: Data(pixels) as CFData)!
        let image = CGImage(
            width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue), provider: provider,
            decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
        let frame = try ScrollFrameReader.sample(image, axis: .vertical)
        precondition(frame.length == height && frame.lanes == 10, "A frame keeps every line and a lane per four columns")
        let margin = ScrollFrameReader.edgeMargin(cross: width)
        precondition(
            margin > 0 && Array(frame.originalRGB?[0..<3] ?? []) == Array(pixels[margin * 4..<(margin * 4 + 3)]),
            "Its first line is the image's top row, read clear of the edge an overlay scroller crosses")
        let last = (width - 1 - margin) * 4
        precondition(
            Array(frame.originalRGB?[(frame.lanes - 1) * 3..<frame.lanes * 3] ?? []) == Array(pixels[last..<(last + 3)]),
            "and its last lane stays as far from the trailing edge")
        let wide = try ScrollFrameReader.sample(image, axis: .horizontal)
        precondition(wide.length == width, "A sideways frame runs along the columns")
        let directory = root.appendingPathComponent("live-strip")
        try ScrollFrameReader.strip(image, rect: CGRect(x: 0, y: 80, width: width, height: 40), to: directory)
        let reader = try CaptureRasterReader(directory: directory)
        var row = [UInt8](repeating: 0, count: reader.raster.size.rowBytes)
        try row.withUnsafeMutableBytes { try reader.read(row: 0, into: $0) }
        precondition(
            reader.raster.size.height == 40 && Array(row[0..<3]) == Array(pixels[(80 * width) * 4..<(80 * width) * 4 + 3]),
            "A strip cut from a live frame starts at the line it was cut from")
        do {
            try ScrollFrameReader.strip(image, rect: CGRect(x: 0, y: 100, width: width, height: 40), to: directory)
            preconditionFailure("a strip past the frame was written")
        } catch CaptureRasterError.invalidRow {}
    }

    static func strips(in root: URL) throws {
        for axis in CaptureDocument.Axis.allCases {
            let repository = CaptureRepository(root: root.appendingPathComponent(axis.rawValue))
            let directory = try repository.create(id: UUID())
            let vertical = axis == .vertical
            let size = try CapturePixelSize(width: vertical ? 41 : 120, height: vertical ? 120 : 41)
            var document = CaptureDocument(id: UUID(), createdAt: Date(), size: size, pieces: [], axis: axis)
            for offset in [0, 30, 60] {
                let frame = directory.appendingPathComponent("frame-\(offset)")
                try CaptureRasterStore.write(size: size, to: frame) { y, output in
                    for x in 0..<size.width {
                        let line = vertical ? y : x
                        let value = line < 10 ? 240 : line >= 110 ? 250 : line + offset
                        for channel in 0..<3 { output[x * 4 + channel] = UInt8(value) }
                        output[x * 4 + 3] = 255
                    }
                }
                let raster = UUID().uuidString
                let plan = try CaptureScrollAppend.plan(
                    document: document, frame: size, raster: raster, offset: offset == 0 ? nil : 30,
                    trailing: offset == 0 ? 0 : 10)
                try ScrollFrameReader.strip(
                    from: frame, rect: plan.source, to: directory.appendingPathComponent(raster))
                document = plan.document
            }
            precondition((vertical ? document.size.height : document.size.width) == 180)
            let pixels = try CaptureCompositeReader(document: document, directory: directory).read(
                rect: document.bounds)
            for y in 0..<document.size.height {
                for x in 0..<document.size.width {
                    let line = vertical ? y : x
                    precondition(
                        pixels[(y * document.size.width + x) * 4]
                            == UInt8(line < 10 ? 240 : line >= 170 ? 250 : line))
                }
            }
            var gap = document
            gap.pieces[1].origin = .zero
            do {
                _ = try gap.validated(); preconditionFailure("overlapping strips accepted")
            } catch CaptureRasterError.invalidTile {}
        }
    }

    static func leases(in root: URL) throws {
        let repository = CaptureRepository(root: root.appendingPathComponent("leases"))
        let live = try repository.create(id: UUID())
        var source: CaptureSource? = try CaptureSource(directory: live)
        let abandoned = try repository.create(id: UUID())
        try withExtendedLifetime(source) {
            try repository.reclaimAbandonedSessions(before: Date().addingTimeInterval(1))
            precondition(FileManager.default.fileExists(atPath: live.path))
            precondition(!FileManager.default.fileExists(atPath: abandoned.path))
        }
        source = nil
        precondition(!FileManager.default.fileExists(atPath: live.path))
    }

    static func output(in root: URL) throws {
        let repository = CaptureRepository(root: root)
        let id = UUID(), raster = UUID().uuidString
        let directory = try repository.create(id: id)
        let size = try CapturePixelSize(width: 127, height: 211)
        let source = directory.appendingPathComponent(raster)
        try CaptureRasterStore.write(size: size, to: source, fillRow: CaptureFixture.fill)
        var document = CaptureDocument(
            id: id, createdAt: Date(), size: size,
            pieces: [
                .init(
                    raster: raster, source: CGRect(x: 0, y: 0, width: size.width, height: size.height),
                    origin: .zero)
            ])
        let output = root.appendingPathComponent("image.png")
        try CaptureRenderer.png(document: document, directory: directory, to: output)
        try CaptureFixture.verifyPNG(at: output, size: size)
        let imported = root.appendingPathComponent("imported")
        let importedSize = try CaptureImageSource.load(output, at: imported)
        precondition(importedSize == size)
        let roundTrip = root.appendingPathComponent("roundtrip.png")
        try CapturePNGWriter.write(raster: imported, to: roundTrip)
        try CaptureFixture.verifyPNG(at: roundTrip, size: size)
        let cgImage = CGImageSourceCreateImageAtIndex(
            CGImageSourceCreateWithURL(output as CFURL, nil)!, 0, nil)!
        let captured = root.appendingPathComponent("captured")
        _ = try CaptureImageSource.store(cgImage, at: captured)
        try CapturePNGWriter.write(raster: captured, to: roundTrip)
        try CaptureFixture.verifyPNG(at: roundTrip, size: size)
        var undo = CaptureUndoHistory(), edit = document.edit
        edit.annotations = [
            .init(id: UUID(), tool: .cover, points: [CGPoint(x: 5, y: 9), CGPoint(x: 40, y: 70)])
        ]
        edit.crop = CGRect(x: 5, y: 9, width: 60, height: 80)
        undo.commit(edit, to: &document)
        precondition(document.revision == 1 && document.needsPreservation)
        undo.undo(&document)
        precondition(document.edit.isEmpty && document.revision == 2)
        undo.redo(&document)
        precondition(document.edit == edit && document.revision == 3)
        try CaptureRenderer.png(document: document, directory: directory, to: output)
        let image = CGImageSourceCreateImageAtIndex(
            CGImageSourceCreateWithURL(output as CFURL, nil)!, 0, nil)!
        precondition(image.width == 60 && image.height == 80)
        let pixels = image.dataProvider!.data! as Data
        precondition(pixels[0] == 0 && pixels[1] == 0 && pixels[2] == 0 && pixels[3] == 255)
        try lossyExports(document: document, directory: directory, in: root)
        try repository.commit(
            document: document, directory: directory, png: output, editable: false, draft: false)
        let entries = try repository.entries()
        precondition(entries.count == 1 && !entries[0].editable)
        let (reopened, _) = try repository.open(entries[0], id: UUID())
        precondition(reopened.edit.isEmpty && reopened.size.width == 60)
        try repository.commit(
            document: document, directory: directory, png: output, editable: true, draft: true)
        let draft = try repository.entries().first { $0.draft }!
        let (editable, _) = try repository.open(draft, id: UUID())
        precondition(editable.edit == edit)
        let savedSource = repository.history.appendingPathComponent("\(draft.id)/source/\(raster)/0-0.rgba")
        try FileManager.default.removeItem(at: savedSource)
        let (safeFallback, fallbackDirectory) = try repository.open(draft, id: UUID())
        precondition(safeFallback.edit.isEmpty && safeFallback.size.width == 60)
        let safePixels = try CaptureCompositeReader(document: safeFallback, directory: fallbackDirectory)
            .read(rect: safeFallback.bounds)
        precondition(safePixels[0] == 0 && safePixels[3] == 255)
        try repository.prune(now: Date().addingTimeInterval(864_000), days: 7, maximumBytes: 512 * 1_048_576)
        let remaining = try repository.entries()
        precondition(remaining.count == 1)
    }

    static func lossyExports(document: CaptureDocument, directory: URL, in root: URL) throws {
        for format in CaptureRenderer.exportFormats where format != .png {
            let output = root.appendingPathComponent("cropped.\(format.rawValue)")
            let options = CaptureExportOptions(format: format)
            try CaptureRenderer.export(document: document, directory: directory, to: output, options: options)
            let source = CGImageSourceCreateWithURL(output as CFURL, nil)!
            precondition(CGImageSourceGetType(source)! as String == format.identifier)
            let image = CGImageSourceCreateImageAtIndex(source, 0, nil)!
            precondition(image.width == 60 && image.height == 80)
            let context = CGContext(
                data: nil, width: 60, height: 80, bitsPerComponent: 8, bytesPerRow: 240,
                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.draw(image, in: CGRect(x: 0, y: 0, width: 60, height: 80))
            let decoded = context.data!.assumingMemoryBound(to: UInt8.self)
            for y in 8..<48 {
                for x in 8..<24 {
                    let offset = (y * 60 + x) * 4
                    precondition((0..<3).allSatisfy { decoded[offset + $0] <= 8 })
                    precondition(decoded[offset + 3] == 255)
                }
            }
            let saved = try Data(contentsOf: output)
            let oversized = CaptureDocument(
                id: UUID(), createdAt: Date(), size: try CapturePixelSize(width: 2001, height: 2000),
                pieces: [])
            do {
                try CaptureRenderer.export(
                    document: oversized, directory: directory, to: output, options: options)
                preconditionFailure("oversized lossy export accepted")
            } catch CaptureExportOptions.Failure.encodingBudget {}
            let preserved = try Data(contentsOf: output)
            precondition(preserved == saved)
        }
        var retina = document
        retina.captureScale = 2
        let original = try CaptureExportOptions().dimensions(for: retina)
        precondition(original.width == 60 && original.height == 80)
        for scale in CaptureExportOptions.Scale.allCases {
            let options = CaptureExportOptions(scale: scale, profile: .displayP3)
            let size = try options.dimensions(for: retina)
            let output = root.appendingPathComponent("scaled-\(scale.rawValue).png")
            try CaptureRenderer.export(document: retina, directory: directory, to: output, options: options)
            let source = CGImageSourceCreateWithURL(output as CFURL, nil)!
            let image = CGImageSourceCreateImageAtIndex(source, 0, nil)!
            precondition(image.width == size.width && image.height == size.height)
            precondition(image.colorSpace?.name == CGColorSpace.displayP3)
            let divisor = scale == .quarter ? 4 : scale == .original ? 1 : 2
            precondition(size.width == 60 / divisor && size.height == 80 / divisor)
        }
        let withoutScale = try CaptureExportOptions(scale: .oneX).dimensions(for: document)
        precondition(withoutScale == original)
    }

    static func alphaRoundTrip(in root: URL) throws {
        let size = try CapturePixelSize(width: 3, height: 1), raster = UUID().uuidString
        let pixels: [UInt8] = [255, 128, 64, 128, 19, 27, 51, 255, 255, 255, 255, 0]
        try CaptureRasterStore.write(size: size, to: root.appendingPathComponent(raster)) { _, buffer in
            pixels.withUnsafeBytes { buffer.copyMemory(from: $0) }
        }
        let document = CaptureDocument(
            id: UUID(), createdAt: Date(), size: size,
            pieces: [.init(raster: raster, source: CGRect(x: 0, y: 0, width: 3, height: 1), origin: .zero)])
        let output = root.appendingPathComponent("alpha-roundtrip.png")
        try CaptureRenderer.png(document: document, directory: root, to: output)
        let reader = try CapturePNGReader(url: output)
        var decoded = [UInt8](repeating: 0, count: size.rowBytes)
        try decoded.withUnsafeMutableBytes { try reader.read(row: 0, into: $0) }
        precondition(decoded[3] == 128 && decoded[7] == 255 && decoded[11] == 0)
        precondition((0..<3).allSatisfy { abs(Int(decoded[$0]) - Int(pixels[$0])) <= 1 })
        precondition(Array(decoded[4..<8]) == Array(pixels[4..<8]))
        precondition(Array(decoded[8..<12]) == [0, 0, 0, 0])
        var invalid = [UInt8](repeating: 0, count: 3)
        do {
            try invalid.withUnsafeMutableBytes { try CapturePixelAlpha.unpremultiply($0) }
            preconditionFailure("An incomplete RGBA pixel was accepted")
        } catch CaptureRasterError.invalidRow {}
    }

    static func annotationStyles(in root: URL) throws {
        let size = try CapturePixelSize(width: 128, height: 128), raster = UUID().uuidString
        try CaptureRasterStore.write(size: size, to: root.appendingPathComponent(raster)) { _, buffer in
            buffer.initializeMemory(as: UInt8.self, repeating: 255)
        }
        var document = CaptureDocument(
            id: UUID(), createdAt: Date(), size: size,
            pieces: [.init(raster: raster, source: CGRect(x: 0, y: 0, width: 128, height: 128), origin: .zero)])
        var rectangle = CaptureAnnotation(id: UUID(), tool: .rectangle,
            points: [.init(x: 20, y: 20), .init(x: 60, y: 40)], rotation: 90, filled: true)
        precondition(abs(rectangle.bounds.width - 20) < 0.001 && abs(rectangle.bounds.height - 40) < 0.001)
        document.edit.annotations = [rectangle]
        let output = root.appendingPathComponent("styled.png")
        func pixel(_ x: Int, _ y: Int) throws -> [UInt8] {
            try CaptureRenderer.png(document: document, directory: root, to: output)
            let reader = try CapturePNGReader(url: output)
            var row = [UInt8](repeating: 0, count: size.rowBytes)
            for index in 0...y {
                try row.withUnsafeMutableBytes { try reader.read(row: index, into: $0) }
            }
            return Array(row[(x * 4)..<(x * 4 + 4)])
        }
        let inside = try pixel(40, 15), outside = try pixel(25, 30)
        precondition(inside[0] > 230 && inside[1] < 70 && inside[3] == 255)
        precondition(outside == [255, 255, 255, 255])
        document.edit.annotations = [.init(id: UUID(), tool: .curvedArrow,
            points: [.init(x: 10, y: 20), .init(x: 110, y: 20)])]
        let bent = try pixel(60, 32), straight = try pixel(60, 20)
        precondition(bent[0] > 230 && bent[1] < 80 && straight == [255, 255, 255, 255])
        document.edit.annotations = [.init(id: UUID(), tool: .highlighter,
            points: [.init(x: 10, y: 80), .init(x: 100, y: 80)])]
        let highlighted = try pixel(50, 80)
        precondition(highlighted[0] > 240 && (170...220).contains(highlighted[1]) && highlighted[3] == 255)
        let encoded = try JSONEncoder().encode(rectangle)
        let decoded = try JSONDecoder().decode(CaptureAnnotation.self, from: encoded)
        precondition(decoded == rectangle)
        rectangle.rotation = .nan
        precondition(!rectangle.isValid)
        rectangle.rotation = 0; rectangle.fontSize = -1
        precondition(!rectangle.isValid)
    }

    static func emoji(in root: URL) throws {
        let size = try CapturePixelSize(width: 1080, height: 200), raster = UUID().uuidString
        try CaptureRasterStore.write(size: size, to: root.appendingPathComponent(raster)) { _, buffer in
            buffer.initializeMemory(as: UInt8.self, repeating: 255)
        }
        var document = CaptureDocument(id: UUID(), createdAt: Date(), size: size,
            pieces: [.init(raster: raster, source: CGRect(x: 0, y: 0, width: 1080, height: 200), origin: .zero)])
        var emoji = CaptureAnnotation(id: UUID(), tool: .emoji, points: [.init(x: 1040, y: 150)], text: "🙂")
        emoji.sizeEmoji(64, in: document.bounds)
        precondition(emoji.isValid && document.bounds.contains(emoji.bounds))
        precondition(emoji.bounds == CGRect(x: 984, y: 104, width: 96, height: 96))
        document.edit.annotations = [emoji]
        let image = try CaptureRenderer.image(document: document, directory: root, rect: document.bounds)
        let pixels = image.dataProvider!.data! as Data
        var yellow = 0, colors = Set<UInt32>()
        for offset in stride(from: 0, to: pixels.count, by: 4) {
            let red = pixels[offset], green = pixels[offset + 1], blue = pixels[offset + 2]
            if red > 180 && green > 100 && blue < 80 { yellow += 1 }
            if red != green || green != blue { colors.insert(UInt32(red) << 16 | UInt32(green) << 8 | UInt32(blue)) }
        }
        precondition(yellow > 300 && colors.count > 50, "Emoji must retain Apple Color Emoji pixels")
        let preview = try CaptureRenderer.preview(document: document, directory: root, maximum: size.width)
        precondition(preview.dataProvider!.data! as Data == pixels, "Emoji must match across preview tiles")
        let output = root.appendingPathComponent("emoji.png")
        try CaptureRenderer.png(document: document, directory: root, to: output)
        let reader = try CapturePNGReader(url: output)
        var row = [UInt8](repeating: 0, count: size.rowBytes)
        for y in 0..<size.height {
            try row.withUnsafeMutableBytes { try reader.read(row: y, into: $0) }
            precondition(row.elementsEqual(pixels[(y * size.rowBytes)..<((y + 1) * size.rowBytes)]))
        }
        emoji.sizeEmoji(768, in: CGRect(x: 29_970, y: 29_970, width: 30, height: 30))
        precondition(emoji.isValid && emoji.fontSize == 20 && emoji.bounds.maxX == 30_000)
        let decoded = try JSONDecoder().decode(CaptureDocument.self, from: JSONEncoder().encode(document))
        precondition(decoded == document)
    }

    static func imageAdjustments(in root: URL) throws {
        let size = try CapturePixelSize(width: 1031, height: 67), raster = UUID().uuidString
        try CaptureRasterStore.write(size: size, to: root.appendingPathComponent(raster)) { y, buffer in
            for x in 0..<size.width {
                buffer[x * 4] = UInt8((x * 13 + y * 7) % 256)
                buffer[x * 4 + 1] = UInt8((x * 9 + y * 11) % 256)
                buffer[x * 4 + 2] = UInt8((x * 3 + y * 17) % 256)
                buffer[x * 4 + 3] = 255
            }
        }
        var document = CaptureDocument(id: UUID(), createdAt: Date(), size: size,
            pieces: [.init(raster: raster, source: CGRect(x: 0, y: 0, width: size.width, height: size.height), origin: .zero)])
        let reader = try CaptureCompositeReader(document: document, directory: root)
        let rect = CGRect(x: 7, y: 9, width: 5, height: 4)
        let original = try reader.read(rect: rect)
        let inverted = try CaptureImageProcessing.pixels(reader: reader, rect: rect, bounds: document.bounds,
            adjustments: .init(inverted: true))
        let monochrome = try CaptureImageProcessing.pixels(reader: reader, rect: rect, bounds: document.bounds,
            adjustments: .init(saturation: 0))
        let flat = try CaptureImageProcessing.pixels(reader: reader, rect: rect, bounds: document.bounds,
            adjustments: .init(contrast: 0))
        for offset in stride(from: 0, to: original.count, by: 4) {
            let luma = Double(original[offset]) * 0.2126 + Double(original[offset + 1]) * 0.7152
                + Double(original[offset + 2]) * 0.0722
            for channel in 0..<3 {
                precondition(inverted[offset + channel] == 255 - original[offset + channel])
                precondition(abs(Double(monochrome[offset + channel]) - luma) <= 1)
                precondition(flat[offset + channel] == 128)
            }
            precondition(inverted[offset + 3] == 255 && monochrome[offset + 3] == 255 && flat[offset + 3] == 255)
        }
        let adjustments = CaptureImageAdjustments(brightness: 0.1, contrast: 0.8, saturation: 1.3, sharpness: 0.7, inverted: true)
        document.edit.adjustments = adjustments
        let full = try CaptureRenderer.image(document: document, directory: root, rect: document.bounds)
        let fullPixels = full.dataProvider!.data! as Data
        let preview = try CaptureRenderer.preview(document: document, directory: root, maximum: size.width)
        let previewPixels = preview.dataProvider!.data! as Data
        precondition(fullPixels == previewPixels, "adjustments must not create seams at preview tile boundaries")
        let output = root.appendingPathComponent("adjustments.png")
        try CaptureRenderer.png(document: document, directory: root, to: output)
        let png = try CapturePNGReader(url: output)
        var row = [UInt8](repeating: 0, count: size.rowBytes)
        for y in 0..<size.height {
            try row.withUnsafeMutableBytes { try png.read(row: y, into: $0) }
            precondition(row.elementsEqual(fullPixels[(y * size.rowBytes)..<((y + 1) * size.rowBytes)]),
                "streaming export must equal preview, including sharpness at each band edge")
        }
        document.edit.annotations = [.init(id: UUID(), tool: .cover, points: [.init(x: 0, y: 0), .init(x: 30, y: 30)])]
        let covered = try CaptureRenderer.image(document: document, directory: root,
            rect: CGRect(x: 0, y: 0, width: 1, height: 1))
        precondition(Array(covered.dataProvider!.data! as Data) == [0, 0, 0, 255])
        let encoded = try JSONEncoder().encode(document)
        let restored = try JSONDecoder().decode(CaptureDocument.self, from: encoded).validated()
        precondition(restored == document)
        document.edit.adjustments?.brightness = .nan
        do {
            _ = try document.validated()
            preconditionFailure("invalid adjustment accepted")
        } catch CaptureRasterError.invalidTile {}
        document.edit = .init()
        var undo = CaptureUndoHistory()
        undo.begin(document)
        for step in 1...20 {
            undo.commit(.init(adjustments: .init(brightness: Double(step) / 100)), to: &document)
        }
        undo.end(document)
        precondition(undo.canUndo && document.needsPreservation)
        undo.undo(&document)
        precondition(document.edit.isEmpty && !undo.canUndo)
        undo.redo(&document)
        precondition(document.edit.adjustments?.brightness == 0.2)
        undo.begin(document)
        let previous = document.edit
        undo.commit(.init(adjustments: .init(brightness: 0.7)), to: &document)
        undo.commit(previous, to: &document)
        undo.end(document)
        undo.undo(&document)
        precondition(document.edit.isEmpty && !undo.canUndo, "a drag ending at its initial value must not add undo")
        let alphaSize = try CapturePixelSize(width: 3, height: 1), alphaRaster = UUID().uuidString
        try CaptureRasterStore.write(size: alphaSize, to: root.appendingPathComponent(alphaRaster)) { _, buffer in
            let rgba: [UInt8] = [20, 40, 60, 0, 80, 100, 120, 127, 140, 160, 180, 255]
            rgba.withUnsafeBytes { buffer.copyMemory(from: $0) }
        }
        let alphaDocument = CaptureDocument(id: UUID(), createdAt: Date(), size: alphaSize,
            pieces: [.init(raster: alphaRaster, source: CGRect(x: 0, y: 0, width: 3, height: 1), origin: .zero)])
        let alphaReader = try CaptureCompositeReader(document: alphaDocument, directory: root)
        let alpha = try CaptureImageProcessing.pixels(reader: alphaReader, rect: alphaDocument.bounds,
            bounds: alphaDocument.bounds, adjustments: adjustments)
        precondition(alpha[3] == 0 && alpha[7] == 127 && alpha[11] == 255)
    }

    static func previewSeams(in root: URL) throws {
        let size = try CapturePixelSize(width: 1537, height: 1103)
        let raster = UUID().uuidString
        try CaptureRasterStore.write(size: size, to: root.appendingPathComponent(raster)) { _, buffer in
            for offset in stride(from: 0, to: buffer.count, by: 4) {
                buffer[offset] = 33
                buffer[offset + 1] = 97
                buffer[offset + 2] = 201
                buffer[offset + 3] = 255
            }
        }
        var document = CaptureDocument(
            id: UUID(), createdAt: Date(), size: size,
            pieces: [.init(raster: raster, source: CGRect(x: 0, y: 0, width: 1537, height: 1103), origin: .zero)])
        document.edit.crop = CGRect(x: 17, y: 23, width: 1499, height: 1079)
        let preview = try CaptureRenderer.preview(document: document, directory: root)
        let pixels = preview.dataProvider!.data! as Data
        for offset in stride(from: 0, to: pixels.count, by: 4) {
            precondition(pixels[offset + 3] == 255, "preview left a translucent tile seam")
            precondition(pixels[offset] == 33 && pixels[offset + 1] == 97 && pixels[offset + 2] == 201)
        }
    }
}
