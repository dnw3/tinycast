import Foundation

extension CaptureCoordinator {
    func removeBackground() {
        if let editor, !editor.busy, var image = editor.backgroundImage, image.backgroundMask != nil {
            editor.finishEditing()
            image.backgroundMask?.enabled.toggle()
            editor.updateImage(image)
            editor.selected = image.id
            return
        }
        run { [weak self] in
            guard let self, let editor = self.editor, !editor.busy else { return }
            editor.finishEditing()
            editor.busy = true
            defer { editor.busy = false }
            let snapshot = editor.document, selected = editor.backgroundImage, source = editor.source
            let input = source.directory.appendingPathComponent("foreground-\(UUID()).png")
            let raster = UUID().uuidString, destination = source.directory.appendingPathComponent(raster)
            var generated: URL?, completed = false
            defer {
                try? FileManager.default.removeItem(at: input)
                try? FileManager.default.removeItem(at: input.appendingPathExtension("mask.png"))
                if !completed {
                    try? FileManager.default.removeItem(at: destination)
                    if let generated { try? FileManager.default.removeItem(at: generated) }
                }
            }
            var replacement = snapshot
            if selected == nil {
                replacement = try await CaptureWork.run {
                    try CaptureCompositionService.flatten(snapshot, directory: source.directory)
                }
                generated = source.directory.appendingPathComponent(replacement.imageLayers[0].raster)
            }
            var layer = selected ?? replacement.imageLayers[0]
            let image = layer
            try await CaptureWork.run {
                try CaptureForegroundService.input(for: image, directory: source.directory, to: input)
            }
            let mask = try await TextRecognitionWorker.foreground(at: input)
            let size = try await CaptureWork.run { try CaptureImageSource.load(mask, at: destination) }
            layer.backgroundMask = .init(raster: raster, size: size)
            guard let index = replacement.imageLayers.firstIndex(where: { $0.id == layer.id }) else { return }
            replacement.edit.imageLayers?[index] = layer
            _ = try replacement.validated()
            try Task.checkCancellation()
            guard self.editor === editor, editor.document.revision == snapshot.revision else { return }
            editor.reframe(replacement)
            editor.selectTool(.select)
            editor.selected = layer.id
            editor.notice = nil
            completed = true
        }
    }
}
