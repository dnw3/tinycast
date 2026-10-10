import AppKit
import AVFoundation
import ScreenCaptureKit
import UniformTypeIdentifiers

extension CaptureCoordinator {
    func startSelectedRecording() {
        guard let workspace, let editor, recording == nil, !workspace.busy, !editor.busy,
            !workspace.selectingTarget, let rect = workspace.frame(for: editor.document)
        else { return }
        run { [weak self] in
            guard let self else { return }
            let options = try workspace.recordingOptions.validated()
            editor.finishEditing()
            workspace.busy = true
            self.overlay.suspend()
            var started = false
            defer {
                workspace.busy = false
                self.countdownPanel.close()
                self.countdown = nil
                if !started { self.recording = nil; self.overlay.resume() }
            }
            if options.microphone {
                guard await AVCaptureDevice.requestAccess(for: .audio) else {
                    throw RecordingFailure.microphonePermission
                }
            }
            if options.camera {
                guard await AVCaptureDevice.requestAccess(for: .video) else { throw RecordingFailure.cameraPermission }
            }
            if options.keys != .off, !Permissions.isAccessibilityTrusted() {
                throw CaptureRecordingLayers.Failure.keyboardUnavailable
            }
            self.restoreFocus()
            if options.delay > 0 {
                self.countdownPanel.show(self, frame: workspace.target.screenFrame)
                let deadline = ContinuousClock.now.advanced(by: .seconds(options.delay))
                for remaining in stride(from: options.delay, through: 1, by: -1) {
                    self.countdown = remaining
                    try await Task.sleep(until: deadline.advanced(by: .seconds(1 - remaining)), clock: .continuous)
                }
                self.countdownPanel.close()
            }
            try Task.checkCancellation()
            guard let screen = NSScreen.screens.first(where: { $0.frame == workspace.target.screenFrame }) else {
                throw CaptureScreenService.Failure.displayChanged
            }
            let target = try await CaptureScreenService.target(screen: screen, scrolling: false)
            let windowID = workspace.request.scope == .window
                ? editor.document.pieces.first.flatMap { workspace.sourceWindows[$0.raster] } : nil
            let filter: SCContentFilter
            let region: CGRect?
            if workspace.request.scope == .window {
                guard let windowID, let window = target.windows.first(where: { $0.windowID == windowID }) else {
                    throw CaptureRecordingSession.Failure.windowUnavailable
                }
                filter = SCContentFilter(desktopIndependentWindow: window)
                region = nil
            } else {
                filter = target.filter
                region = CGRect(x: rect.minX, y: target.screenFrame.height - rect.maxY,
                    width: rect.width, height: rect.height)
            }
            let dimensions = (region ?? filter.contentRect).size
            let size = try options.outputSize(CGSize(width: dimensions.width * CGFloat(filter.pointPixelScale),
                height: dimensions.height * CGFloat(filter.pointPixelScale)))
            let repository = self.repository
            let source = try await CaptureWork.run { try CaptureSource(directory: try repository.create(id: UUID())) }
            let session = CaptureRecordingSession(source: source, size: size,
                frame: rect.offsetBy(dx: target.screenFrame.minX, dy: target.screenFrame.minY), options: options,
                filter: filter, region: region, windowID: windowID, displayID: target.display.displayID
            ) { [weak self] reason in self?.pauseRecording(reason: reason) }
            self.recording = session
            try await session.resume()
            if Task.isCancelled {
                try await session.pause()
                throw CancellationError()
            }
            self.otherResult = editor
            self.editor = nil
            self.clearSelection()
            self.observeSession()
            self.recordingPanel.show(session, coordinator: self)
            self.restoreFocus()
            started = true
        }
    }

    func toggleRecordingPause() {
        run { [weak self] in
            guard let session = self?.recording else { return }
            if session.phase == .paused { try await session.resume() } else { try await session.pause() }
        }
    }

    func pauseRecording(reason: String) {
        guard let recording else { return }
        if recording.phase == .starting { task?.cancel(); return }
        run { [weak self] in
            guard let session = self?.recording else { return }
            try await session.pause(reason: reason)
        }
    }

    func finishRecording() { run { [weak self] in try await self?.finishRecordingCurrent() } }

    func finishRecordingCurrent() async throws {
        guard let recording else { return }
        let url = try await recording.finish()
        let info = try await CaptureVideoService.inspect(url)
        let state = CaptureVideoState(source: recording.source, url: url, info: info)
        state.exportOptions.videoFramesPerSecond = recording.options.framesPerSecond
        video = state
        self.recording = nil
        recordingPanel.close()
        sessionObserver = nil
        videoWindow.show(self)
        switch recording.options.completion {
        case .preview: break
        case .saveFile: _ = try await saveVideoCurrent(state)
        case .copyFile: try await shareVideoCurrent(state, delivery: .copy)
        }
    }

    func saveVideo() {
        run { [weak self] in
            guard let self, let video = self.video else { return }
            _ = try await self.saveVideoCurrent(video)
        }
    }

    func saveVideoDraft() {
        run { [weak self] in
            guard let self, let state = self.video, !state.busy else { return }
            state.player.pause()
            state.busy = true
            state.progress = 0
            defer { state.busy = false; state.progress = nil }
            let snapshot = try state.edit.validated(duration: state.info.duration)
            let rendered = state.source.directory.appendingPathComponent("draft-\(UUID()).mp4")
            defer { try? FileManager.default.removeItem(at: rendered) }
            var options = state.exportOptions
            options.format = .mp4
            try await CaptureVideoService.render(state.url, edit: snapshot, options: options, to: rendered) { value in
                await MainActor.run { state.progress = value }
            }
            let info = try await CaptureVideoService.inspect(rendered)
            let preview = try await CaptureVideoService.thumbnail(rendered), repository = self.repository
            let draft = CaptureRepository.VideoDraft(original: state.url, duration: state.info.duration, edit: snapshot)
            try await CaptureWork.run { _ = try repository.commitVideo(rendered, info: info, preview: preview, draft: draft) }
            state.savedEdit = snapshot
            state.notice = "Draft saved with the original recording. Copy and preview use the edited result."
            self.core.showMessage("Saved editable video draft", tone: .success)
        }
    }

    func showScreenshotResult() {
        guard let video, !video.busy, let image = otherResult, !image.busy else { return }
        video.player.pause()
        videoWindow.close()
        editor = image
        otherResult = nil
        editorWindow.show(self)
    }

    func showRecordingResult() {
        guard let video, !video.busy, let editor, !editor.busy else { return }
        editor.finishEditing()
        otherResult = editor
        self.editor = nil
        editorWindow.close()
        videoWindow.show(self)
    }

    func saveVideoCurrent(_ state: CaptureVideoState) async throws -> Bool {
        guard !state.busy else { return false }
        state.player.pause()
        state.busy = true
        defer { state.busy = false; savePanel = nil }
        let snapshot = try state.edit.validated(duration: state.info.duration)
        let options = state.exportOptions
        let panel = NSSavePanel()
        panel.allowedContentTypes = options.format == .mp4 ? [.mpeg4Movie] : [.gif]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = "Recording.\(options.format.rawValue)"
        savePanel = panel
        let response = await videoWindow.present(panel)
        savePanel = nil
        guard response == .OK, let destination = panel.url else { return false }
        let rendered = state.source.directory.appendingPathComponent("export-\(UUID().uuidString).\(options.format.rawValue)")
        defer { state.progress = nil; try? FileManager.default.removeItem(at: rendered) }
        do {
            if options.format == .mp4 {
                state.progress = 0
                try await CaptureVideoService.render(state.url, edit: snapshot, options: options, to: rendered) { value in
                    await MainActor.run { state.progress = value }
                }
            } else {
                state.progress = 0
                try await CaptureGIFService.render(state.url, edit: snapshot, options: options, to: rendered) { value in
                    await MainActor.run { state.progress = value }
                }
            }
            try await CaptureWork.run {
                let files = FileManager.default
                let temporary = destination.deletingLastPathComponent().appendingPathComponent(".\(UUID().uuidString).tmp")
                defer { try? files.removeItem(at: temporary) }
                try files.copyItem(at: rendered, to: temporary)
                try Task.checkCancellation()
                if files.fileExists(atPath: destination.path) {
                    _ = try files.replaceItemAt(destination, withItemAt: temporary)
                } else { try files.moveItem(at: temporary, to: destination) }
            }
            state.savedEdit = snapshot
            state.notice = nil
            let repository = repository, preferences = settings.preferences
            do {
                let entry: CaptureHistoryEntry
                if options.format == .gif {
                    entry = try await CaptureWork.run { try repository.commitGIF(rendered) }
                } else {
                    let info = try await CaptureVideoService.inspect(rendered)
                    let preview = try await CaptureVideoService.thumbnail(rendered)
                    entry = try await CaptureWork.run { try repository.commitVideo(rendered, info: info, preview: preview) }
                }
                try await CaptureWork.run {
                    try repository.prune(now: Date(), days: max(1, preferences.retentionDays),
                        maximumBytes: max(16, preferences.maximumHistoryMB) * 1_048_576)
                }
                core.showMessage(options.format == .gif ? "Saved GIF" : "Saved recording", tone: .success)
                completionThumbnail.show(entry, coordinator: self)
            } catch {
                state.notice = "Saved — history could not be saved. Save again to retry."
                core.showMessage("Saved — history could not be saved", tone: .neutral)
            }
            return true
        } catch {
            state.notice = error is CancellationError
                ? "Export cancelled. Your recording is still open." : error.localizedDescription
            throw error
        }
    }

    func mayCloseVideo() async -> Bool {
        guard let video, video.needsPreservation else { return true }
        guard !video.busy else { return false }
        video.player.pause()
        let choice = await core.choose(title: "Keep this recording?",
            message: "Save the video before closing.", symbol: "record.circle",
            options: [.init(title: "Cancel", role: .cancel), .init(title: "Discard", role: .destructive),
                .init(title: "Save Video")], defaultIndex: 2)
        if choice == 0 { return false }
        if choice == 1 { return true }
        do { return try await saveVideoCurrent(video) } catch { report(error); return false }
    }

    func openVideoHistory(_ entry: CaptureHistoryEntry) async throws {
        let repository = repository
        let (source, edit) = try await CaptureWork.run { try repository.openVideo(entry, id: UUID()) }
        let url = source.directory.appendingPathComponent(edit == nil ? entry.filename : "original.mp4")
        let info = try await CaptureVideoService.inspect(url)
        let validated = try edit?.validated(duration: info.duration)
        core.paletteCoordinator.hidePalette(restoreFocus: false)
        let state = CaptureVideoState(source: source, url: url, info: info, edit: validated)
        state.savedEdit = state.edit
        video = state
        videoWindow.show(self)
    }

    enum RecordingFailure: LocalizedError {
        case microphonePermission, cameraPermission
        var errorDescription: String? {
            switch self {
            case .microphonePermission:
                "Allow Microphone access in System Settings, or turn off Microphone and start again."
            case .cameraPermission:
                "Allow Camera access in System Settings, or turn off Camera and start again."
            }
        }
    }
}
