import AppKit
import Observation
import ScreenCaptureKit

@MainActor
@Observable
final class CaptureCoordinator {
    let settings = CaptureSettingsStore()
    var editor: CaptureEditorState?
    var scroll: ScrollCaptureSession?
    var workspace: CaptureWorkspaceState?
    var otherResult: CaptureEditorState?
    var pendingCapture: CaptureAppendState?
    var historyEntries: [CaptureHistoryEntry] = []
    var historyQuery = ""
    var pins: [CapturePinController] = []
    var exportOptions = CaptureExportOptions()
    var countdown: Int?
    var recording: CaptureRecordingSession?
    var video: CaptureVideoState?
    var uploadConnecting = false
    var uploadNotice: String?
    @ObservationIgnored unowned let core: AppCore
    @ObservationIgnored var task: Task<Void, Never>?
    @ObservationIgnored var uploadAuthorization: Task<Void, Never>?
    @ObservationIgnored lazy var repository = CaptureRepository(
        root: AppPaths.applicationSupport().appendingPathComponent("captures"))
    @ObservationIgnored lazy var editorWindow = CaptureEditorController(activation: core.activationPolicy)
    @ObservationIgnored let overlay = CaptureOverlayController()
    @ObservationIgnored let scrollPanel = ScrollCapturePanelController()
    @ObservationIgnored let countdownPanel = CaptureCountdownController()
    @ObservationIgnored let recordingPanel = CaptureRecordingController()
    @ObservationIgnored lazy var videoWindow = CaptureVideoController(activation: core.activationPolicy)
    @ObservationIgnored lazy var previewWindow = CapturePreviewController(activation: core.activationPolicy)
    @ObservationIgnored var scrollSource: CaptureSource?
    @ObservationIgnored var selectionSession: CaptureSessionState?
    @ObservationIgnored var savePanel: NSSavePanel?
    @ObservationIgnored var previousApp: NSRunningApplication?
    @ObservationIgnored var sessionObserver: CaptureSessionObserver?
    @ObservationIgnored let sharing = CaptureShareController()
    @ObservationIgnored let completionThumbnail = CaptureCompletionController()

    init(core: AppCore) { self.core = core }

    var metrics: InterfaceMetrics { core.settings.interfaceSize.metrics }

    func focusExisting() -> Bool {
        if let savePanel, savePanel.isVisible {
            NSApp.activate()
            savePanel.makeKeyAndOrderFront(nil)
            return true
        }
        return previewWindow.focusExisting() || editorWindow.focusExisting()
            || videoWindow.focusExisting() || overlay.focusExisting()
    }

    func applyEnabled() {
        core.appIndex.setCommandsVisible(Set(SettingsTab.capture.ownedCommands), settings.preferences.enabled)
    }

    func setEnabled(_ enabled: Bool) {
        run { [weak self] in
            guard let self else { return }
            if !enabled {
                if self.recording != nil { try await self.finishRecordingCurrent() }
                await self.stopScrollingForClose()
                if !(await self.mayClose()) { return }
                self.stop()
            }
            self.settings.preferences.enabled = enabled
            self.applyEnabled()
        }
    }

    func open(_ command: CommandID) {
        let started = ContinuousClock.now
        guard settings.preferences.enabled else { return }
        completionThumbnail.close()
        if recording != nil { finishRecording(); return }
        if scroll != nil { finishScroll(); return }
        if workspace != nil { return }
        run { [weak self] in
            guard let self else { return }
            if command == .captureHistory { try await self.loadHistory(); return }
            let closeStarted = ContinuousClock.now
            guard await self.mayClose() else { return }
            CapturePerformance.completed("selection-close", since: closeStarted)
            self.previousApp =
                self.core.paletteCoordinator.targetApp
                ?? NSWorkspace.shared.frontmostApplication
            if command == .editClipboardImage || command == .pinClipboardImage {
                try await self.importClipboard(pin: command == .pinClipboardImage)
                return
            }
            let permissionStarted = ContinuousClock.now
            let permitted = CGPreflightScreenCaptureAccess()
            CapturePerformance.completed("selection-permission", since: permissionStarted)
            guard permitted else {
                let allow = await self.core.confirm(
                    title: "Allow Screen Recording",
                    message:
                        "Capture needs Screen Recording permission. After granting it, run the command again.",
                    symbol: "camera", confirmTitle: "Open Permission", tone: .neutral, confirmRole: .standard)
                if allow { CGRequestScreenCaptureAccess(); self.openScreenPermission() }
                return
            }
            guard let screen = NSScreen.underCursor else { return }
            try await Signposts.interval("Capture Prepare") {
                try await self.prepare(screen: screen, command: command)
            }
            CapturePerformance.completed("selection-ready", since: started)
        }
    }

    func show(document: CaptureDocument, source: CaptureSource) {
        clearSelection()
        editor = CaptureEditorState(document: document, source: source)
        editorWindow.show(self)
    }

    func requestClose() {
        if pendingCapture != nil { restoreAppendCapture(); return }
        run { [weak self] in
            guard let self, await self.mayClose() else { return }
            self.restoreFocus()
        }
    }

    func mayClose() async -> Bool {
        let hadWorkspace = editor != nil || otherResult != nil || video != nil
        if pendingCapture != nil { restoreAppendCapture() }
        guard await mayCloseVideo() else { return false }
        let states = [editor, otherResult].compactMap { $0 }
        for state in states { state.finishEditing() }
        guard !states.contains(where: { $0.busy }) else {
            core.showMessage("Finish or cancel the current operation first", tone: .neutral)
            return false
        }
        overlay.suspend()
        var closed = false
        defer { if !closed { overlay.resume() } }
        for state in states where state.needsPreservation {
            let choice = await core.choose(
                title: state.document.axis == nil ? "Keep this screenshot?" : "Keep this scrolling screenshot?",
                message: "Save an editable draft to keep your original and annotations.", symbol: "camera",
                options: [
                    .init(title: "Cancel", role: .cancel), .init(title: "Discard", role: .destructive),
                    .init(title: "Save Draft")
                ], defaultIndex: 2)
            if choice == 0 { return false }
            if choice == 2 {
                do { try await publishDraft(state) } catch { report(error); return false }
            }
        }
        clearSelection()
        editorWindow.close()
        editor = nil
        otherResult = nil
        video?.player.pause()
        video = nil
        videoWindow.close()
        closed = true
        if hadWorkspace { CapturePerformance.closed() }
        return true
    }

    func finishScroll() {
        run { [weak self] in
            guard let self, let session = self.scroll, let source = self.scrollSource else { return }
            await session.stop()
            self.scrollPanel.close()
            self.scroll = nil; self.scrollSource = nil
            self.sessionObserver = nil
            if !session.document.pieces.isEmpty {
                self.show(document: session.document, source: source)
            } else { self.restoreOtherResult() }
        }
    }

    func cancelScroll() {
        run { [weak self] in
            guard let self, let session = self.scroll else { return }
            session.pause()
            var keep = false
            if session.document.pieces.count > 1 {
                let choice = await self.core.choose(
                    title: "Keep captured content?", message: nil, symbol: "camera",
                    options: [
                        .init(title: "Back", role: .cancel), .init(title: "Discard", role: .destructive),
                        .init(title: "Keep Result")
                    ], defaultIndex: 2)
                if choice == 0 { return }
                keep = choice == 2
            }
            await session.stop()
            let source = self.scrollSource
            self.scrollPanel.close()
            self.scroll = nil; self.scrollSource = nil
            self.sessionObserver = nil
            if keep, let source { self.show(document: session.document, source: source) } else { self.restoreOtherResult() }
        }
    }

    func toggleAutomaticScroll() {
        guard let scroll else { return }
        if scroll.automatic { scroll.automatic = false; return }
        if !Permissions.isAccessibilityTrusted() {
            scroll.pause("Grant Accessibility permission, then choose Auto Scroll again")
            Permissions.ensureAccessibility()
            return
        }
        scroll.resume()
        scroll.automatic = true
    }

    func restartScroll() {
        run { [weak self] in
            guard let self, let session = self.scroll else { return }
            session.pause()
            let choice = await self.core.choose(
                title: "Select another region?", message: "Keep this result, or discard it and select again.",
                symbol: "crop",
                options: [
                    .init(title: "Back", role: .cancel), .init(title: "Keep Result"),
                    .init(title: "Discard and Reselect", role: .destructive)
                ], defaultIndex: 1)
            guard choice != 0 else { return }
            await session.stop()
            let source = self.scrollSource
            self.scrollPanel.close(); self.scroll = nil; self.scrollSource = nil; self.sessionObserver = nil
            if choice == 1, let source, !session.document.pieces.isEmpty {
                self.show(document: session.document, source: source)
            } else if let screen = NSScreen.screens.first(where: { $0.frame == session.target.screenFrame })
                ?? NSScreen.underCursor
            {
                self.restoreOtherResult()
                guard await self.mayClose() else { return }
                try await self.prepare(screen: screen, command: .captureScrollingScreenshot)
            }
        }
    }

    func clearSelection() {
        selectionSession?.advance(to: .closed)
        selectionSession = nil
        overlay.close()
        workspace = nil
        if scroll == nil, recording == nil { sessionObserver = nil }
    }

    func cancelWork() {
        savePanel?.cancel(nil)
        task?.cancel()
        editor?.cancelEditingWork?()
        otherResult?.cancelEditingWork?()
    }

    func stop() {
        uploadAuthorization?.cancel()
        completionThumbnail.close()
        cancelWork()
        scroll?.cancel()
        scroll = nil
        scrollSource = nil
        clearSelection()
        scrollPanel.close()
        countdownPanel.close()
        countdown = nil
        recordingPanel.close()
        video?.player.pause()
        videoWindow.close()
        video = nil
        previewWindow.close()
        editorWindow.close()
        editor = nil
        otherResult = nil
        for pin in pins { pin.close() }
        pendingCapture = nil
        pins = []
        sessionObserver = nil
    }

    func prepareToTerminate() async -> Bool {
        if let task { cancelWork(); await task.value }
        if recording != nil {
            do { try await finishRecordingCurrent() } catch { report(error); return false }
        }
        await stopScrollingForClose()
        return await mayClose()
    }

    private func stopScrollingForClose() async {
        guard let session = scroll else { return }
        await session.stop()
        let source = scrollSource
        scroll = nil
        scrollSource = nil
        scrollPanel.close()
        sessionObserver = nil
        if let source, !session.document.pieces.isEmpty {
            show(document: session.document, source: source)
        } else { restoreOtherResult() }
    }

    func run(_ operation: @escaping @MainActor () async throws -> Void) {
        guard task == nil else { return }
        task = Task { [weak self] in
            defer { self?.task = nil }
            do { try await operation() } catch is CancellationError {
                self?.editor?.notice = "Cancelled"
            } catch { self?.report(error) }
        }
    }

    func report(_ error: Error) {
        editor?.notice = error.localizedDescription
        recording?.notice = error.localizedDescription
        video?.notice = error.localizedDescription
        core.showMessage(error.localizedDescription, tone: .danger)
    }

    func restoreFocus() {
        if NSWorkspace.shared.frontmostApplication?.processIdentifier
            == ProcessInfo.processInfo.processIdentifier
        {
            previousApp?.activate()
        }
    }

    func openScreenPermission() {
        if let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")
        {
            NSWorkspace.shared.open(url)
        }
    }

    func observeSession() {
        sessionObserver = CaptureSessionObserver { [weak self] reason in
            guard let self else { return }
            self.scroll?.pause(reason)
            self.pauseRecording(reason: reason)
            if self.selectionSession != nil || self.countdown != nil { self.task?.cancel() }
            self.clearSelection()
            self.restoreAppendCapture()
            self.editor?.notice = reason
            if self.editor != nil { self.editorWindow.show(self) }
        }
    }
}
