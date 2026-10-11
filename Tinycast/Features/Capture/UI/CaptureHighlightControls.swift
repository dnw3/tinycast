import SwiftUI

struct CaptureHighlightControls: View {
    let state: CaptureEditorState
    @Environment(CaptureCoordinator.self) private var coordinator

    var body: some View {
        Menu(String(localized: "Highlight: \(state.snapsToText ? "Text Lines" : "Freehand")")) {
            Button("Freehand") {
                state.finishEditing(); state.snapsToText = false
            }
            Button("Text Lines…") { coordinator.prepareTextHighlight() }
        }
        .fixedSize().focusable(false).accessibilityLabel(String(localized: "Highlight Mode"))
        .tooltip(String(localized: "Highlight freehand, or recognize text and drag across its lines"))
    }
}
