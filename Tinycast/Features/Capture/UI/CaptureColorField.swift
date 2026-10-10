import SwiftUI

struct CaptureColorField: View {
    let state: CaptureEditorState
    @Environment(\.metrics) private var metrics
    @State private var text = ""

    var body: some View {
        TextField("Color", text: $text)
            .frame(width: metrics.scaled(Theme.Size.capturePropertyField * 2))
            .accessibilityLabel("Custom Color Hex")
            .onAppear { text = state.color?.hex ?? "" }
            .onChange(of: state.color) { _, color in text = color?.hex ?? "" }
            .onSubmit {
                guard let color = CaptureColor(hex: text) else {
                    state.notice = "Enter a six-digit color, such as #2468AC."
                    return
                }
                state.color = color
                state.updateSelectedStyle()
                state.notice = nil
                text = color.hex
            }
    }
}
