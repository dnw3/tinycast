import AppKit

enum CaptureFileDelivery {
    case copy, share, upload(CaptureUploadDestination, CaptureUploadCredential)
}

extension CaptureCoordinator {
    func shareImage(delivery: CaptureFileDelivery = .share) {
        guard let editor, !editor.busy else { return }
        expandCapture()
        run { [weak self] in
            guard let self, self.editor === editor else { return }
            editor.finishEditing()
            editor.busy = true
            defer { editor.busy = false }
            let snapshot = editor.document, source = editor.source, repository = self.repository
            let rendered = source.directory.appendingPathComponent("share-\(UUID()).png")
            defer { try? FileManager.default.removeItem(at: rendered) }
            let editable = self.settings.keepsOriginals
            let entry = try await CaptureWork.run {
                try CaptureRenderer.png(document: snapshot, directory: source.directory, to: rendered)
                return try repository.commit(
                    document: snapshot, directory: source.directory,
                    png: rendered, editable: editable, draft: false)
            }
            try await self.deliverFile(entry, via: delivery, from: self.editorWindow.sharingView)
            editor.publishedRevision = snapshot.revision
        }
    }

    func shareVideo(delivery: CaptureFileDelivery = .share) {
        run { [weak self] in
            guard let self, let state = self.video else { return }
            try await self.shareVideoCurrent(state, delivery: delivery)
        }
    }

    func shareVideoCurrent(_ state: CaptureVideoState, delivery: CaptureFileDelivery) async throws {
        guard video === state, !state.busy else { return }
        state.player.pause()
        state.busy = true
        state.progress = 0
        defer { state.busy = false; state.progress = nil }
        let snapshot = try state.edit.validated(duration: state.info.duration), options = state.exportOptions
        let rendered = state.source.directory.appendingPathComponent(
            "share-\(UUID()).\(options.format.rawValue)")
        defer { try? FileManager.default.removeItem(at: rendered) }
        let repository = self.repository, entry: CaptureHistoryEntry
        if options.format == .gif {
            try await CaptureGIFService.render(state.url, edit: snapshot, options: options, to: rendered) {
                value in
                await MainActor.run { state.progress = value }
            }
            entry = try await CaptureWork.run { try repository.commitGIF(rendered) }
        } else {
            try await CaptureVideoService.render(state.url, edit: snapshot, options: options, to: rendered) {
                value in
                await MainActor.run { state.progress = value }
            }
            let info = try await CaptureVideoService.inspect(rendered)
            let preview = try await CaptureVideoService.thumbnail(rendered)
            entry = try await CaptureWork.run {
                try repository.commitVideo(rendered, info: info, preview: preview)
            }
        }
        try await self.deliverFile(entry, via: delivery, from: self.videoWindow.sharingView)
        state.savedEdit = snapshot
    }

    func deliverFile(
        _ entry: CaptureHistoryEntry, via delivery: CaptureFileDelivery, from view: NSView?
    ) async throws {
        let repository = repository, keeping = Set(PasteboardFiles.urls(on: .general)),
            preferences = settings.preferences
        let url = try await CaptureWork.run {
            let url = try repository.transfer(entry, now: Date(), keeping: keeping)
            try repository.prune(
                now: Date(), days: max(1, preferences.retentionDays),
                maximumBytes: max(16, preferences.maximumHistoryMB) * 1_048_576)
            return url
        }
        try Task.checkCancellation()
        switch delivery {
        case .copy:
            try writeCaptureFile(url)
            completionThumbnail.show(entry, coordinator: self)
        case .share:
            guard let view else { throw CaptureShareController.Failure.windowUnavailable }
            sharing.show(url, from: view) { [weak self] error in if let error { self?.report(error) } }
        case .upload(let destination, let credential):
            try await uploadFile(url, destination: destination, credential: credential)
        }
    }

    func uploadCapture(video: Bool = false) {
        do {
            guard let destination = settings.uploadDestination else { showUploadSettings(); return }
            let delivery = CaptureFileDelivery.upload(
                destination, try settings.uploadCredential(for: destination))
            if video { shareVideo(delivery: delivery) } else { shareImage(delivery: delivery) }
        } catch { report(error) }
    }

    func showUploadSettings() {
        if workspace != nil { expandCapture() }
        core.settingsCoordinator.showSettings(tab: .capture)
    }

    private func uploadFile(
        _ file: URL, destination: CaptureUploadDestination, credential: CaptureUploadCredential
    ) async throws {
        let message = String(localized: "Uploading to \(destination.title)…")
        guard editor != nil || video != nil else {
            core.showProgress(message) { [weak self] in self?.cancelWork() }
            do {
                try await transferUpload(file, destination: destination, credential: credential)
            } catch is CancellationError {
                core.hideProgress()
                throw CancellationError()
            }
            return
        }
        editor?.notice = message
        video?.notice = message
        try await transferUpload(file, destination: destination, credential: credential)
    }

    private func transferUpload(
        _ file: URL, destination: CaptureUploadDestination, credential: CaptureUploadCredential
    ) async throws {
        let prepared: CaptureUploadService.Prepared
        if destination.kind == .drive {
            let token = try await CaptureDriveService.refresh(
                destination: destination, credential: credential)
            prepared = try await CaptureDriveService.prepare(file: file, token: token, id: UUID())
        } else {
            prepared = try await CaptureWork.run {
                try CaptureUploadService.prepare(
                    file: file, destination: destination, credential: credential,
                    scratch: file.deletingLastPathComponent(), id: UUID(), date: Date())
            }
        }
        defer { if prepared.temporary { try? FileManager.default.removeItem(at: prepared.file) } }
        let (values, continuation) = AsyncStream<Double>.makeStream(bufferingPolicy: .bufferingNewest(1))
        defer { continuation.finish() }
        let transport = CaptureUploadTransport { continuation.yield($0) }
        async let progress: Void = observeUploadProgress(values, state: video?.busy == true ? video : nil)
        let (data, response) = try await transport.upload(prepared.request, file: prepared.file)
        continuation.finish()
        await progress
        let link = try CaptureUploadService.result(data, response: response, prepared: prepared)
        try Task.checkCancellation()
        Paster.copyPlainText(link.absoluteString)
        editor?.notice = String(localized: "Uploaded · link copied")
        video?.notice = String(localized: "Uploaded · link copied")
        core.showMessage(String(localized: "Uploaded · link copied"), tone: .success)
    }

    private func observeUploadProgress(_ values: AsyncStream<Double>, state: CaptureVideoState?) async {
        for await value in values {
            guard !Task.isCancelled else { return }
            state?.progress = value
        }
    }
}
