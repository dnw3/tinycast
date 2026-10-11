import Foundation
import ImageIO

@main
struct CapturePresentationPresetTests {
    @MainActor static func main() throws {
        let suite = "capture-preset-test-\(UUID())", defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = CaptureSettingsStore(defaults: defaults)
        precondition(store.presentationPresets.isEmpty)
        let paper = CapturePresentationPreset.BuiltIn.paper.presentation
        try store.savePresentationPreset(name: "  My Paper  ", presentation: paper)
        let saved = store.presentationPresets[0]
        precondition(saved.name == "My Paper" && saved.presentation == paper)
        let reopened = CaptureSettingsStore(defaults: defaults)
        precondition(reopened.presentationPresets == [saved])
        try store.savePresentationPreset(name: saved.name, presentation: .init(), replacing: saved.id)
        precondition(store.presentationPresets[0].id == saved.id && store.presentationPresets[0].presentation == .init())
        let binding = store.presentationPresetsBinding, snapshot = binding.read()
        precondition(binding.key == .capturePresentationPresets)
        precondition(binding.write([saved].settingsJSON).isEmpty && store.presentationPresets == [saved])
        for name in ["", "\n", "bad\tname", "bad\u{2028}name", String(repeating: "界", count: 41), "MY PAPER"] {
            do {
                try store.savePresentationPreset(name: name, presentation: paper)
                preconditionFailure("Invalid or duplicate names must not replace saved styles")
            } catch is CapturePresentationPreset.Failure {}
        }
        precondition(store.presentationPresets == [saved])
        for style in [CapturePresentation(padding: .nan), .init(radius: 81), .init(shadow: -1)] {
            do {
                try store.savePresentationPreset(name: "Invalid", presentation: style)
                preconditionFailure("Invalid styling must be rejected")
            } catch CapturePresentationPreset.Failure.style {}
        }
        for bad in [SettingsFileJSON.null, .array([.string("bad")]), .array([saved.settingsJSON, saved.settingsJSON])] {
            precondition(!binding.write(bad).isEmpty && store.presentationPresets == [saved])
        }
        var invalidPreset = saved
        invalidPreset.presentation.padding = .infinity
        precondition(!binding.write([invalidPreset].settingsJSON).isEmpty && store.presentationPresets == [saved])
        precondition(!store.replacePresentationPresets([saved, saved]))
        for index in 1..<20 { try store.savePresentationPreset(name: "Preset \(index)", presentation: paper) }
        do {
            try store.savePresentationPreset(name: "Too Many", presentation: paper)
            preconditionFailure("The preset count must be bounded")
        } catch CapturePresentationPreset.Failure.limit {}
        precondition(store.presentationPresets.count == 20)
        precondition(binding.write(snapshot).isEmpty && store.presentationPresets.count == 1)
        store.removePresentationPreset(saved.id)
        precondition(store.presentationPresets.isEmpty && CaptureSettingsStore(defaults: defaults).presentationPresets.isEmpty)
        defaults.set(Data(repeating: 0, count: 32_769), forKey: AppSettingsKey.capturePresentationPresets.rawValue)
        precondition(CaptureSettingsStore(defaults: defaults).presentationPresets.isEmpty)
        try renderedPresets()
        print("Preset validation, persistence, settings binding, bounded lists, rendering and exports passed")
    }

    static func renderedPresets() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let raster = UUID().uuidString, size = try CapturePixelSize(width: 80, height: 64)
        try CaptureRasterStore.write(size: size, to: directory.appendingPathComponent(raster)) { _, row in
            row.initializeMemory(as: UInt8.self, repeating: 255)
        }
        let tile = directory.appendingPathComponent(raster).appendingPathComponent("0-0.rgba")
        let original = try Data(contentsOf: tile)
        var document = CaptureDocument(id: UUID(), createdAt: Date(), size: size,
            pieces: [.init(raster: raster, source: CGRect(x: 0, y: 0, width: 80, height: 64), origin: .zero)])
        document.edit.annotations = [.init(id: UUID(), tool: .cover,
            points: [CGPoint(x: 20, y: 20), CGPoint(x: 50, y: 45)])]
        for malformed in [CapturePresentation(padding: -1), .init(radius: .infinity)] {
            var invalid = document
            invalid.edit.presentation = malformed
            do {
                _ = try CaptureExportOptions().validatedDimensions(for: invalid)
                preconditionFailure("Invalid styling must not produce export dimensions")
            } catch CaptureRasterError.invalidSize {}
        }
        var invalidCrop = document
        invalidCrop.edit.crop = CGRect(x: -1, y: 0, width: 80, height: 64)
        do {
            _ = try CaptureExportOptions().validatedDimensions(for: invalidCrop)
            preconditionFailure("Styling must not permit a crop outside source content")
        } catch CaptureRasterError.invalidSize {}
        var images: Set<Data> = []
        for preset in CapturePresentationPreset.BuiltIn.allCases {
            let style = preset.presentation
            precondition(style.isValid)
            var undo = CaptureUndoHistory(), edit = document.edit
            edit.presentation = style
            undo.commit(edit, to: &document)
            let bounds = document.outputBounds
            let png = directory.appendingPathComponent("\(preset.rawValue).png")
            try CaptureRenderer.png(document: document, directory: directory, to: png)
            let image = CGImageSourceCreateImageAtIndex(CGImageSourceCreateWithURL(png as CFURL, nil)!, 0, nil)!
            let decoded = rgba(image), preview = rgba(try CaptureRenderer.preview(
                document: document, directory: directory, maximum: 8192))
            precondition(image.width == Int(bounds.width) && image.height == Int(bounds.height))
            precondition(zip(decoded, preview).allSatisfy { abs(Int($0) - Int($1)) <= 2 })
            images.insert(try Data(contentsOf: png))
            let center = (Int(30 - bounds.minY) * image.width + Int(35 - bounds.minX)) * 4
            precondition(decoded[center] == 0 && decoded[center + 3] == 255)
            let roundTrip = try JSONDecoder().decode(CaptureDocument.self, from: JSONEncoder().encode(document))
            precondition(roundTrip == document)
            for format in CaptureRenderer.exportFormats where format != .png {
                let url = directory.appendingPathComponent("\(preset.rawValue).\(format.rawValue)")
                try CaptureRenderer.export(document: document, directory: directory, to: url,
                    options: .init(format: format))
                let source = CGImageSourceCreateWithURL(url as CFURL, nil)!
                let output = CGImageSourceCreateImageAtIndex(source, 0, nil)!
                precondition(output.width == image.width && output.height == image.height)
                let bytes = rgba(output)
                precondition(Int(bytes[center]) + Int(bytes[center + 1]) + Int(bytes[center + 2]) < 90)
            }
            undo.undo(&document)
            precondition(document.edit.presentation == nil)
            undo.redo(&document)
            precondition(document.edit.presentation == style)
            document.edit.presentation = nil
        }
        let retained = try Data(contentsOf: tile)
        precondition(images.count == 4 && retained == original)
    }

    static func rgba(_ image: CGImage) -> Data {
        let context = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8,
            bytesPerRow: image.width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return Data(bytes: context.data!, count: image.width * image.height * 4)
    }
}
