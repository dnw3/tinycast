import AppKit

@main
struct CaptureInlineCompositionTests {
    @MainActor static func main() throws {
        NSApplication.shared.setActivationPolicy(.prohibited)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let source = try CaptureSource(directory: directory)
        let size = try CapturePixelSize(width: 48, height: 32)
        let raster = UUID().uuidString
        try CaptureRasterStore.write(size: size, to: directory.appendingPathComponent(raster)) { y, row in
            for x in 0..<size.width {
                row[x * 4] = UInt8(x * 4)
                row[x * 4 + 1] = UInt8(y * 7)
                row[x * 4 + 2] = 80
                row[x * 4 + 3] = 255
            }
        }
        let document = CaptureDocument(id: UUID(), createdAt: Date(),
            size: try CapturePixelSize(width: 16, height: 16),
            pieces: [.init(raster: raster, source: CGRect(x: 16, y: 8, width: 16, height: 16), origin: .zero)])
        let state = CaptureEditorState(document: document, source: source)
        let surface = NSView(frame: CGRect(x: 0, y: 0, width: 48, height: 32))
        let root = CaptureSelectionRootView(frame: surface.frame, selection: surface, image: nil, scale: 1)
        let window = NSWindow(contentRect: root.frame, styleMask: [], backing: .buffered, defer: false)
        window.contentView = root
        let canvas = CaptureCanvas(state: state, fixedScale: 1).inlineView(reusing: nil)
        canvas.wantsLayer = true
        surface.addSubview(canvas)
        canvas.frame = CGRect(x: 16, y: 8, width: 16, height: 16)
        for _ in 0..<20 {
            RunLoop.main.run(until: Date().addingTimeInterval(0.025))
            root.layoutSubtreeIfNeeded()
            root.displayIfNeeded()
        }
        precondition(state.notice == nil, state.notice ?? "Inline source must load successfully")
        let context = CGContext(data: nil, width: 48, height: 32, bitsPerComponent: 8, bytesPerRow: 48 * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        root.layer!.render(in: context)
        let bytes = context.data!.assumingMemoryBound(to: UInt8.self)
        let middle = (16 * 48 + 24) * 4
        precondition(bytes[middle + 3] == 255 && bytes[middle] == 96 && bytes[middle + 2] == 80,
            "Inline canvas pixels must remain visible over the frozen desktop layer")
        func mouse(_ type: NSEvent.EventType, _ point: CGPoint) {
            let event = NSEvent.mouseEvent(with: type, location: canvas.convert(point, to: nil), modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                context: nil, eventNumber: 1, clickCount: 1, pressure: 1)!
            switch type {
            case .leftMouseDown: canvas.mouseDown(with: event)
            case .leftMouseDragged: canvas.mouseDragged(with: event)
            default: canvas.mouseUp(with: event)
            }
        }
        state.selectTool(.number)
        state.numberStyle = .roman
        state.numberLeader = true
        state.nextNumber = 3999
        mouse(.leftMouseDown, CGPoint(x: 2, y: 2))
        mouse(.leftMouseDragged, CGPoint(x: 12, y: 12))
        mouse(.leftMouseUp, CGPoint(x: 12, y: 12))
        let createdNumber = state.document.edit.annotations[0]
        precondition(createdNumber.numberLabel == "MMMCMXCIX" && createdNumber.numberLeader == true)
        precondition(state.nextNumber == 4000)
        state.selectTool(.select)
        mouse(.leftMouseDown, CGPoint(x: 12, y: 12))
        mouse(.leftMouseDragged, CGPoint(x: 5, y: 10))
        mouse(.leftMouseUp, CGPoint(x: 5, y: 10))
        precondition(state.document.edit.annotations[0].points.first == createdNumber.points.first)
        precondition(state.document.edit.annotations[0].points.last == CGPoint(x: 5, y: 10))
        state.undoEdit()
        precondition(state.nextNumber == 4000 && state.document.edit.annotations[0].points == createdNumber.points)
        state.undoEdit()
        precondition(state.nextNumber == 3999)
        state.redoEdit()
        precondition(state.nextNumber == 4000)
        state.selectTool(.number)
        mouse(.leftMouseDown, CGPoint(x: 4, y: 4))
        mouse(.leftMouseUp, CGPoint(x: 4, y: 4))
        precondition(state.document.edit.annotations.count == 1 && state.notice != nil)
        state.selectTool(.pen)
        state.smoothPen = true
        mouse(.leftMouseDown, CGPoint(x: 2, y: 2))
        mouse(.leftMouseDragged, CGPoint(x: 5, y: 10))
        mouse(.leftMouseDragged, CGPoint(x: 10, y: 4))
        mouse(.leftMouseDragged, CGPoint(x: 14, y: 12))
        mouse(.leftMouseUp, CGPoint(x: 14, y: 12))
        let stroke = state.document.edit.annotations.last!
        precondition(stroke.tool == .pen && stroke.smoothed == true && stroke.points.count >= 4)
        precondition(stroke.points.first == CGPoint(x: 2, y: 2) && stroke.points.last == CGPoint(x: 14, y: 12))
        state.undoEdit()
        state.undoEdit()
        precondition(state.document.edit.annotations.isEmpty)
        state.selectTool(.highlighter)
        state.textHighlight = .init(document: state.document,
            lines: [CGRect(x: 1, y: 2, width: 14, height: 5), CGRect(x: 1, y: 9, width: 14, height: 5)])
        state.snapsToText = true
        mouse(.leftMouseDown, CGPoint(x: 3, y: 4))
        mouse(.leftMouseDragged, CGPoint(x: 11, y: 11))
        mouse(.leftMouseUp, CGPoint(x: 11, y: 11))
        let snapped = state.document.edit.annotations
        precondition(snapped.count == 2 && snapped.allSatisfy { $0.tool == .highlighter })
        precondition(snapped[0].points == [CGPoint(x: 3, y: 4.5), CGPoint(x: 11, y: 4.5)])
        precondition(state.textHighlight?.revision == state.document.revision && state.snapsToText)
        state.undoEdit()
        precondition(state.document.edit.annotations.isEmpty && state.snapsToText)
        state.redoEdit()
        precondition(state.document.edit.annotations == snapped && state.snapsToText)
        state.selectTool(.select)
        let selectedRevision = state.document.revision
        mouse(.leftMouseDown, CGPoint(x: 3, y: 2))
        mouse(.leftMouseUp, CGPoint(x: 3, y: 2))
        precondition(state.selected == snapped[0].id)
        precondition(state.document.revision == selectedRevision && state.document.edit.annotations == snapped,
            "Clicking an earlier annotation must not reorder it or create an undo entry")
        state.undoEdit()
        precondition(state.document.edit.annotations.isEmpty)
        state.adjustImage(.init(brightness: 0.1))
        precondition(state.textHighlight == nil && !state.snapsToText)
        state.undoEdit()
        precondition(state.textHighlight == nil, "Undo must not resurrect a discarded recognition snapshot")
        window.contentView = nil
        let number = CaptureAnnotation(id: UUID(), tool: .number,
            points: [.zero, CGPoint(x: 12, y: 12)], numberFormat: .init(value: 10))
        state.nextNumber = 10
        var edit = state.document.edit
        edit.annotations = [number]
        state.commit(edit)
        state.nextNumber = 11
        state.undoEdit()
        precondition(state.nextNumber == 10 && state.document.edit.annotations.isEmpty)
        state.redoEdit()
        precondition(state.nextNumber == 11 && state.document.edit.annotations == [number])
        state.selected = number.id
        state.numberStyle = .roman
        state.numberLeader = true
        state.updateSelectedStyle()
        precondition(state.document.edit.annotations[0].numberLabel == "X")
        precondition(state.document.edit.annotations[0].numberLeader == true)
        state.undoEdit()
        precondition(state.nextNumber == 11 && state.document.edit.annotations[0].numberLabel == "10")
        let reopened = CaptureEditorState(document: state.document, source: source)
        precondition(reopened.nextNumber == 11)
        let beforeStyling = state.document
        state.finishEditing()
        state.setPresentation(CapturePresentationPreset.BuiltIn.window.presentation)
        precondition(state.document.edit.presentation?.windowFrame == true)
        state.undoEdit()
        precondition(state.document.edit == beforeStyling.edit)
        state.redoEdit()
        precondition(state.document.edit.presentation?.windowFrame == true)
        print("Shipped inline canvas renders cropped source pixels inside a layer-backed selection root")
    }
}
