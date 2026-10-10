import SwiftUI

struct CaptureImageLayerControls: View {
    let state: CaptureEditorState
    let image: CaptureImageLayer
    @Environment(CaptureCoordinator.self) private var coordinator
    @Environment(\.metrics) private var metrics

    var body: some View {
        CaptureToolFlow(spacing: metrics.spacing.md) {
            Text("Image").foregroundStyle(Theme.Colors.textSecondary)
            slider("Opacity", key: \.opacity, range: 0...1)
            slider("Rotation", key: \.rotation, range: -180...180)
            CaptureIconButton(title: "Bring Image Forward", symbol: "square.3.layers.3d.top.filled") {
                state.moveImageForward(true)
            }
            CaptureIconButton(title: "Send Image Backward", symbol: "square.3.layers.3d.bottom.filled") {
                state.moveImageForward(false)
            }
            CaptureIconButton(title: image.backgroundMask?.enabled == true ? "Restore Background" : "Remove Background",
                symbol: "person.crop.rectangle", selected: image.backgroundMask?.enabled == true) {
                coordinator.removeBackground()
            }
            CaptureIconButton(title: "Remove Image", symbol: "trash") { state.deleteSelection() }
        }
        .disabled(state.busy)
        .onDisappear { state.undo.end(state.document) }
    }

    private func slider(
        _ title: String, key: WritableKeyPath<CaptureImageLayer, Double>, range: ClosedRange<Double>
    ) -> some View {
        VStack(spacing: metrics.spacing.xxs) {
            HStack {
                Text(title)
                Spacer()
                Text(key == \.opacity ? "\(Int(image.opacity * 100))%" : "\(Int(image.rotation))°")
                    .foregroundStyle(Theme.Colors.textSecondary).monospacedDigit()
            }
            Slider(value: Binding(get: { image[keyPath: key] }, set: { value in
                guard var selected = state.selectedImage else { return }
                selected[keyPath: key] = value
                state.updateImage(selected)
            }), in: range, onEditingChanged: { editing in
                if editing {
                    state.finishEditing(); state.undo.begin(state.document)
                } else { state.undo.end(state.document) }
            }).accessibilityLabel("Image \(title)")
        }
        .frame(width: metrics.scaled(Theme.Size.captureAdjustmentWidth))
    }
}
