import AppKit
import UniformTypeIdentifiers

extension CaptureCoordinator {
    func addImage(clipboard: Bool = false, axis: CaptureDocument.Axis? = nil) {
        run { [weak self] in
            guard let self, let editor = self.editor, !editor.busy else { return }
            guard editor.document.imageLayers.count < 32 else {
                editor.notice = String(localized: "Remove an image first (maximum 32).")
                return
            }
            editor.finishEditing()
            editor.busy = true
            self.overlay.suspend()
            defer { editor.busy = false; self.savePanel = nil; self.overlay.resume() }
            let revision = editor.document.revision, source = editor.source
            let raster = UUID().uuidString, destination = source.directory.appendingPathComponent(raster)
            var added = false
            var generated: Set<String> = []
            defer {
                if !added {
                    try? FileManager.default.removeItem(at: destination)
                    for raster in generated {
                        try? FileManager.default.removeItem(
                            at: source.directory.appendingPathComponent(raster))
                    }
                }
            }
            let size: CapturePixelSize
            if clipboard {
                size = try await self.loadClipboardImage(at: destination)
            } else {
                let panel = NSOpenPanel()
                panel.allowedContentTypes = [.image]
                panel.canChooseDirectories = false
                panel.allowsMultipleSelection = false
                panel.prompt = "Add Image"
                self.savePanel = panel
                guard await self.editorWindow.present(panel) == .OK, let url = panel.url else { return }
                size = try await CaptureWork.run { try CaptureImageSource.load(url, at: destination) }
            }
            try Task.checkCancellation()
            guard self.editor === editor, revision == editor.document.revision else { return }
            var layer = CaptureImageLayer.placed(
                id: UUID(), raster: raster, size: size, in: editor.document.outputBounds)
            if let axis {
                layer.frame = CGRect(x: 0, y: 0, width: size.width, height: size.height)
                let snapshot = editor.document, image = layer
                let replacement = try await CaptureWork.run {
                    try CaptureCompositionService.append(
                        image, to: snapshot, directory: source.directory, axis: axis)
                }
                generated = Set(replacement.rasterRegions.map(\.raster)).subtracting(
                    snapshot.rasterRegions.map(\.raster))
                try Task.checkCancellation()
                guard self.editor === editor, revision == editor.document.revision else { return }
                editor.reframe(replacement)
                editor.fit()
            } else {
                var replacement = editor.document
                replacement.edit.imageLayers = replacement.imageLayers + [layer]
                _ = try replacement.validated()
                editor.commit(replacement.edit)
            }
            editor.selectTool(.select)
            editor.selected = layer.id
            editor.notice = nil
            added = true
            if axis != nil, self.workspace != nil { editor.busy = false; self.expandCapture() }
        }
    }
}
