import SwiftUI

struct CapturePresentationControls: View {
    let state: CaptureEditorState
    @Environment(\.metrics) private var metrics

    private var style: CapturePresentation { state.document.edit.presentation ?? .init() }

    var body: some View {
        if state.presentationControls {
            CaptureToolFlow(spacing: metrics.spacing.md) {
                CapturePresentationPresets(state: state)
                Picker("Background", selection: binding(\.background)) {
                    ForEach(CapturePresentation.Background.allCases, id: \.self) {
                        Text(LocalizedStringKey($0.title)).tag($0)
                    }
                }.fixedSize()
                if style.background != .transparent {
                    color(String(localized: "Background Color"), key: \.color)
                    if style.background == .gradient || style.background == .grid {
                        color(String(localized: "Accent Color"), key: \.secondary)
                    }
                }
                slider(String(localized: "Padding"), key: \.padding, range: 0...160)
                slider(String(localized: "Corners"), key: \.radius, range: 0...80)
                slider(String(localized: "Shadow"), key: \.shadow, range: 0...60)
                CaptureIconButton(
                    title: String(localized: "Window Frame"), symbol: "macwindow", selected: style.windowFrame
                ) {
                    state.finishEditing()
                    binding(\.windowFrame).wrappedValue.toggle()
                }
                CaptureIconButton(
                    title: String(localized: "Remove Styling"), symbol: "arrow.counterclockwise"
                ) {
                    state.finishEditing()
                    state.setPresentation(nil)
                    state.presentationControls = false
                }
                CaptureIconButton(title: String(localized: "Close Styling"), symbol: "xmark") {
                    state.finishEditing()
                    state.presentationControls = false
                }
            }
            .font(metrics.typography.bar).disabled(state.busy)
            .onDisappear { state.undo.end(state.document) }
        }
    }

    private func binding<Value>(_ key: WritableKeyPath<CapturePresentation, Value>) -> Binding<Value> {
        Binding(
            get: { style[keyPath: key] },
            set: {
                var replacement = style
                replacement[keyPath: key] = $0
                state.setPresentation(replacement)
            })
    }

    private func color(_ title: String, key: WritableKeyPath<CapturePresentation, CaptureColor>) -> some View
    {
        ColorField(title: title, value: binding(key), finish: state.finishEditing)
    }

    private func slider(
        _ title: String, key: WritableKeyPath<CapturePresentation, Double>, range: ClosedRange<Double>
    ) -> some View {
        VStack(spacing: metrics.spacing.xxs) {
            HStack {
                Text(title)
                Spacer()
                Text("\(Int(style[keyPath: key])) px").monospacedDigit().foregroundStyle(
                    Theme.Colors.textSecondary)
            }
            Slider(
                value: binding(key), in: range, step: 1,
                onEditingChanged: { editing in
                    if editing {
                        state.finishEditing(); state.undo.begin(state.document)
                    } else {
                        state.undo.end(state.document)
                    }
                }
            ).accessibilityLabel(title)
        }.frame(width: metrics.scaled(Theme.Size.captureAdjustmentWidth))
    }

    private struct ColorField: View {
        let title: String
        @Binding var value: CaptureColor
        let finish: () -> Void
        @Environment(\.metrics) private var metrics
        @State private var text = ""

        var body: some View {
            HStack(spacing: metrics.spacing.xxs) {
                Circle().fill(Color(red: value.rgba[0], green: value.rgba[1], blue: value.rgba[2]))
                    .frame(
                        width: metrics.scaled(Theme.Size.captureGlyph),
                        height: metrics.scaled(Theme.Size.captureGlyph))
                TextField(title, text: $text)
                    .frame(width: metrics.scaled(Theme.Size.capturePropertyField * 2))
                    .accessibilityLabel(title).tooltip(title)
                    .onAppear { text = value.hex }
                    .onChange(of: value) { _, next in text = next.hex }
                    .onSubmit {
                        finish()
                        if let color = CaptureColor(hex: text) { value = color }
                        text = value.hex
                    }
            }
        }
    }
}
