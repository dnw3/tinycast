import Foundation

extension CaptureCoordinator {
    var translationLanguages: [String] { core.translationCoordinator.languages }

    func prepareImageTranslation() {
        guard let editor, !editor.busy else { return }
        expandCapture()
        run { [weak self] in
            guard let self, self.editor === editor else { return }
            editor.finishEditing()
            editor.busy = true
            editor.notice = String(localized: "Finding paragraphs…")
            defer { editor.busy = false }
            var document = editor.document
            document.edit.translation = nil
            let source = editor.source, preferences = self.core.translationCoordinator.store.preferences
            let directory = source.directory.appendingPathComponent("translation-\(UUID())")
            defer { try? FileManager.default.removeItem(at: directory) }
            let blocks: [CaptureTranslation.Block]
            if let existing = editor.document.edit.translation {
                blocks = existing.blocks
            } else {
                await self.core.pauseClipboardRecognition()
                defer { self.core.resumeClipboardRecognition() }
                let snapshot = document
                let input = try await CaptureWork.run {
                    try CaptureTextInput.prepare(document: snapshot, source: source, at: directory)
                }
                let result = try await TextRecognitionWorker.recognize(at: input)
                guard !result.truncated else { throw TranslationBatchRequest.Failure.invalidInput }
                blocks = try await CaptureWork.run {
                    let paragraphs = CaptureTranslation.paragraphs(
                        result.boxes.map { ($0.text, $0.rect) },
                        in: snapshot.contentBounds)
                    guard !paragraphs.isEmpty, paragraphs.count <= 32,
                        paragraphs.reduce(0, { $0 + $1.text.utf8.count })
                            <= TranslationRequest.maximumInputBytes
                    else { throw TranslationBatchRequest.Failure.invalidInput }
                    return try paragraphs.map { paragraph in
                        let color = try CaptureEraseService.color(
                            document: snapshot, directory: source.directory,
                            around: paragraph.rect)
                        return .init(
                            id: UUID(), source: paragraph.text, text: "", rect: paragraph.rect,
                            background: color)
                    }
                }
            }
            let text = blocks.map(\.source).joined(separator: "\n")
            let detected = try await CaptureWork.run {
                TranslationLanguageService.detect(
                    text, preferred: [preferences.firstLanguage, preferences.secondLanguage]) ?? ""
            }
            try Task.checkCancellation()
            guard self.editor === editor, editor.document.revision == document.revision else { return }
            let target =
                editor.document.edit.translation?.target
                ?? TranslationLanguagePolicy.target(
                    source: detected,
                    first: preferences.firstLanguage, second: preferences.secondLanguage, override: "")
            editor.translationReview = .init(
                translation: .init(
                    target: target, blocks: blocks,
                    enabled: editor.document.edit.translation?.enabled ?? true),
                source: detected, engine: preferences.engine, revision: document.revision)
            editor.presentationControls = false
            editor.imageAdjustments = false
            editor.selected = nil
            editor.tool = .select
            editor.notice = nil
        }
    }

    func translateImageParagraphs() {
        run { [weak self] in
            guard let self, let editor = self.editor, let review = editor.translationReview,
                review.revision == editor.document.revision
            else { return }
            editor.busy = true
            review.needsLanguages = false
            editor.notice = String(localized: "Translating paragraphs…")
            defer { editor.busy = false }
            let request = TranslationBatchRequest(
                texts: review.translation.blocks.map(\.source),
                source: review.source, target: review.translation.target)
            do {
                let texts = try await self.core.translationCoordinator.translateImage(
                    request, engine: review.engine)
                try Task.checkCancellation()
                guard self.editor === editor, editor.translationReview === review,
                    review.revision == editor.document.revision
                else { return }
                for index in texts.indices { review.translation.blocks[index].text = texts[index] }
                try await self.applyImageTranslation(editor, review: review)
            } catch {
                review.needsLanguages = (error as? AppleTranslationService.Failure) == .needsLanguages
                throw error
            }
        }
    }

    func applyImageTranslation() {
        run { [weak self] in
            guard let self, let editor = self.editor, let review = editor.translationReview else { return }
            editor.busy = true
            defer { editor.busy = false }
            try await self.applyImageTranslation(editor, review: review)
        }
    }

    private func applyImageTranslation(
        _ editor: CaptureEditorState, review: CaptureTranslationReviewState
    ) async throws {
        let translation = review.translation
        try await CaptureWork.run { try CaptureTranslationRenderer.validate(translation) }
        try Task.checkCancellation()
        guard self.editor === editor, editor.translationReview === review,
            review.revision == editor.document.revision
        else { return }
        var edit = editor.document.edit
        edit.translation = translation
        editor.commit(edit)
        review.revision = editor.document.revision
        editor.translationReview = review
        editor.notice = nil
    }

    func showOriginalText() {
        guard let editor, !editor.busy, var translation = editor.document.edit.translation else { return }
        let review = editor.translationReview
        translation.enabled.toggle()
        var edit = editor.document.edit
        edit.translation = translation
        editor.commit(edit)
        if let review {
            review.translation.enabled = translation.enabled
            review.revision = editor.document.revision
            editor.translationReview = review
        }
    }

    func openTranslationLanguages() { core.translationCoordinator.openLanguageSettings() }
}
