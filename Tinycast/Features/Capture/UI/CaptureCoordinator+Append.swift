import AppKit

extension CaptureCoordinator {
    func appendCapture(axis: CaptureDocument.Axis) {
        run { [weak self] in
            guard let self, let editor = self.editor, !editor.busy, self.pendingCapture == nil,
                let screen = NSScreen.underCursor
            else { return }
            guard CGPreflightScreenCaptureAccess() else { throw CaptureScreenService.Failure.unavailable }
            editor.finishEditing()
            self.pendingCapture = CaptureAppendState(editor: editor, axis: axis)
            self.editorWindow.close()
            self.editor = nil
            var started = false
            defer { if !started { self.restoreAppendCapture() } }
            self.restoreFocus()
            try await Task.sleep(for: .milliseconds(200))
            try await self.prepare(screen: screen, request: .init())
            started = true
        }
    }

    func finishAppendCapture() {
        run { [weak self] in
            guard let self, let pending = self.pendingCapture, let capture = self.editor,
                !capture.busy, !pending.editor.busy, self.workspace?.selectingTarget == false
            else { return }
            capture.busy = true
            defer { capture.busy = false }
            let original = pending.editor.document, snapshot = capture.document
            let source = pending.editor.source, captured = capture.source
            let raster = UUID().uuidString, destination = source.directory.appendingPathComponent(raster)
            let png = source.directory.appendingPathComponent("append-\(UUID()).png")
            var completed = false
            var generated: Set<String> = []
            defer {
                try? FileManager.default.removeItem(at: png)
                if !completed {
                    try? FileManager.default.removeItem(at: destination)
                    for raster in generated {
                        try? FileManager.default.removeItem(at: source.directory.appendingPathComponent(raster))
                    }
                }
            }
            let axis = pending.axis
            let replacement = try await CaptureWork.run {
                try CaptureRenderer.png(document: snapshot, directory: captured.directory, to: png)
                let size = try CaptureImageSource.load(png, at: destination)
                let bounds = CGRect(x: 0, y: 0, width: size.width, height: size.height)
                let image = CaptureImageLayer(id: UUID(), raster: raster, source: bounds, frame: bounds)
                return try CaptureCompositionService.append(image, to: original, directory: source.directory, axis: axis)
            }
            generated = Set(replacement.rasterRegions.map(\.raster)).subtracting(original.rasterRegions.map(\.raster))
            try Task.checkCancellation()
            guard self.pendingCapture === pending, self.editor === capture,
                pending.editor.document.revision == original.revision
            else { return }
            pending.editor.reframe(replacement)
            pending.editor.fit()
            completed = true
            self.restoreAppendCapture()
        }
    }

    func restoreAppendCapture() {
        guard let pendingCapture else { return }
        clearSelection()
        editor = pendingCapture.editor
        self.pendingCapture = nil
        editorWindow.show(self)
    }
}
