import AppKit
import ScreenCaptureKit

/// The screen as it stood under one of Tinycast's open menus, which closes once it is taken.
struct CaptureMenuSnapshot: Sendable {
    let displayID: CGDirectDisplayID
    let image: Task<CGImage, any Error>
}

extension CaptureCoordinator {
    /// All Tinycast shows is desktop, its system-drawn windows too; toasts and dialogs never are.
    func screenshotWindowIDs(keepingPalette: Bool) -> Set<CGWindowID> {
        func omitted(_ window: NSWindow) -> Bool {
            if let parent = window.parent, omitted(parent) { return true }
            return window.level >= .screenSaver || window is HUDPanel || window is DialogPanel
                || !keepingPalette && window is PalettePanel
        }
        let omittedIDs = NSApp.windows.filter(omitted).map { CGWindowID($0.windowNumber) }
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let onScreen = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
        let shown = onScreen.compactMap { info -> CGWindowID? in
            guard info[kCGWindowOwnerPID as String] as? pid_t == ownPID else { return nil }
            return info[kCGWindowNumber as String] as? CGWindowID
        }
        return Set(pins.compactMap(\.windowID)).union(shown).subtracting(omittedIDs)
    }

    /// AI Chat, Settings, Notes and the like, which scrolling and recording treat as any app's.
    func contentWindowIDs() -> Set<CGWindowID> {
        screenshotWindowIDs(keepingPalette: false).subtracting(pins.compactMap(\.windowID))
    }

    func prepare(
        screen: NSScreen, command: CommandID, keepingPalette: Bool = false,
        overMenu: CaptureMenuSnapshot? = nil
    ) async throws {
        try await prepare(
            screen: screen,
            request: CaptureRequest(
                mode: command == .captureScrollingScreenshot
                    ? .scrolling : command == .captureRecording ? .recording : .screenshot,
                scope: command == .captureFullscreen ? .screen : .region,
                action: command == .captureText ? .text : command == .captureAndTranslate ? .translate : .edit
            ), keepingPalette: keepingPalette, overMenu: overMenu)
    }

    /// A shortcut pressed over Tinycast's open menu: the screen is taken first, off the main actor.
    func snapshotOverMenu(for command: CommandID) -> CaptureMenuSnapshot? {
        let screenshots: Set<CommandID> = [
            .captureScreenshot, .captureFullscreen, .captureText, .captureAndTranslate
        ]
        guard screenshots.contains(command), let closeMenu = core.hotKeys.holdTrackingMenus() else {
            return nil
        }
        guard
            let displayID = NSScreen.underCursor?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")]
                as? CGDirectDisplayID
        else {
            closeMenu()
            return nil
        }
        let windowIDs = screenshotWindowIDs(keepingPalette: false)
        let cursor = settings.preferences.includesCursor
        let image = Task.detached {
            defer { closeMenu() }
            return try await CaptureScreenService.imageOverMenu(
                displayID: displayID, includedWindowIDs: windowIDs, cursor: cursor)
        }
        return CaptureMenuSnapshot(displayID: displayID, image: image)
    }

    func prepare(
        screen: NSScreen, request: CaptureRequest, keepingPalette: Bool = false,
        overMenu: CaptureMenuSnapshot? = nil
    ) async throws {
        let keepsPalette = keepingPalette && request.mode == .screenshot && core.paletteCoordinator.isVisible
        clearSelection()
        let session = CaptureSessionState(id: UUID())
        selectionSession = session
        observeSession()
        var presented = false
        defer { if !presented { clearSelection() } }
        let targetStarted = ContinuousClock.now
        let displayID =
            screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
        async let pendingTarget = { @MainActor in
            guard
                let screen = NSScreen.screens.first(where: {
                    $0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
                        == displayID
                })
            else { throw CaptureScreenService.Failure.displayChanged }
            return try await CaptureScreenService.target(
                screen: screen, scrolling: request.mode == .scrolling,
                includedWindowIDs: request.mode == .screenshot
                    ? self.screenshotWindowIDs(keepingPalette: keepsPalette) : self.contentWindowIDs())
        }()
        await Task.yield()
        let paletteStarted = ContinuousClock.now
        if !keepsPalette { core.paletteCoordinator.hidePalette(restoreFocus: false) }
        CapturePerformance.completed("selection-palette", since: paletteStarted)
        let target = try await pendingTarget
        CapturePerformance.completed("selection-target", since: targetStarted)
        let imageStarted = ContinuousClock.now
        let image =
            if let overMenu, overMenu.displayID == target.display.displayID {
                try await overMenu.image.value
            } else {
                try await CaptureScreenService.image(
                    target: target, cursor: settings.preferences.includesCursor, presentation: true)
            }
        CapturePerformance.completed("selection-snapshot", since: imageStarted)
        let id = UUID(), raster = UUID().uuidString, repository = repository
        let source = try await CaptureWork.run { try CaptureSource(directory: repository.create(id: id)) }
        let size = try CapturePixelSize(width: image.width, height: image.height)
        let document = CaptureDocument(
            id: id, createdAt: Date(), size: size,
            pieces: [
                .init(
                    raster: raster, source: CGRect(x: 0, y: 0, width: size.width, height: size.height),
                    origin: .zero)
            ], captureScale: Double(target.scale))
        try Task.checkCancellation()
        guard selectionSession?.accepts(id: session.id, revision: session.revision) == true else {
            throw CancellationError()
        }
        selectionSession?.advance(to: .selecting)
        let workspace = CaptureWorkspaceState(
            target: target, source: source, document: document, preview: image,
            request: request, axis: settings.preferences.axis)
        workspace.lastRegion = settings.lastRegion(
            displayID: target.display.displayID, screenSize: target.screenFrame.size)
        workspace.preparation = CaptureSelectionPreparation()
        self.workspace = workspace
        let presentationStarted = ContinuousClock.now
        overlay.show(self, workspace: workspace)
        // Under the overlay, whose frozen desktop already shows it, so it never visibly blinks out.
        if keepsPalette { core.paletteCoordinator.hidePalette(restoreFocus: false) }
        CapturePerformance.completed("selection-present", since: presentationStarted)
        presented = true
        prepareSource(workspace: workspace, images: [(image, raster)])
        if request.scope == .screen {
            selectRegion(CGRect(origin: .zero, size: target.screenFrame.size), scope: .screen)
        }
    }

    func selectRegion(_ rect: CGRect, scope: CaptureRequest.Scope = .region) {
        guard let workspace, !workspace.busy, editor?.busy != true,
            let pixels = CaptureGeometry.pixels(
                rect, screen: CGRect(origin: .zero, size: workspace.target.screenFrame.size),
                scale: workspace.target.scale)
        else { return }
        if workspace.preparation.deferSelection(.region(rect, scope)) { return }
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
                settings.remember(
                    .init(
                        displayID: workspace.target.display.displayID,
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
        workspace.preparation.discardSelection()
        guard Permissions.isAccessibilityTrusted() else {
            Permissions.ensureAccessibility()
            core.showMessage(
                String(localized: "Grant Accessibility, then choose Select Element again"), tone: .neutral)
            return
        }
        editor?.finishEditing()
        workspace.request.scope = .region
        workspace.choosingWindow = false
        workspace.choosingElement.toggle()
    }

    func sizeCaptureRegion(_ pixels: CGSize) {
        guard let workspace, let editor, let frame = workspace.frame(for: editor.document),
            let rect = CaptureSelectionConstraint.sized(
                frame, pixels: pixels, scale: workspace.target.scale,
                in: CGRect(origin: .zero, size: workspace.target.screenFrame.size))
        else { self.editor?.notice = String(localized: "Choose dimensions that fit this screen."); return }
        editor.notice = nil
        selectRegion(rect)
    }

    func selectWindow(_ window: SCWindow) {
        guard let workspace, !workspace.busy else { return }
        if workspace.preparation.deferSelection(.window(window.windowID)) { return }
        run { [weak self] in
            guard let self else { return }
            try await self.captureWindow(window, workspace: workspace)
            // Picked in scrolling mode, a window starts scrolling at once.
            guard workspace.request.mode == .scrolling, self.workspace === workspace else { return }
            try await self.scrollWindow(window, returnMode: .scrolling)
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
        if let editor = self.editor {
            editor.reframe(document)
        } else {
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
        workspace.preparation.discardSelection()
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
            !workspace.busy, editor?.busy != true
        else { return }
        editor?.finishEditing()
        workspace.requiresScrollRegion =
            mode == .scrolling
            && (workspace.request.scope != .region
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
                do { try await self.prepare(screen: screen, request: .init()) } catch {
                    self.restoreAppendCapture(); throw error
                }
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

    func beginScrollCapture(axis: CaptureDocument.Axis = .vertical) {
        guard let workspace else { return }
        let originalMode = workspace.request.mode
        workspace.axis = axis
        if let window = pickedWindow(in: workspace) {
            run { [weak self] in try await self?.scrollWindow(window, returnMode: originalMode) }
            return
        }
        if workspace.request.scope != .region
            || editor?.document.pieces.first?.raster != workspace.document.pieces.first?.raster
        {
            setCaptureMode(.scrolling)
            return
        }
        startSelectedScroll(returnMode: originalMode)
    }

    func startSelectedScroll(returnMode: CaptureRequest.Mode? = nil) {
        guard let start = scrollStart() else { return }
        run { [weak self] in try await self?.startScroll(start, returnMode: returnMode) }
    }

    /// What a selection hands a scrolling session, when it can start one at all.
    private struct ScrollStart {
        let workspace: CaptureWorkspaceState
        let editor: CaptureEditorState
        let rect: CGRect
        let screen: NSScreen
        let pixels: CGRect
    }

    private func scrollStart() -> ScrollStart? {
        guard let workspace, let editor, !workspace.busy, !editor.busy,
            !workspace.selectingTarget, !workspace.requiresScrollRegion,
            let rect = workspace.frame(for: editor.document),
            let screen = NSScreen.screens.first(where: { $0.frame == workspace.target.screenFrame }),
            let pixels = CaptureGeometry.pixels(
                rect, screen: CGRect(origin: .zero, size: screen.frame.size), scale: workspace.target.scale)
        else { return nil }
        return ScrollStart(workspace: workspace, editor: editor, rect: rect, screen: screen, pixels: pixels)
    }

    /// The window a click picked: it scrolls from its own content, with no region drawn first.
    private func pickedWindow(in workspace: CaptureWorkspaceState) -> SCWindow? {
        guard workspace.request.scope == .window, let raster = editor?.document.pieces.first?.raster,
            let id = workspace.sourceWindows[raster]
        else { return nil }
        return workspace.target.windows.first { $0.windowID == id }
    }

    /// The picked window is the region as picked, started without touching what is on screen first.
    private func scrollWindow(_ window: SCWindow, returnMode: CaptureRequest.Mode) async throws {
        guard let workspace, let editor, !workspace.busy, !editor.busy,
            let screen = NSScreen.screens.first(where: { $0.frame == workspace.target.screenFrame })
        else { return }
        let top = NSScreen.primary?.frame.maxY ?? 0
        let rect = CGRect(
            x: window.frame.minX, y: top - window.frame.maxY, width: window.frame.width, height: window.frame.height
        ).intersection(screen.frame).offsetBy(dx: -screen.frame.minX, dy: -screen.frame.minY)
        guard !rect.isEmpty,
            let pixels = CaptureGeometry.pixels(
                rect, screen: CGRect(origin: .zero, size: screen.frame.size), scale: workspace.target.scale)
        else {
            // Off this display, the reader draws the region as before.
            setCaptureMode(.scrolling)
            return
        }
        let start = ScrollStart(workspace: workspace, editor: editor, rect: rect, screen: screen, pixels: pixels)
        try await startScroll(start, returnMode: returnMode)
    }

    private func startScroll(_ start: ScrollStart, returnMode: CaptureRequest.Mode?) async throws {
        let workspace = start.workspace, editor = start.editor, screen = start.screen
        let rect = start.rect
        var pixels = start.pixels
        editor.finishEditing()
        workspace.busy = true
        var started = false
        defer {
            workspace.busy = false
            if !started {
                if let returnMode { workspace.request.mode = returnMode }
                self.overlay.resume()
            }
        }
        let target = try await CaptureScreenService.target(
            screen: screen, scrolling: true, includedWindowIDs: self.contentWindowIDs())
        let point = CGPoint(x: screen.frame.minX + rect.midX, y: screen.frame.minY + rect.midY)
        guard let window = CaptureScreenService.window(at: point, target: target),
            let pid = window.owningApplication?.processID
        else { throw CaptureScreenService.Failure.unavailable }
        // A drag that strays past the window's edge would otherwise read as leaving it at once.
        let edge = window.frame.offsetBy(dx: -target.display.frame.minX, dy: -target.display.frame.minY)
        pixels = pixels.intersection(CaptureGeometry.innerPixels(edge, scale: target.scale))
        guard !pixels.isEmpty else { throw CaptureScreenService.Failure.unavailable }
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
            document: .init(
                id: id, createdAt: Date(), size: size, pieces: [], axis: workspace.axis,
                captureScale: Double(target.scale)),
            source: source, target: target, region: region, windowID: window.windowID,
            pid: pid, windowFrame: window.frame, axis: workspace.axis,
            speed: self.settings.preferences.scrollSpeed)
        try self.scrollPanel.show(session, coordinator: self)
        self.overlay.suspend()
        self.otherResult = editor
        self.retainedWorkspace = workspace
        self.editor = nil
        self.scrollSource = source
        self.scroll = session
        self.clearSelection()
        self.activateScrollTarget(pid)
        session.start()
        started = true
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
        if let workspace = retainedWorkspace,
            NSScreen.screens.contains(where: { $0.frame == workspace.target.screenFrame })
        {
            retainedWorkspace = nil
            workspace.request.mode = .screenshot
            workspace.request.action = .edit
            workspace.preparation = CaptureSelectionPreparation(ready: true)
            workspace.busy = false
            self.workspace = workspace
            selectionSession = CaptureSessionState(id: UUID())
            selectionSession?.advance(to: .selecting)
            observeSession()
            overlay.show(self, workspace: workspace)
        } else {
            retainedWorkspace = nil
            editorWindow.show(self)
        }
    }

    private func performCaptureAction() {
        guard let workspace, workspace.request.action != .edit else { return }
        let translate = workspace.request.action == .translate
        workspace.request.action = .edit
        recognize(translate: translate)
    }
}
