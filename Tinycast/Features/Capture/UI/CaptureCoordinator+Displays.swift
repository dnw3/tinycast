import AppKit

extension CaptureCoordinator {
    func captureAcrossDisplays(all: Bool) {
        guard let workspace, !workspace.busy, editor?.busy != true,
            let screen = NSScreen.screens.first(where: { $0.frame == workspace.target.screenFrame })
        else { return }
        let action = workspace.request.action
        run { [weak self] in
            guard let self else { return }
            if self.pendingCapture != nil { self.editor = nil; self.clearSelection() } else {
                guard await self.mayClose() else { return }
            }
            do {
                try await self.prepareDisplays(screen: screen, action: action)
                if all, let selection = self.workspace?.displays { self.selectDisplaysRegion(selection.bounds) }
            } catch {
                self.restoreAppendCapture()
                throw error
            }
        }
    }

    private func prepareDisplays(screen: NSScreen, action: CaptureRequest.Action) async throws {
        let session = CaptureSessionState(id: UUID())
        selectionSession = session
        observeSession()
        var presented = false
        defer { if !presented { clearSelection() } }
        let screens = NSScreen.screens
        guard screens.count > 1, screens.count <= 32 else { throw CaptureScreenService.Failure.displayChanged }
        let repository = repository, id = UUID()
        let source = try await CaptureWork.run { try CaptureSource(directory: repository.create(id: id)) }
        var snapshots: [CaptureDisplaySelection.Snapshot] = []
        var primary: CaptureWorkspaceState?
        var pixels = 0
        for current in screens {
            try Task.checkCancellation()
            let target = try await CaptureScreenService.target(screen: current, scrolling: false)
            let estimated = target.screenFrame.width * target.screenFrame.height * target.scale * target.scale
            guard estimated <= Double(64_000_000 - pixels) else { throw CaptureRasterError.invalidSize }
            let image = try await CaptureScreenService.image(target: target, cursor: settings.preferences.includesCursor)
            let raster = UUID().uuidString
            let (size, preview) = try await CaptureWork.run {
                let size = try CaptureImageSource.store(image, at: source.directory.appendingPathComponent(raster))
                return (size, try CaptureImageSource.preview(image))
            }
            pixels += size.width * size.height
            snapshots.append(.init(display: .init(id: target.display.displayID,
                frame: target.screenFrame, scale: target.scale), raster: raster, preview: preview))
            if current == screen {
                let document = CaptureDocument(id: id, createdAt: Date(), size: size,
                    pieces: [.init(raster: raster, source: CGRect(x: 0, y: 0, width: size.width, height: size.height),
                        origin: .zero)], captureScale: Double(target.scale))
                primary = CaptureWorkspaceState(target: target, source: source, document: document,
                    preview: preview, request: .init(action: action), axis: settings.preferences.axis)
            }
        }
        try Task.checkCancellation()
        guard selectionSession?.accepts(id: session.id, revision: session.revision) == true,
            screens.map(\.frame) == NSScreen.screens.map(\.frame), let primary
        else { throw CaptureScreenService.Failure.displayChanged }
        primary.displays = CaptureDisplaySelection(snapshots: snapshots)
        selectionSession?.advance(to: .selecting)
        workspace = primary
        overlay.show(self, workspace: primary)
        presented = true
    }

    func selectDisplaysRegion(_ region: CGRect) {
        guard let workspace, let selection = workspace.displays, !workspace.busy else { return }
        do {
            let document = try selection.document(region: region, id: workspace.document.id,
                createdAt: workspace.document.createdAt)
            editor = CaptureEditorState(document: document, source: workspace.source)
            if pendingCapture != nil { finishAppendCapture(); return }
            let action = workspace.request.action
            expandCapture()
            if action != .edit { recognize(translate: action == .translate) }
        } catch { report(error) }
    }
}
