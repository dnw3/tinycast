import SwiftUI

struct CaptureColorField: View {
    let state: CaptureEditorState

    var body: some View {
        CaptureHexField(title: String(localized: "Custom Color Hex"), color: state.color) { color in
            if let color {
                state.setColor(color)
                state.notice = nil
            } else {
                state.notice = String(localized: "Enter a six-digit color, such as #2468AC.")
            }
        }
    }
}

/// The one hex entry for capture colors; `commit` gets nil for input that is not a color.
struct CaptureHexField: View {
    let title: String
    let color: CaptureColor?
    let commit: (CaptureColor?) -> Void
    @Environment(\.metrics) private var metrics
    @State private var text = ""

    var body: some View {
        TextField(title, text: $text)
            .frame(width: metrics.scaled(Theme.Size.capturePropertyField * 2))
            .captureField(metrics)
            .accessibilityLabel(title).tooltip(title)
            .onAppear { text = color?.hex ?? "" }
            .onChange(of: color) { _, next in text = next?.hex ?? "" }
            .onSubmit {
                let parsed = CaptureColor(hex: text)
                commit(parsed)
                text = (parsed ?? color)?.hex ?? text
            }
    }
}
