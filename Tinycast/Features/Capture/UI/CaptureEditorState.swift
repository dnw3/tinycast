import Foundation
import Observation

@MainActor
@Observable
final class CaptureEditorState {
    var document: CaptureDocument
    let source: CaptureSource
    var directory: URL { source.directory }
    @ObservationIgnored var finishText: (() -> Void)?
    @ObservationIgnored var cancelEditingWork: (() -> Void)?
    var undo = CaptureUndoHistory()
    var tool: CaptureAnnotation.Tool = .select
    var ink: CaptureAnnotation.Ink = .red
    var color: CaptureColor?
    var pickingColor = false
    var emoji = "🙂"
    var emojiSize = 64.0
    var magnification = 2.0
    var strokeWidth = 4.0
    var rotation = 0.0
    var font: CaptureAnnotation.Font = .system
    var fontSize = 24.0
    var filled = false
    var advancedTools = false
    var imageAdjustments = false
    var presentationControls = false
    var translationReview: CaptureTranslationReviewState?
    var codes: [String] = []
    var codeIndex = 0
    var redactionCandidates: [CaptureRedactionPolicy.Candidate] = []
    var redactionIndex = 0
    var selected: UUID?
    var zoom = 1.0
    var fitRequest = UUID()
    var fitMode: CaptureViewportPolicy.Fit?
    var followsViewport = true
    var busy = false
    var notice: String?
    var publishedRevision: Int?

    init(document: CaptureDocument, source: CaptureSource) {
        self.document = document
        self.source = source
    }

    var needsPreservation: Bool { document.needsPreservation && publishedRevision != document.revision }

    func fit(_ mode: CaptureViewportPolicy.Fit? = nil) {
        fitMode = mode
        followsViewport = true
        fitRequest = UUID()
    }

    func setZoom(_ value: Double) {
        followsViewport = false
        zoom = min(8, max(0.02, value))
    }

    func commit(_ edit: CaptureDocument.Edit) {
        let revision = document.revision
        undo.commit(edit, to: &document)
        if document.revision != revision { clearRecognition() }
    }

    func finishEditing() {
        finishText?()
        undo.end(document)
    }

    func cancelPickingColor() {
        guard pickingColor else { return }
        pickingColor = false
        notice = nil
    }

    func selectTool(_ tool: CaptureAnnotation.Tool) {
        finishEditing()
        cancelPickingColor()
        self.tool = tool
        imageAdjustments = false
        presentationControls = false
        translationReview = nil
        if tool != .select { selected = nil }
        if tool == .blur, ![4, 8, 12].contains(strokeWidth) { strokeWidth = 8 }
    }

    func adjustImage(_ adjustments: CaptureImageAdjustments) {
        guard adjustments.isValid else { return }
        var edit = document.edit
        edit.adjustments = adjustments.isIdentity ? nil : adjustments
        commit(edit)
    }

    func setPresentation(_ presentation: CapturePresentation?) {
        var replacement = document
        replacement.edit.presentation = presentation
        do {
            _ = try replacement.validated()
            commit(replacement.edit)
            fit()
        } catch { notice = "Reduce the padding to keep the image within the export limit." }
    }

    func flipImage(_ axis: CaptureDocument.Axis) {
        guard !busy else { return }
        do {
            reframe(try CaptureReflection.flip(document, axis: axis))
        } catch { notice = error.localizedDescription }
    }
    func fitCanvasToImages() {
        guard !busy else { return }
        do {
            reframe(try CaptureComposition.fit(document))
            fit()
        } catch { notice = error.localizedDescription }
    }
    func reframe(_ replacement: CaptureDocument) {
        finishEditing()
        undo.commit(replacement, to: &document)
        clearRecognition()
        selected = nil
    }
    func undoEdit() { undo.undo(&document); selected = nil; clearRecognition() }
    func redoEdit() { undo.redo(&document); selected = nil; clearRecognition() }

    private func clearRecognition() { codes = []; redactionCandidates = []; translationReview = nil }

    func applyRedactions() {
        var edit = document.edit
        let candidates = redactionCandidates.filter(\.included)
        guard !candidates.isEmpty, edit.annotations.count + candidates.count <= 1000 else {
            notice = "Select fewer areas before applying covers."
            return
        }
        edit.annotations += candidates.map {
            .init(id: UUID(), tool: .cover, points: [$0.rect.origin, .init(x: $0.rect.maxX, y: $0.rect.maxY)])
        }
        commit(edit)
        notice = nil
    }
    func deleteSelection() {
        guard let selected else { return }
        if document.pieces.isEmpty, document.imageLayers.count == 1, selectedImage != nil {
            notice = "Keep at least one image in the composition."
            return
        }
        var edit = document.edit
        edit.annotations.removeAll { $0.id == selected }
        edit.imageLayers?.removeAll { $0.id == selected }
        commit(edit)
        self.selected = nil
    }

    var selectedImage: CaptureImageLayer? { document.imageLayers.first { $0.id == selected } }

    var backgroundImage: CaptureImageLayer? {
        if let selectedImage { return selectedImage }
        guard document.pieces.isEmpty, document.imageLayers.count == 1,
            document.edit.crop == nil, document.edit.annotations.isEmpty,
            document.edit.presentation == nil,
            document.edit.translation == nil,
            document.edit.adjustments?.isIdentity ?? true
        else { return nil }
        return document.imageLayers[0]
    }

    func updateImage(_ replacement: CaptureImageLayer) {
        guard replacement.isValid,
            let index = document.imageLayers.firstIndex(where: { $0.id == replacement.id })
        else { return }
        var edit = document.edit
        edit.imageLayers?[index] = replacement
        commit(edit)
    }

    func moveImageForward(_ forward: Bool) {
        finishEditing()
        guard let selected, let index = document.imageLayers.firstIndex(where: { $0.id == selected }) else { return }
        var edit = document.edit
        let next = min(document.imageLayers.count - 1, max(0, index + (forward ? 1 : -1)))
        edit.imageLayers?.swapAt(index, next)
        commit(edit)
    }

    func updateSelectedStyle() {
        finishEditing()
        guard let selected, let index = document.edit.annotations.firstIndex(where: { $0.id == selected })
        else { return }
        var edit = document.edit
        if edit.annotations[index].tool == .magnifier {
            edit.annotations[index].magnification = magnification
            commit(edit)
            return
        }
        if edit.annotations[index].tool == .emoji {
            edit.annotations[index].text = emoji
            edit.annotations[index].sizeEmoji(emojiSize, in: document.outputBounds)
            emojiSize = edit.annotations[index].fontSize ?? 64
            commit(edit)
            return
        }
        edit.annotations[index].ink = ink
        edit.annotations[index].color = color
        edit.annotations[index].width = strokeWidth
        if (edit.annotations[index].rotation ?? 0) != rotation { edit.annotations[index].rotation = rotation }
        if edit.annotations[index].tool == .text {
            if (edit.annotations[index].font ?? .system) != font { edit.annotations[index].font = font }
            if (edit.annotations[index].fontSize ?? strokeWidth * 6) != fontSize {
                edit.annotations[index].fontSize = fontSize
            }
        }
        if [.rectangle, .ellipse].contains(edit.annotations[index].tool),
            (edit.annotations[index].filled ?? false) != filled { edit.annotations[index].filled = filled }
        commit(edit)
    }
}
