import SwiftUI

struct CapturePresentationControls: View {
    let state: CaptureEditorState
    @Environment(\.metrics) private var metrics

    private var style: CapturePresentation { state.document.edit.presentation ?? .init() }

    var body: some View {
        if state.presentationControls {
            CaptureToolFlow(spacing: metrics.spacing.md) {
                CapturePresentationPresets(state: state)
                CapturePickerMenu(
                    title: String(localized: "Background"), symbol: "square.fill.on.square",
                    options: CapturePresentation.Background.allCases.map {
                        ($0, Bundle.main.localizedString(forKey: $0.title, value: nil, table: nil))
                    },
                    selection: binding(\.background))
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

        var body: some View {
            HStack(spacing: metrics.spacing.xxs) {
                Circle().fill(Color(red: value.rgba[0], green: value.rgba[1], blue: value.rgba[2]))
                    .frame(
                        width: metrics.scaled(Theme.Size.captureGlyph),
                        height: metrics.scaled(Theme.Size.captureGlyph))
                CaptureHexField(title: title, color: value) { color in
                    finish()
                    if let color { value = color }
                }
            }
        }
    }
}
