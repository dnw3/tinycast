import AppKit

extension CaptureCoordinator {
    func prepareSource(workspace: CaptureWorkspaceState, images: [(CGImage, String)]) {
        let source = workspace.source
        sourcePreparation = Task { [weak self] in
            do {
                let started = ContinuousClock.now
                try await CaptureWork.run {
                    for (image, raster) in images {
                        try Task.checkCancellation()
                        _ = try CaptureImageSource.store(image, at: source.directory.appendingPathComponent(raster))
                    }
                }
                try Task.checkCancellation()
                guard let self, self.workspace === workspace else { return }
                CapturePerformance.completed("selection-source-ready", since: started)
                let pending = workspace.preparation.finish()
                self.sourcePreparation = nil
                switch pending {
                case .region(let rect, let scope): self.selectRegion(rect, scope: scope)
                case .displays(let region): self.selectDisplaysRegion(region)
                case .window(let id):
                    if let window = workspace.target.windows.first(where: { $0.windowID == id }) {
                        self.selectWindow(window)
                    }
                case nil: break
                }
            } catch {
                guard !Task.isCancelled, let self, self.workspace === workspace else { return }
                self.clearSelection()
                self.restoreAppendCapture()
                self.report(error)
            }
        }
    }
}
