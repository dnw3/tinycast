import Foundation

@MainActor
final class CaptureAppendState {
    let editor: CaptureEditorState
    let axis: CaptureDocument.Axis

    init(editor: CaptureEditorState, axis: CaptureDocument.Axis) {
        self.editor = editor
        self.axis = axis
    }
}
