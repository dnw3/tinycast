import Foundation
import Observation

@MainActor
@Observable
final class CaptureEditorState {
    var document: CaptureDocument
    let source: CaptureSource
    var directory: URL { source.directory }
    @ObservationIgnored var finishText: (() -> Void)?
    @ObservationIgnored var changeActiveText: ((CaptureTextChange) -> Bool)?
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
    var textStyle = CaptureTextStyle()
    var font: CaptureAnnotation.Font {
        get { textStyle.font }
        set { textStyle.font = newValue }
    }
    var fontSize: Double {
        get { textStyle.size }
        set { textStyle.size = newValue }
    }
    var arrowStyle: CaptureAnnotation.ArrowStyle = .single
    var reversed = false
    var shapeStyle: CaptureAnnotation.ShapeStyle = .outline
    var cornerRadius = 0.0
    var numberStyle: CaptureNumberFormat.Style = .decimal
    var nextNumber = 1
    var numberLeader = false
    var smoothPen = true
    var snapsToText = false
    var textHighlight: CaptureTextHighlight?
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
        let numbers = document.edit.annotations.filter { $0.tool == .number }
        nextNumber = numbers.last?.numberFormat.map { $0.value + 1 } ?? numbers.count + 1
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
        } catch {
            notice = String(localized: "Reduce the padding to keep the image within the export limit.")
        }
    }

    func flipImage(_ axis: CaptureDocument.Axis) {
        guard !busy else { return }
        do {
            reframe(try CaptureReflection.flip(document, axis: axis))
        } catch {
            notice = Bundle.main.localizedString(forKey: error.localizedDescription, value: nil, table: nil)
        }
    }
    func fitCanvasToImages() {
        guard !busy else { return }
        do {
            reframe(try CaptureComposition.fit(document))
            fit()
        } catch {
            notice = Bundle.main.localizedString(forKey: error.localizedDescription, value: nil, table: nil)
        }
    }
    func reframe(_ replacement: CaptureDocument) {
        finishEditing()
        undo.commit(replacement, to: &document)
        clearRecognition()
        selected = nil
    }
    func undoEdit() {
        let before = document.edit.annotations
        undo.undo(&document)
        let remaining = Set(document.edit.annotations.map(\.id))
        if let removed = before.last(where: { $0.tool == .number && !remaining.contains($0.id) }),
            let value = removed.numberFormat?.value, nextNumber == value + 1
        {
            nextNumber = value
        }
        selected = nil
        clearRecognition()
    }
    func redoEdit() {
        let before = Set(document.edit.annotations.map(\.id))
        undo.redo(&document)
        if let added = document.edit.annotations.last(where: { $0.tool == .number && !before.contains($0.id) }
        ),
            let value = added.numberFormat?.value, nextNumber == value
        {
            nextNumber = value + 1
        }
        selected = nil
        clearRecognition()
    }

    private func clearRecognition() {
        codes = []; redactionCandidates = []; translationReview = nil
        if textHighlight?.advance(to: document) == false {
            textHighlight = nil
            snapsToText = false
        }
    }

    func snappedHighlights(_ draft: CaptureAnnotation) -> [CaptureAnnotation]? {
        guard snapsToText, draft.tool == .highlighter else { return nil }
        guard let textHighlight, textHighlight.revision == document.revision,
            let first = draft.points.first, let last = draft.points.last
        else { return [] }
        return textHighlight.annotations(from: first, to: last, ink: draft.ink, color: draft.color)
    }

    func applyRedactions() {
        var edit = document.edit
        let candidates = redactionCandidates.filter(\.included)
        guard !candidates.isEmpty, edit.annotations.count + candidates.count <= 1000 else {
            notice = String(localized: "Select fewer areas before applying covers.")
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
            notice = String(localized: "Keep at least one image in the composition.")
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
        guard let selected, let index = document.imageLayers.firstIndex(where: { $0.id == selected }) else {
            return
        }
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
        if [.rectangle, .ellipse].contains(edit.annotations[index].tool) {
            edit.annotations[index].shapeStyle = shapeStyle
            edit.annotations[index].cornerRadius = cornerRadius
        }
        if [.arrow, .curvedArrow].contains(edit.annotations[index].tool) {
            edit.annotations[index].arrowStyle = arrowStyle
            edit.annotations[index].reversed = reversed
        }
        if edit.annotations[index].tool == .number {
            let value = edit.annotations[index].numberFormat?.value ?? Int(edit.annotations[index].text) ?? 1
            edit.annotations[index].numberFormat = .init(style: numberStyle, value: min(3999, max(1, value)))
            edit.annotations[index].numberLeader = numberLeader
        }
        if edit.annotations[index].tool == .pen { edit.annotations[index].smoothed = smoothPen }
        commit(edit)
    }

    var currentTextStyle: CaptureTextStyle {
        var style = textStyle
        let rgba = color?.rgba ?? ink.rgba
        style.color = CaptureColor(
            red: UInt8((rgba[0] * 255).rounded()), green: UInt8((rgba[1] * 255).rounded()),
            blue: UInt8((rgba[2] * 255).rounded()))
        return style
    }

    func adoptTextStyle(_ style: CaptureTextStyle) {
        textStyle = style
        if let ink = CaptureAnnotation.Ink.allCases.first(where: {
            UInt8(($0.rgba[0] * 255).rounded()) == style.color.red
                && UInt8(($0.rgba[1] * 255).rounded()) == style.color.green
                && UInt8(($0.rgba[2] * 255).rounded()) == style.color.blue
        }) {
            self.ink = ink
            color = nil
        } else {
            color = style.color
        }
    }

    func setColor(_ color: CaptureColor) {
        self.color = color
        let tool = document.edit.annotations.first { $0.id == selected }?.tool ?? tool
        if tool == .text || changeActiveText != nil {
            changeText(.color(color))
        } else {
            updateSelectedStyle()
        }
    }

    func changeText(_ change: CaptureTextChange) {
        var style = currentTextStyle
        style.apply(change)
        guard style.isValid else { return }
        adoptTextStyle(style)
        if changeActiveText?(change) == true { return }
        guard let selected, let index = document.edit.annotations.firstIndex(where: { $0.id == selected }),
            document.edit.annotations[index].tool == .text
        else { return }
        var edit = document.edit
        var format = edit.annotations[index].effectiveTextFormat
        let text = edit.annotations[index].text
        guard format.apply(change, to: NSRange(location: 0, length: text.utf16.count), in: text) else {
            return
        }
        edit.annotations[index].textFormat = format
        commit(edit)
    }
}
