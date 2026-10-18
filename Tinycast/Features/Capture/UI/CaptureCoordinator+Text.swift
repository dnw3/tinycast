import Foundation

extension CaptureCoordinator {
    func prepareTextHighlight() {
        guard let editor, !editor.busy else { return }
        editor.finishEditing()
        editor.selectTool(.highlighter)
        if editor.textHighlight?.revision == editor.document.revision {
            editor.snapsToText = true
            return
        }
        run { [weak self, weak editor] in
            guard let self, let editor, self.editor === editor else { return }
            editor.busy = true
            editor.notice = String(localized: "Finding text lines…")
            defer { editor.busy = false }
            let document = editor.document, source = editor.source
            let directory = source.directory.appendingPathComponent("highlight-\(UUID())")
            defer { try? FileManager.default.removeItem(at: directory) }
            await self.core.pauseClipboardRecognition()
            defer { self.core.resumeClipboardRecognition() }
            let input = try await CaptureWork.run {
                try CaptureTextInput.prepare(document: document, source: source, at: directory)
            }
            let result = try await TextRecognitionWorker.recognize(at: input)
            try Task.checkCancellation()
            guard self.editor === editor, result.requestID == document.id,
                result.revision == editor.document.revision
            else { return }
            let highlight = CaptureTextHighlight(document: document, lines: result.boxes.map(\.rect))
            editor.textHighlight = highlight.lines.isEmpty ? nil : highlight
            editor.snapsToText = !highlight.lines.isEmpty
            editor.notice =
                highlight.lines.isEmpty
                ? String(localized: "No text found. Freehand highlighting is still available.")
                : result.truncated
                    ? String(localized: "Some text was not recognized. Select a smaller region to continue.")
                    : String(localized: "Drag across text to highlight one or more lines.")
        }
    }

    func suggestRedactions(_ policy: CaptureRedactionPolicy) {
        run { [weak self] in
            guard let self, let editor = self.editor else { return }
            editor.finishEditing()
            editor.busy = true
            editor.notice = String(localized: "Finding areas to cover…")
            editor.redactionCandidates = []
            defer { editor.busy = false }
            let document = editor.document, source = editor.source
            let directory = source.directory.appendingPathComponent("redaction-\(UUID())")
            defer { try? FileManager.default.removeItem(at: directory) }
            await self.core.pauseClipboardRecognition()
            defer { self.core.resumeClipboardRecognition() }
            let input = try await CaptureWork.run {
                try CaptureTextInput.prepare(
                    document: document, source: source, at: directory, content: policy.content)
            }
            let result = try await TextRecognitionWorker.recognize(at: input)
            try Task.checkCancellation()
            let candidates = try await CaptureWork.run {
                policy.candidates(in: result.boxes.map { ($0.text, $0.rect) }, bounds: document.outputBounds)
            }
            guard self.editor === editor, result.requestID == document.id,
                result.revision == editor.document.revision
            else { return }
            editor.redactionCandidates = candidates
            editor.redactionIndex = 0
            editor.imageAdjustments = false
            editor.codes = []
            editor.tool = .select
            editor.selected = nil
            self.workspace?.selectionOptions = false
            editor.notice =
                candidates.isEmpty
                ? String(localized: "No matching areas found. You can still cover areas manually.")
                : result.truncated
                    ? String(
                        localized: "Only part of the image was checked. Review the remaining areas manually.")
                    : nil
        }
    }

    func scanCodes() {
        run { [weak self] in
            guard let self, let editor = self.editor else { return }
            editor.finishEditing()
            editor.busy = true
            editor.notice = String(localized: "Scanning QR codes…")
            defer { editor.busy = false }
            let document = editor.document, source = editor.source
            let directory = source.directory.appendingPathComponent("codes-\(UUID())")
            defer { try? FileManager.default.removeItem(at: directory) }
            await self.core.pauseClipboardRecognition()
            defer { self.core.resumeClipboardRecognition() }
            let input = try await CaptureWork.run {
                try CaptureTextInput.prepare(document: document, source: source, at: directory, content: .qr)
            }
            let result = try await TextRecognitionWorker.recognize(at: input)
            try Task.checkCancellation()
            guard self.editor === editor, result.requestID == document.id,
                result.revision == editor.document.revision
            else { return }
            editor.codes = result.boxes.map(\.text)
            editor.codeIndex = 0
            editor.notice =
                result.text.isEmpty
                ? String(localized: "No QR code found. Select the whole code and retry.")
                : result.truncated
                    ? String(
                        localized: "Some codes could not be included. Select a smaller region to continue.")
                    : nil
        }
    }

    func copyCode(_ code: String) {
        Paster.copyPlainText(code)
        core.showMessage(String(localized: "Copied"), tone: .success)
    }

    func recognize(translate: Bool) {
        run { [weak self] in try await self?.recognizeCurrent(translate: translate) }
    }

    func recognizeCurrent(translate: Bool) async throws {
        guard let editor else { return }
        editor.finishEditing()
        editor.busy = true
        editor.notice = String(localized: "Recognizing text…")
        defer { editor.busy = false }
        let document = editor.document, source = editor.source
        let directory = source.directory.appendingPathComponent("ocr-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        await core.pauseClipboardRecognition()
        defer { core.resumeClipboardRecognition() }
        let input = try await CaptureWork.run {
            try CaptureTextInput.prepare(document: document, source: source, at: directory)
        }
        let result = try await TextRecognitionWorker.recognize(at: input)
        try Task.checkCancellation()
        guard self.editor === editor, editor.document.revision == result.revision,
            document.id == result.requestID
        else { return }
        editor.notice =
            result.truncated
            ? String(localized: "Only part of the image was recognized. Select a smaller region to continue.")
            : nil
        if result.text.isEmpty {
            editor.notice = String(localized: "No text found. Try selecting a clearer region.")
        }
        let preview = try await CaptureWork.run {
            try CaptureRenderer.preview(document: document, directory: source.directory, maximum: 240)
        }
        try Task.checkCancellation()
        guard self.editor === editor, editor.document.revision == document.revision else { return }
        clearSelection()
        core.translationCoordinator.open(
            text: result.text, source: .capture(documentID: document.id, revision: document.revision),
            translate: translate, notice: editor.notice, retaining: source, preview: preview)
    }
}
