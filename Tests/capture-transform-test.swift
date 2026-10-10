import CoreGraphics
import Foundation

@main
struct CaptureTransformTests {
    static func expect(_ condition: Bool, _ message: String = "Capture transform assertion failed") {
        guard !condition else { return }
        FileHandle.standardError.write(Data((message + "\n").utf8))
        fatalError(message)
    }

    static func main() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("capture-transform-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let raster = UUID().uuidString, sourceSize = try CapturePixelSize(width: 1171, height: 101)
        try CaptureRasterStore.write(size: sourceSize, to: root.appendingPathComponent(raster)) { y, row in
            for x in 0..<sourceSize.width {
                row[x * 4] = UInt8((x * 7 + y * 3) % 255)
                row[x * 4 + 1] = UInt8((x * 5 + y * 11) % 255)
                row[x * 4 + 2] = UInt8((x * 13 + y * 2) % 255)
                row[x * 4 + 3] = 255
            }
        }
        for axis in CaptureDocument.Axis.allCases {
            var document = CaptureDocument(id: UUID(), createdAt: Date(),
                size: try CapturePixelSize(width: 1111, height: 81), pieces: [], axis: axis)
            if axis == .horizontal {
                document.pieces = [
                    .init(raster: raster, source: .init(x: 19, y: 7, width: 600, height: 81), origin: .zero),
                    .init(raster: raster, source: .init(x: 619, y: 7, width: 511, height: 81), origin: .init(x: 600, y: 0))]
            } else {
                document.pieces = [
                    .init(raster: raster, source: .init(x: 19, y: 7, width: 1111, height: 37), origin: .zero),
                    .init(raster: raster, source: .init(x: 19, y: 44, width: 1111, height: 44), origin: .init(x: 0, y: 37))]
            }
            document.edit.crop = CGRect(x: 11, y: 5, width: 1081, height: 71)
            document.edit.annotations = [
                .init(id: UUID(), tool: .pixelate, points: [.init(x: 995, y: 9), .init(x: 1067, y: 70)]),
                .init(id: UUID(), tool: .cover, points: [.init(x: 1040, y: 15), .init(x: 1100, y: 66)]),
                .init(id: UUID(), tool: .rectangle, points: [.init(x: 13, y: 11), .init(x: 59, y: 36)], filled: true)]
            let original = try pixels(document, at: root)
            for direction in CaptureDocument.Axis.allCases {
                let flipped = try CaptureReflection.flip(document, axis: direction)
                try compare(original, document: document, flipped: flipped, direction: direction, at: root)
                let archive = root.appendingPathComponent(UUID().uuidString)
                try FileManager.default.createDirectory(at: archive, withIntermediateDirectories: false)
                let archived = try CaptureSourceArchive.copy(document: flipped, from: root, to: archive)
                let archivedPixels = try pixels(archived, at: archive), flippedPixels = try pixels(flipped, at: root)
                expect(archivedPixels == flippedPixels, "Archive must retain reflection")
                let unflipped = try CaptureReflection.flip(flipped, axis: direction)
                expect(unflipped == document, "Two flips restore all edits")
                var restored = document, undo = CaptureUndoHistory()
                undo.commit(flipped, to: &restored)
                undo.undo(&restored)
                expect(restored.pieces == document.pieces && restored.edit == document.edit)
                undo.redo(&restored)
                expect(restored.pieces == flipped.pieces && restored.edit == flipped.edit)
                let decoded = try JSONDecoder().decode(CaptureDocument.self, from: JSONEncoder().encode(flipped)).validated()
                expect(decoded == flipped)
            }
        }
        try reframing(raster: raster)
        try magnifier(at: root)
        try imageLayers(at: root)
        try composition(at: root)
        try backgroundMask(at: root)
        try presentation(raster: raster, size: sourceSize, at: root)
        try translation(raster: raster, size: sourceSize, at: root)
        try displays(at: root)
        print("Capture reflection preserves pixels, covers, crops, strip order, archives, selection geometry and undo")
    }

    static func displays(at root: URL) throws {
        let displays: [CaptureDisplayComposition.Display] = [
            .init(id: 1, frame: CGRect(x: -100, y: 25, width: 100, height: 50), scale: 1),
            .init(id: 2, frame: CGRect(x: 0, y: 0, width: 100, height: 100), scale: 2)]
        let layout = try CaptureDisplayComposition.layout(
            region: CGRect(x: -50, y: 10, width: 100, height: 80), displays: displays)
        expect(layout.scale == 2 && layout.size.width == 200 && layout.size.height == 160)
        expect(layout.slices[0].source == CGRect(x: 50, y: 0, width: 50, height: 50))
        expect(layout.slices[0].frame == CGRect(x: 0, y: 30, width: 100, height: 100))
        expect(layout.slices[1].source == CGRect(x: 0, y: 20, width: 100, height: 160))
        expect(layout.slices[1].frame == CGRect(x: 100, y: 0, width: 100, height: 160))
        var document = CaptureDocument(id: UUID(), createdAt: Date(), size: layout.size,
            pieces: [], captureScale: Double(layout.scale))
        document.edit.imageLayers = try layout.slices.enumerated().map { index, slice in
            let raster = UUID().uuidString, width = index == 0 ? 100 : 200, height = index == 0 ? 50 : 200
            try CaptureRasterStore.write(size: CapturePixelSize(width: width, height: height),
                to: root.appendingPathComponent(raster)) { _, row in
                for x in 0..<width {
                    row[x * 4] = index == 0 ? 255 : 0; row[x * 4 + 1] = index == 1 ? 255 : 0
                    row[x * 4 + 2] = 0; row[x * 4 + 3] = 255
                }
            }
            return .init(id: UUID(), raster: raster, source: slice.source, frame: slice.frame)
        }
        _ = try document.validated()
        let output = try pixels(document, at: root)
        for y in 0..<160 {
            for x in 0..<200 {
                let expected: [UInt8] = x >= 100 ? [0, 255, 0, 255]
                    : (30..<130).contains(y) ? [255, 0, 0, 255] : [0, 0, 0, 0]
                let offset = (y * 200 + x) * 4
                expect(output[offset..<offset + 4].elementsEqual(expected), "Mixed-scale seams and gaps must stay exact")
            }
        }
        let archive = root.appendingPathComponent("displays-archive")
        try FileManager.default.createDirectory(at: archive, withIntermediateDirectories: false)
        let archived = try CaptureSourceArchive.copy(document: document, from: root, to: archive)
        expect(try pixels(archived, at: archive) == output, "Cross-display draft preserves output pixels")
        for layer in archived.imageLayers {
            let raster = try CaptureRasterStore.read(at: archive.appendingPathComponent(layer.raster))
            expect(layer.source.origin == .zero && raster.size.width == Int(layer.source.width)
                && raster.size.height == Int(layer.source.height), "Draft stores only each selected screen crop")
        }
        let single = try CaptureDisplayComposition.layout(
            region: CGRect(x: -80, y: 30, width: 50, height: 40), displays: displays)
        expect(single.scale == 1 && single.slices.count == 1 && single.size.width == 50)
        for region in [CGRect(x: -100, y: 0, width: 40, height: 20),
            CGRect(x: -1e30, y: 0, width: 1e31, height: 80)] {
            do {
                _ = try CaptureDisplayComposition.layout(region: region, displays: displays)
                expect(false, "Empty-screen and excessive selections must fail")
            } catch { }
        }
    }

    static func translation(raster: String, size: CapturePixelSize, at root: URL) throws {
        let groups = CaptureTranslation.paragraphs([
            ("left one", CGRect(x: 20, y: 20, width: 180, height: 20)),
            ("right one", CGRect(x: 260, y: 20, width: 180, height: 20)),
            ("left two", CGRect(x: 20, y: 48, width: 170, height: 20)),
            ("right two", CGRect(x: 260, y: 48, width: 160, height: 20)),
            ("new paragraph", CGRect(x: 20, y: 110, width: 200, height: 20))],
            in: CGRect(x: 0, y: 0, width: 500, height: 200))
        expect(groups.map(\.text) == ["left one\nleft two", "right one\nright two", "new paragraph"])
        var document = CaptureDocument(id: UUID(), createdAt: Date(), size: size,
            pieces: [.init(raster: raster, source: .init(x: 0, y: 0, width: size.width, height: size.height), origin: .zero)])
        document.edit.annotations = [.init(id: UUID(), tool: .cover,
            points: [.init(x: 1080, y: 20), .init(x: 1130, y: 65)])]
        let original = try pixels(document, at: root)
        let translation = CaptureTranslation(target: "zh-Hans", blocks: [
            .init(id: UUID(), source: "first line\nsecond line", text: "Hello 7391\n第二段",
                rect: .init(x: 900, y: 10, width: 240, height: 80), background: .init(red: 245, green: 245, blue: 245))])
        try CaptureTranslationRenderer.validate(translation)
        document.edit.translation = translation
        let output = try pixels(document, at: root)
        expect(output != original)
        let covered = try CaptureRenderer.color(document: document, directory: root, at: .init(x: 1100, y: 35))
        expect(covered.hex == "#000000", "Translation never overrides a privacy cover")
        for y in 0..<size.height {
            for x in 0..<size.width where x < 900 || x >= 1140 || y < 10 || y >= 90 {
                let i = (y * size.width + x) * 4
                expect(output[i..<i+4] == original[i..<i+4], "Translation is limited to its paragraph")
            }
        }
        for axis in CaptureDocument.Axis.allCases {
            try compare(output, document: document, flipped: CaptureReflection.flip(document, axis: axis),
                direction: axis, at: root)
        }
        document.edit.translation?.enabled = false
        let restored = try pixels(document, at: root)
        expect(restored == original, "Original toggle restores all underlying pixels")
        document.edit.translation?.enabled = true
        let url = root.appendingPathComponent("translation.png")
        try CaptureRenderer.png(document: document, directory: root, to: url)
        let repository = CaptureRepository(root: root.appendingPathComponent("translation-history"))
        try repository.commit(document: document, directory: root, png: url, editable: true, draft: true)
        let (opened, directory) = try repository.open(repository.entries()[0], id: UUID())
        let reopened = try pixels(opened, at: directory)
        expect(reopened == output && opened.edit.translation == translation)
        var invalid = translation
        invalid.blocks[0].text = String(repeating: "Too much text ", count: 500)
        do { try CaptureTranslationRenderer.validate(invalid); expect(false, "Overflow silently clipped") } catch { }
    }

    static func presentation(raster: String, size: CapturePixelSize, at root: URL) throws {
        var document = CaptureDocument(id: UUID(), createdAt: Date(), size: size,
            pieces: [.init(raster: raster, source: .init(x: 0, y: 0, width: size.width, height: size.height), origin: .zero)])
        document.edit.crop = CGRect(x: 13, y: 5, width: 1131, height: 90)
        document.edit.annotations = [.init(id: UUID(), tool: .cover,
            points: [.init(x: 1020, y: 25), .init(x: 1100, y: 75)])]
        let original = document
        for background in CapturePresentation.Background.allCases {
            document.edit.presentation = .init(background: background, padding: 43, radius: 13, shadow: 20, windowFrame: true)
            _ = try document.validated()
            expect(document.outputBounds == CGRect(x: -30, y: -70, width: 1217, height: 208))
            let whole = try pixels(document, at: root)
            let png = root.appendingPathComponent("styled.png")
            try CaptureRenderer.png(document: document, directory: root, to: png)
            let reader = try CapturePNGReader(url: png)
            var decoded = Data(count: whole.count)
            try decoded.withUnsafeMutableBytes { bytes in
                for y in 0..<208 {
                    try reader.read(row: y, into: .init(rebasing: bytes[(y * 1217 * 4)..<((y + 1) * 1217 * 4)]))
                }
            }
            var straight = whole
            try straight.withUnsafeMutableBytes { try CapturePixelAlpha.unpremultiply($0) }
            expect(decoded == straight, "Styling PNG bands must match a single rendering: \(background)")
            let preview = try CaptureRenderer.preview(document: document, directory: root, maximum: 1217)
            expect(preview.dataProvider!.data! as Data == whole, "Styling preview tiles must match PNG: \(background)")
            let color = try CaptureRenderer.color(document: document, directory: root, at: .init(x: 1050, y: 50))
            expect(color.hex == "#000000", "Styling preserves final privacy covers")
            if background == .transparent {
                expect(Array(whole[0..<4]) == [0, 0, 0, 0])
                let corner = ((43 * 1217) + 43) * 4
                expect(whole[corner + 3] < 255, "Rounded frame excludes the original corner")
            }
            let decodedDocument = try JSONDecoder().decode(CaptureDocument.self,
                from: JSONEncoder().encode(document)).validated()
            expect(decodedDocument == document)
            let archive = root.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: archive, withIntermediateDirectories: false)
            let saved = try CaptureSourceArchive.copy(document: document, from: root, to: archive)
            let restored = try pixels(saved, at: archive)
            expect(restored == whole)
        }
        var undo = CaptureUndoHistory(), result = original
        undo.commit(document.edit, to: &result)
        undo.undo(&result)
        expect(result.pieces == original.pieces && result.edit == original.edit)
        undo.redo(&result)
        expect(result.edit == document.edit)
        result.edit.presentation?.padding = .infinity
        do { _ = try result.validated(); expect(false) } catch { }
        result = document
        result.size = try CapturePixelSize(width: 30_000, height: 100)
        result.pieces[0].source.size.width = 30_000
        result.edit.crop = nil
        do { _ = try result.validated(); expect(false) } catch { }
    }

    static func backgroundMask(at root: URL) throws {
        let raster = UUID().uuidString, mask = UUID().uuidString
        let size = try CapturePixelSize(width: 1170, height: 190)
        let maskSize = try CapturePixelSize(width: 117, height: 19)
        for (name, dimensions, isMask) in [(raster, size, false), (mask, maskSize, true)] {
            try CaptureRasterStore.write(size: dimensions, to: root.appendingPathComponent(name)) { _, row in
                for x in 0..<dimensions.width {
                    row[x * 4] = isMask ? 255 : 220
                    row[x * 4 + 1] = isMask ? 255 : 80
                    row[x * 4 + 2] = isMask ? 255 : 40
                    row[x * 4 + 3] = isMask ? x < 39 ? 0 : x < 78 ? 128 : 255 : 255
                }
            }
        }
        let bounds = CGRect(x: 0, y: 0, width: size.width, height: size.height)
        var layer = CaptureImageLayer(id: UUID(), raster: raster, source: bounds, frame: bounds)
        layer.backgroundMask = .init(raster: mask, size: maskSize)
        var document = CaptureDocument(id: UUID(), createdAt: Date(), size: size, pieces: [])
        document.edit.imageLayers = [layer]
        let result = try pixels(document, at: root)
        expect(Array(result[0..<4]) == [0, 0, 0, 0], "Removed pixels contain no hidden source color")
        expect(result[(80 * size.width + 500) * 4 + 3] == 128)
        expect(Array(result[(80 * size.width + 1100) * 4..<(80 * size.width + 1100) * 4 + 4]) == [220, 80, 40, 255])
        let png = root.appendingPathComponent("foreground.png")
        try CaptureRenderer.png(document: document, directory: root, to: png)
        let reader = try CapturePNGReader(url: png)
        var decoded = Data(count: size.byteCount)
        try decoded.withUnsafeMutableBytes { bytes in
            for y in 0..<size.height {
                try reader.read(row: y, into: UnsafeMutableRawBufferPointer(
                    rebasing: bytes[y * size.rowBytes..<(y + 1) * size.rowBytes]))
            }
        }
        var straight = result
        try straight.withUnsafeMutableBytes { try CapturePixelAlpha.unpremultiply($0) }
        expect(straight == decoded, "Mask alpha matches across PNG bands")
        let preview = try CaptureRenderer.preview(document: document, directory: root, maximum: size.width)
        expect(preview.dataProvider!.data! as Data == result, "Mask alpha matches across viewport tiles")
        for axis in CaptureDocument.Axis.allCases {
            try compare(result, document: document, flipped: CaptureReflection.flip(document, axis: axis),
                direction: axis, at: root)
        }
        var restored = document, undo = CaptureUndoHistory(), edit = document.edit
        edit.imageLayers?[0].backgroundMask?.enabled = false
        undo.commit(edit, to: &restored)
        let original = try pixels(restored, at: root)
        expect(Array(original[0..<4]) == [220, 80, 40, 255], "Background remains available after removal")
        undo.undo(&restored)
        let undone = try pixels(restored, at: root)
        expect(undone == result)
        undo.redo(&restored)
        expect(restored.imageLayers[0].backgroundMask?.enabled == false)
        let repository = CaptureRepository(root: root.appendingPathComponent("mask-history"))
        try repository.commit(document: document, directory: root, png: png, editable: true, draft: true)
        let entry = try repository.entries()[0]
        let (reopened, directory) = try repository.open(entry, id: UUID())
        let reopenedPixels = try pixels(reopened, at: directory)
        expect(reopened.imageLayers[0].backgroundMask == layer.backgroundMask && reopenedPixels == result)
        let archived = repository.history.appendingPathComponent(entry.id.uuidString).appendingPathComponent("source")
        for missing in [mask, raster] {
            let saved = archived.appendingPathComponent(missing)
            let backup = archived.appendingPathComponent("backup-\(missing)")
            try FileManager.default.moveItem(at: saved, to: backup)
            let (fallback, source) = try repository.open(entry, id: UUID())
            let fallbackPixels = try pixels(fallback, at: source)
            expect(fallback.edit.isEmpty && fallbackPixels == result,
                "Missing image or mask must fall back to the complete flattened result")
            try FileManager.default.moveItem(at: backup, to: saved)
        }
        document.edit.annotations = [.init(id: UUID(), tool: .cover,
            points: [.init(x: 10, y: 10), .init(x: 50, y: 50)])]
        let covered = try pixels(document, at: root)
        expect(Array(covered[(20 * size.width + 20) * 4..<(20 * size.width + 20) * 4 + 4]) == [0, 0, 0, 255])
    }

    static func composition(at root: URL) throws {
        let base = UUID().uuidString, sticker = UUID().uuidString
        let baseSize = try CapturePixelSize(width: 80, height: 120)
        let stickerSize = try CapturePixelSize(width: 50, height: 60)
        for (raster, size, color) in [(base, baseSize, UInt8(240)), (sticker, stickerSize, UInt8(30))] {
            try CaptureRasterStore.write(size: size, to: root.appendingPathComponent(raster)) { _, row in
                for x in 0..<size.width {
                    row[x * 4] = color; row[x * 4 + 1] = 90; row[x * 4 + 2] = 140; row[x * 4 + 3] = 255
                }
            }
        }
        var original = CaptureDocument(id: UUID(), createdAt: Date(), size: baseSize,
            pieces: [.init(raster: base, source: .init(x: 0, y: 0, width: 80, height: 120), origin: .zero)], axis: .vertical)
        original.edit.crop = CGRect(x: 10, y: 20, width: 60, height: 80)
        original.edit.annotations = [.init(id: UUID(), tool: .cover,
            points: [.init(x: 30, y: 40), .init(x: 50, y: 60)])]
        let expected = try pixels(original, at: root)
        let image = CaptureImageLayer(id: UUID(), raster: sticker,
            source: .init(x: 0, y: 0, width: 50, height: 60), frame: .init(x: 0, y: 0, width: 50, height: 60))
        for axis in CaptureDocument.Axis.allCases {
            let combined = try CaptureCompositionService.append(image, to: original, directory: root, axis: axis)
            expect(combined.pieces.isEmpty && combined.axis == nil && combined.imageLayers.count == 2)
            expect(combined.size.width == (axis == .horizontal ? 110 : 60))
            expect(combined.size.height == (axis == .vertical ? 140 : 80))
            let first = try CaptureRenderer.image(document: combined, directory: root,
                rect: CGRect(x: 0, y: 0, width: 60, height: 80)).dataProvider!.data! as Data
            expect(first == expected, "Combining preserves the crop and final covered pixels")
            var undo = CaptureUndoHistory(), edited = original
            undo.commit(combined, to: &edited)
            undo.undo(&edited)
            expect(edited.pieces == original.pieces && edited.edit == original.edit && edited.axis == .vertical,
                "Undo restores the scrolling document and its editable covers")
            undo.redo(&edited)
            expect(edited.pieces.isEmpty && edited.axis == nil)
            var moved = combined
            moved.edit.imageLayers?[1].frame.origin = CGPoint(x: -13, y: -27)
            let fitted = try CaptureComposition.fit(moved)
            expect(fitted.imageLayers[1].frame.origin == .zero)
            expect(fitted.imageLayers[0].frame.origin == CGPoint(x: 13, y: 27))
            let archive = root.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: archive, withIntermediateDirectories: false)
            let archived = try CaptureSourceArchive.copy(document: fitted, from: root, to: archive)
            let output = try pixels(fitted, at: root), reopened = try pixels(archived, at: archive)
            expect(output == reopened, "Composition archive retains each independent image")
        }
    }

    static func imageLayers(at root: URL) throws {
        let base = UUID().uuidString, sticker = UUID().uuidString
        let baseSize = try CapturePixelSize(width: 1500, height: 500)
        let stickerSize = try CapturePixelSize(width: 620, height: 190)
        try CaptureRasterStore.write(size: baseSize, to: root.appendingPathComponent(base)) { _, row in
            for x in 0..<baseSize.width {
                row[x * 4] = 255; row[x * 4 + 1] = 255; row[x * 4 + 2] = 255; row[x * 4 + 3] = 255
            }
        }
        try CaptureRasterStore.write(size: stickerSize, to: root.appendingPathComponent(sticker)) { y, row in
            for x in 0..<stickerSize.width {
                row[x * 4] = UInt8(x % 255); row[x * 4 + 1] = UInt8(y % 255)
                row[x * 4 + 2] = 91; row[x * 4 + 3] = x < 30 ? 0 : x < 60 ? 128 : 255
            }
        }
        var document = CaptureDocument(id: UUID(), createdAt: Date(), size: baseSize,
            pieces: [.init(raster: base, source: CGRect(x: 0, y: 0, width: 1500, height: 500), origin: .zero)])
        let layer = CaptureImageLayer(id: UUID(), raster: sticker,
            source: CGRect(x: 0, y: 0, width: 620, height: 190),
            frame: CGRect(x: 700, y: 173, width: 620, height: 190))
        document.edit.imageLayers = [layer]
        _ = try document.validated()
        let rendered = try pixels(document, at: root)
        func color(_ x: Int, _ y: Int, _ data: Data) -> [UInt8] {
            Array(data[((y * 1500 + x) * 4)..<((y * 1500 + x) * 4 + 4)])
        }
        expect(color(710, 210, rendered) == [255, 255, 255, 255], "Transparent sticker preserves the base")
        expect(color(800, 210, rendered) == [100, 37, 91, 255], "Image coordinates must match the source")
        expect(color(1024, 250, rendered) == [69, 77, 91, 255], "Image must cross viewport tile boundaries")
        for rotation in [0.0, 27.0] {
            var transformed = document
            transformed.edit.imageLayers?[0].rotation = rotation
            transformed.edit.imageLayers?[0].opacity = 0.65
            if rotation != 0 { transformed.edit.imageLayers?[0].frame.size = CGSize(width: 471, height: 144) }
            let image = try pixels(transformed, at: root)
            let png = root.appendingPathComponent("layers.png")
            try CaptureRenderer.png(document: transformed, directory: root, to: png)
            let reader = try CapturePNGReader(url: png)
            var decoded = Data(count: image.count)
            try decoded.withUnsafeMutableBytes { bytes in
                for y in 0..<500 {
                    try reader.read(row: y, into: .init(rebasing: bytes[(y * 6000)..<((y + 1) * 6000)]))
                }
            }
            let current = transformed.imageLayers[0], radians = -rotation * .pi / 180
            for index in image.indices where image[index] != decoded[index] {
                let x = Double(index / 4 % 1500) + 0.5 - current.frame.midX
                let y = Double(index / 6000) + 0.5 - current.frame.midY
                let localX = x * cos(radians) - y * sin(radians)
                let localY = x * sin(radians) + y * cos(radians)
                let edge = min(abs(abs(localX) - current.frame.width / 2), abs(abs(localY) - current.frame.height / 2))
                expect(rotation != 0 && edge <= 2 && abs(Int(image[index]) - Int(decoded[index])) <= 2,
                    "Only the rotated outer antialias edge may differ; at \(index / 4 % 1500),\(index / 6000), edge \(edge)")
            }
            let archive = root.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: archive, withIntermediateDirectories: false)
            let archived = try CaptureSourceArchive.copy(document: transformed, from: root, to: archive)
            let restored = try pixels(archived, at: archive)
            expect(restored == image, "Editable archive retains source layers")
        }
        var protected = document
        protected.edit.annotations = [.init(id: UUID(), tool: .cover,
            points: [CGPoint(x: 950, y: 200), CGPoint(x: 1100, y: 300)])]
        let protectedPixels = try pixels(protected, at: root)
        expect(color(1024, 250, protectedPixels) == [0, 0, 0, 255], "Covers remain above imported images")
        for axis in CaptureDocument.Axis.allCases {
            let flipped = try CaptureReflection.flip(protected, axis: axis)
            try compare(protectedPixels, document: protected, flipped: flipped, direction: axis, at: root)
        }
        let decoded = try JSONDecoder().decode(CaptureDocument.self, from: JSONEncoder().encode(document)).validated()
        expect(decoded == document)
        var undo = CaptureUndoHistory(), changed = document.edit
        changed.imageLayers?.removeAll()
        undo.commit(changed, to: &document)
        undo.undo(&document)
        expect(document.imageLayers == [layer])
        var invalid = document
        invalid.edit.imageLayers = Array(repeating: layer, count: 33)
        expect((try? invalid.validated()) == nil)
    }

    static func pixels(_ document: CaptureDocument, at directory: URL) throws -> Data {
        let image = try CaptureRenderer.image(document: document, directory: directory, rect: document.outputBounds)
        return image.dataProvider!.data! as Data
    }

    static func compare(
        _ original: Data, document: CaptureDocument, flipped: CaptureDocument,
        direction: CaptureDocument.Axis, at directory: URL
    ) throws {
        let output = try pixels(flipped, at: directory)
        let width = Int(document.outputBounds.width), height = Int(document.outputBounds.height)
        for y in 0..<height {
            for x in 0..<width {
                let oldX = direction == .horizontal ? width - 1 - x : x
                let oldY = direction == .vertical ? height - 1 - y : y
                let offset = (y * width + x) * 4, oldOffset = (oldY * width + oldX) * 4
                expect(output[offset..<(offset + 4)] == original[oldOffset..<(oldOffset + 4)],
                    "Flip must mirror the final covered image: \(direction) at \(x),\(y)")
            }
        }
        let url = directory.appendingPathComponent("reflected.png")
        try CaptureRenderer.png(document: flipped, directory: directory, to: url)
        let reader = try CapturePNGReader(url: url)
        var data = Data(count: output.count)
        try data.withUnsafeMutableBytes { bytes in
            for y in 0..<height {
                try reader.read(row: y, into: .init(rebasing: bytes[(y * width * 4)..<((y + 1) * width * 4)]))
            }
        }
        var straight = output
        try straight.withUnsafeMutableBytes { try CapturePixelAlpha.unpremultiply($0) }
        expect(data == straight, "Streaming PNG must match reflection across tile boundaries")
        let preview = try CaptureRenderer.preview(document: flipped, directory: directory, maximum: width)
        expect(preview.dataProvider!.data! as Data == output, "Preview must mirror exactly like PNG")
    }

    static func reframing(raster: String) throws {
        let document = CaptureDocument(id: UUID(), createdAt: Date(), size: try CapturePixelSize(width: 100, height: 80),
            pieces: [.init(raster: raster, source: .init(x: 40, y: 10, width: 100, height: 80), origin: .zero)])
        let flipped = try CaptureReflection.flip(document, axis: .horizontal)
        expect(flipped.needsPreservation && !document.needsPreservation)
        let resized = try CaptureSelectionGeometry.reframe(flipped, raster: raster,
            pixels: .init(x: 20, y: 10, width: 120, height: 80),
            oldFrame: .init(x: 40, y: 10, width: 100, height: 80),
            newFrame: .init(x: 20, y: 10, width: 120, height: 80), oldScale: 1, scale: 1)
        expect(resized.pieces[0].reflection?.horizontal == true)
    }

    static func magnifier(at directory: URL) throws {
        let size = try CapturePixelSize(width: 1200, height: 220), raster = UUID().uuidString
        try CaptureRasterStore.write(size: size, to: directory.appendingPathComponent(raster)) { _, row in
            row.initializeMemory(as: UInt8.self, repeating: 255)
        }
        var document = CaptureDocument(id: UUID(), createdAt: Date(), size: size,
            pieces: [.init(raster: raster, source: .init(x: 0, y: 0, width: 1200, height: 220), origin: .zero)])
        document.edit.annotations = [
            .init(id: UUID(), tool: .rectangle, points: [.init(x: 1000, y: 80), .init(x: 1060, y: 140)], filled: true),
            .init(id: UUID(), tool: .cover, points: [.init(x: 1025, y: 105), .init(x: 1035, y: 115)]),
            .init(id: UUID(), tool: .magnifier, points: [.init(x: 930, y: 10), .init(x: 1130, y: 210)], magnification: 2)]
        let covered = try CaptureRenderer.color(document: document, directory: directory, at: .init(x: 1038, y: 110))
        expect(covered.hex == "#000000", "The lens must magnify the final cover instead of reading original pixels")
        let magnified = try CaptureRenderer.color(document: document, directory: directory, at: .init(x: 990, y: 110))
        expect(magnified.red > 200 && magnified.green < 80, "Magnify vector annotations with the source")
        let tile = try CaptureRenderer.image(document: document, directory: directory,
            rect: document.bounds, includingVectorAnnotations: false)
        let tileBytes = tile.dataProvider!.data! as Data
        expect(tileBytes[(110 * size.width + 990) * 4 + 1] < 80, "Canvas tiles need the same annotated lens input")
        let image = try pixels(document, at: directory)
        let preview = try CaptureRenderer.preview(document: document, directory: directory, maximum: size.width)
        let previewBytes = preview.dataProvider!.data! as Data
        sameLensPixels(image, previewBytes, width: size.width)
        let url = directory.appendingPathComponent("magnifier.png")
        try CaptureRenderer.png(document: document, directory: directory, to: url)
        let reader = try CapturePNGReader(url: url)
        var exported = Data(count: image.count)
        try exported.withUnsafeMutableBytes { bytes in
            for y in 0..<size.height {
                try reader.read(row: y, into: .init(rebasing: bytes[(y * size.rowBytes)..<((y + 1) * size.rowBytes)]))
            }
        }
        sameLensPixels(image, exported, width: size.width)
        document.edit.annotations.append(.init(id: UUID(), tool: .magnifier,
            points: [.init(x: 1050, y: 0), .init(x: 1190, y: 150)], magnification: 8))
        _ = try pixels(document, at: directory)
        document.edit.annotations[2].magnification = .infinity
        expect(!document.edit.annotations[2].isValid)
    }

    static func sameLensPixels(_ first: Data, _ second: Data, width: Int) {
        expect(first.count == second.count)
        for offset in first.indices where first[offset] != second[offset] {
            let x = Double(offset / 4 % width) + 0.5, y = Double(offset / 4 / width) + 0.5
            let edge = abs(hypot(x - 1030, y - 110) - 100)
            expect(edge <= 3 && abs(Int(first[offset]) - Int(second[offset])) <= 1,
                "Only a one-level CoreGraphics antialias difference at the lens edge is allowed")
        }
    }
}
