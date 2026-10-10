import SwiftUI

struct CaptureImageAdjustmentControls: View {
    let state: CaptureEditorState
    @Environment(CaptureCoordinator.self) private var coordinator
    @Environment(\.metrics) private var metrics

    private var adjustments: CaptureImageAdjustments { state.document.edit.adjustments ?? .init() }

    var body: some View {
        if state.imageAdjustments {
            CaptureToolFlow(spacing: metrics.spacing.md) {
                CaptureIconButton(title: "Flip Horizontally",
                    symbol: "arrow.left.and.right.righttriangle.left.righttriangle.right") {
                    state.flipImage(.horizontal)
                }
                CaptureIconButton(title: "Flip Vertically", symbol: "arrow.up.and.down.righttriangle.up.righttriangle.down") {
                    state.flipImage(.vertical)
                }
                CaptureIconButton(title: state.backgroundImage?.backgroundMask?.enabled == true
                    ? "Restore Background" : "Remove Background", symbol: "person.crop.rectangle") {
                    coordinator.removeBackground()
                }
                slider("Brightness", key: \.brightness, range: -1...1)
                slider("Contrast", key: \.contrast, range: 0...2)
                slider("Saturation", key: \.saturation, range: 0...2)
                slider("Sharpness", key: \.sharpness, range: 0...1)
                CaptureIconButton(title: "Invert Colors", symbol: "circle.lefthalf.filled", selected: adjustments.inverted) {
                    state.finishEditing()
                    var replacement = adjustments
                    replacement.inverted.toggle()
                    state.adjustImage(replacement)
                }
                CaptureIconButton(title: "Reset Adjustments", symbol: "arrow.counterclockwise") {
                    state.finishEditing()
                    state.adjustImage(.init())
                }.disabled(adjustments.isIdentity)
                CaptureIconButton(title: "Close Adjustments", symbol: "xmark") {
                    state.finishEditing()
                    state.imageAdjustments = false
                }
            }
            .font(metrics.typography.bar)
            .disabled(state.busy)
            .onDisappear { state.undo.end(state.document) }
        }
    }

    private func slider(
        _ title: String, key: WritableKeyPath<CaptureImageAdjustments, Double>, range: ClosedRange<Double>
    ) -> some View {
        VStack(spacing: metrics.spacing.xxs) {
            HStack {
                Text(title)
                Spacer()
                Text(adjustments[keyPath: key], format: .percent.precision(.fractionLength(0)))
                    .foregroundStyle(Theme.Colors.textSecondary).monospacedDigit()
            }
            Slider(value: Binding(get: { adjustments[keyPath: key] }, set: { value in
                var replacement = adjustments
                replacement[keyPath: key] = value
                state.adjustImage(replacement)
            }), in: range, onEditingChanged: { editing in
                if editing {
                    state.finishEditing()
                    state.undo.begin(state.document)
                } else { state.undo.end(state.document) }
            }).accessibilityLabel(title)
        }
        .frame(width: metrics.scaled(Theme.Size.captureAdjustmentWidth))
    }
}
