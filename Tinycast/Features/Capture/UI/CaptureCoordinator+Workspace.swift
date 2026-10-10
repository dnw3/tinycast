import AppKit
import ScreenCaptureKit

extension CaptureCoordinator {
    func prepare(screen: NSScreen, command: CommandID) async throws {
        try await prepare(screen: screen, request: CaptureRequest(
            mode: command == .captureScrollingScreenshot ? .scrolling : command == .captureRecording ? .recording : .screenshot,
            scope: command == .captureFullscreen ? .screen : .region,
            action: command == .captureText ? .text : command == .captureAndTranslate ? .translate : .edit))
    }

    func prepare(screen: NSScreen, request: CaptureRequest) async throws {
        clearSelection()
        let session = CaptureSessionState(id: UUID())
        selectionSession = session
        observeSession()
        var presented = false
        defer { if !presented { clearSelection() } }
        let targetStarted = ContinuousClock.now
        let displayID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
        async let pendingTarget = { @MainActor in
            guard let screen = NSScreen.screens.first(where: {
                $0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID == displayID
            }) else { throw CaptureScreenService.Failure.displayChanged }
            return try await CaptureScreenService.target(screen: screen, scrolling: request.mode == .scrolling)
        }()
        await Task.yield()
        let paletteStarted = ContinuousClock.now
        core.paletteCoordinator.hidePalette(restoreFocus: false)
        CapturePerformance.completed("selection-palette", since: paletteStarted)
        let target = try await pendingTarget
        CapturePerformance.completed("selection-target", since: targetStarted)
        let imageStarted = ContinuousClock.now
        let image = try await CaptureScreenService.image(target: target, cursor: settings.preferences.includesCursor)
        CapturePerformance.completed("selection-snapshot", since: imageStarted)
        let rasterStarted = ContinuousClock.now
        let id = UUID(), raster = UUID().uuidString, repository = repository, scale = Double(target.scale)
        let result = try await CaptureWork.run {
            let storeStarted = ContinuousClock.now
            let source = try CaptureSource(directory: try repository.create(id: id))
            let size = try CaptureImageSource.store(image, at: source.directory.appendingPathComponent(raster))
            let document = CaptureDocument(
                id: id, createdAt: Date(), size: size,
                pieces: [.init(raster: raster, source: CGRect(x: 0, y: 0, width: size.width, height: size.height),
                    origin: .zero)], captureScale: scale)
            CapturePerformance.completed("selection-store", since: storeStarted)
            let previewStarted = ContinuousClock.now
            let preview = try CaptureImageSource.preview(image)
            CapturePerformance.completed("selection-preview", since: previewStarted)
            return (source, document, preview)
        }
        CapturePerformance.completed("selection-raster", since: rasterStarted)
        try Task.checkCancellation()
        guard selectionSession?.accepts(id: session.id, revision: session.revision) == true else {
            throw CancellationError()
        }
        selectionSession?.advance(to: .selecting)
        let workspace = CaptureWorkspaceState(
            target: target, source: result.0, document: result.1, preview: result.2,
            request: request, axis: settings.preferences.axis)
        workspace.lastRegion = settings.lastRegion(displayID: target.display.displayID, screenSize: target.screenFrame.size)
        self.workspace = workspace
        if request.scope == .screen { editor = CaptureEditorState(document: result.1, source: result.0) }
        let presentationStarted = ContinuousClock.now
        overlay.show(self, workspace: workspace)
        CapturePerformance.completed("selection-present", since: presentationStarted)
        presented = true
    }

    func selectRegion(_ rect: CGRect, scope: CaptureRequest.Scope = .region) {
        guard let workspace, !workspace.busy, editor?.busy != true,
            let pixels = CaptureGeometry.pixels(
                rect, screen: CGRect(origin: .zero, size: workspace.target.screenFrame.size),
                scale: workspace.target.scale)
        else { return }
        do {
            let base = workspace.document
            if let editor, let oldFrame = workspace.frame(for: editor.document, cropped: false) {
                editor.finishEditing()
                let frame = CaptureSelectionGeometry.frame(
                    pixels: pixels, in: CGRect(origin: .zero, size: workspace.target.screenFrame.size),
                    scale: workspace.target.scale)
                let replacement = try CaptureSelectionGeometry.reframe(
                    editor.document, raster: base.pieces[0].raster, pixels: pixels,
                    oldFrame: oldFrame, newFrame: frame,
                    oldScale: workspace.scale(for: editor.document), scale: workspace.target.scale)
                editor.reframe(replacement)
            } else {
                var document = base
                document.size = try CapturePixelSize(width: Int(pixels.width), height: Int(pixels.height))
                document.pieces[0].source = pixels
                editor = CaptureEditorState(document: document, source: workspace.source)
            }
            workspace.request.scope = scope
            workspace.choosingWindow = false
            workspace.choosingElement = false
            workspace.requiresScrollRegion = false
            if scope == .region {
                settings.remember(.init(displayID: workspace.target.display.displayID,
                    screenSize: workspace.target.screenFrame.size, rect: rect))
            }
            performCaptureAction()
        } catch { report(error) }
    }

    func restoreCaptureRegion() {
        guard let workspace, let rect = workspace.lastRegion
        else { return }
        selectRegion(rect)
    }

    func chooseCaptureElement() {
        guard let workspace, !workspace.busy, editor?.busy != true else { return }
        guard Permissions.isAccessibilityTrusted() else {
            Permissions.ensureAccessibility()
            core.showMessage("Grant Accessibility, then choose Select Element again", tone: .neutral)
            return
        }
        editor?.finishEditing()
        workspace.request.scope = .region
        workspace.choosingWindow = false
        workspace.choosingElement.toggle()
    }

    func sizeCaptureRegion(_ pixels: CGSize) {
        guard let workspace, let editor, let frame = workspace.frame(for: editor.document),
            let rect = CaptureSelectionConstraint.sized(frame, pixels: pixels, scale: workspace.target.scale,
                in: CGRect(origin: .zero, size: workspace.target.screenFrame.size))
        else { self.editor?.notice = "Choose dimensions that fit this screen."; return }
        editor.notice = nil
        selectRegion(rect)
    }

    func selectWindow(_ window: SCWindow) {
        guard let workspace, !workspace.busy else { return }
        run { [weak self] in
            try await self?.captureWindow(window, workspace: workspace)
        }
    }

    func captureWindow(_ window: SCWindow, workspace: CaptureWorkspaceState) async throws {
        workspace.busy = true
        defer { workspace.busy = false }
        self.editor?.finishEditing()
        let image = try await CaptureScreenService.image(
            target: workspace.target, window: window, cursor: self.settings.preferences.includesCursor)
        let source = workspace.source, raster = UUID().uuidString
        let size = try await CaptureWork.run {
            try CaptureImageSource.store(image, at: source.directory.appendingPathComponent(raster))
        }
        try Task.checkCancellation()
        guard self.workspace === workspace else { return }
        let frame = CGRect(
            x: window.frame.minX - workspace.target.screenFrame.minX,
            y: (NSScreen.primary?.frame.maxY ?? 0) - window.frame.maxY - workspace.target.screenFrame.minY,
            width: window.frame.width, height: window.frame.height)
        workspace.sourceFrames[raster] = (frame, CGFloat(size.width) / frame.width)
        workspace.sourceWindows[raster] = window.windowID
        var document = workspace.document
        document.size = size
        document.captureScale = Double(size.width) / window.frame.width
        document.pieces = [.init(raster: raster, source: document.bounds, origin: .zero)]
        if let editor = self.editor { editor.reframe(document) } else {
            self.editor = CaptureEditorState(document: document, source: source)
        }
        workspace.request.scope = .window
        workspace.choosingWindow = false
        workspace.choosingElement = false
        workspace.requiresScrollRegion = workspace.request.mode == .scrolling
        if workspace.request.action != .edit {
            let translate = workspace.request.action == .translate
            workspace.request.action = .edit
            try await self.recognizeCurrent(translate: translate)
        }
    }

    func setCaptureScope(_ scope: CaptureRequest.Scope) {
        guard let workspace, workspace.displays == nil, !workspace.busy, editor?.busy != true else { return }
        editor?.finishEditing()
        workspace.request.scope = scope
        workspace.choosingWindow = scope == .window
        workspace.choosingElement = false
        if scope == .screen {
            if workspace.request.mode == .scrolling { workspace.request.mode = .screenshot }
            selectRegion(CGRect(origin: .zero, size: workspace.target.screenFrame.size), scope: .screen)
        }
    }

    func setCaptureMode(_ mode: CaptureRequest.Mode) {
        guard pendingCapture == nil, let workspace, workspace.displays == nil,
            !workspace.busy, editor?.busy != true else { return }
        editor?.finishEditing()
        workspace.requiresScrollRegion = mode == .scrolling && (workspace.request.scope != .region
            || editor?.document.pieces.first?.raster != workspace.document.pieces.first?.raster)
        workspace.request.mode = mode
        workspace.choosingWindow = false
        workspace.choosingElement = false
        if mode == .scrolling { workspace.request.scope = .region }
    }

    func switchCaptureScreen(_ screen: NSScreen) {
        run { [weak self] in
            if let self, self.pendingCapture != nil {
                self.editor = nil
                do { try await self.prepare(screen: screen, request: .init()) } catch { self.restoreAppendCapture(); throw error }
                return
            }
            guard let self, let workspace = self.workspace, await self.mayClose() else { return }
            try await self.prepare(screen: screen, request: workspace.request)
        }
    }

    func expandCapture() {
        guard let editor, !editor.busy, workspace?.busy != true else { return }
        editor.finishEditing()
        clearSelection()
        editor.fit()
        editorWindow.show(self)
    }

    func completeSelection() {
        guard let workspace, !workspace.selectingTarget else { return }
        if let selection = workspace.displays {
            selectDisplaysRegion(selection.region ?? selection.bounds)
            return
        }
        if pendingCapture != nil { finishAppendCapture(); return }
        switch workspace.request.mode {
        case .screenshot: copy()
        case .scrolling: startSelectedScroll()
        case .recording: startSelectedRecording()
        }
    }

    func startSelectedScroll() {
        guard let workspace, let editor, !workspace.busy, !editor.busy,
            !workspace.selectingTarget, !workspace.requiresScrollRegion,
            let rect = workspace.frame(for: editor.document),
            let screen = NSScreen.screens.first(where: { $0.frame == workspace.target.screenFrame }),
            let pixels = CaptureGeometry.pixels(
                rect, screen: CGRect(origin: .zero, size: screen.frame.size), scale: workspace.target.scale)
        else { return }
        run { [weak self] in
            guard let self else { return }
            editor.finishEditing()
            workspace.busy = true
            self.overlay.suspend()
            var started = false
            defer {
                workspace.busy = false
                if !started { self.overlay.resume() }
            }
            let target = try await CaptureScreenService.target(screen: screen, scrolling: true)
            let point = CGPoint(x: screen.frame.minX + rect.midX, y: screen.frame.minY + rect.midY)
            guard let window = CaptureScreenService.window(at: point, target: target),
                let pid = window.owningApplication?.processID
            else { throw CaptureScreenService.Failure.unavailable }
            let repository = self.repository, id = UUID()
            let source = try await CaptureWork.run {
                try CaptureSource(directory: try repository.create(id: id))
            }
            try Task.checkCancellation()
            guard self.workspace === workspace else { throw CancellationError() }
            let region = CGRect(
                x: pixels.minX / target.scale, y: pixels.minY / target.scale,
                width: pixels.width / target.scale, height: pixels.height / target.scale)
            let size = try CapturePixelSize(width: Int(pixels.width), height: Int(pixels.height))
            let session = ScrollCaptureSession(
                document: .init(id: id, createdAt: Date(), size: size, pieces: [], axis: workspace.axis,
                    captureScale: Double(target.scale)),
                source: source, target: target, region: region, windowID: window.windowID,
                pid: pid, windowFrame: window.frame, axis: workspace.axis,
                speed: self.settings.preferences.scrollSpeed)
            try self.scrollPanel.show(session, coordinator: self)
            self.otherResult = editor
            self.editor = nil
            self.scrollSource = source
            self.scroll = session
            self.clearSelection()
            NSRunningApplication(processIdentifier: pid)?.activate()
            session.start()
            started = true
        }
    }

    func swapCaptureResult() {
        guard let otherResult, editor?.busy != true, !otherResult.busy else { return }
        editor?.finishEditing()
        let current = editor
        editor = otherResult
        self.otherResult = current
    }

    func restoreOtherResult() {
        guard editor == nil, let otherResult else { return }
        editor = otherResult
        self.otherResult = nil
        editorWindow.show(self)
    }

    private func performCaptureAction() {
        guard let workspace, workspace.request.action != .edit else { return }
        let translate = workspace.request.action == .translate
        workspace.request.action = .edit
        recognize(translate: translate)
    }
}
