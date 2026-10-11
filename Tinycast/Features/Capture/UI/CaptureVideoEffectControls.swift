import SwiftUI

struct CaptureVideoEffectControls: View {
    @Bindable var state: CaptureVideoState
    @Environment(\.metrics) private var metrics
    @FocusState private var editingText: Bool

    var body: some View {
        if let effect = state.selectedEffect {
            VStack(alignment: .leading, spacing: metrics.spacing.sm) {
                HStack(spacing: metrics.spacing.md) {
                    Text(effect.kind.rawValue.capitalized)
                    field(String(localized: "From"), value: value(\.start))
                    field(String(localized: "To"), value: value(\.end))
                    if effect.kind != .zoom {
                        TextField(
                            "Color",
                            text: Binding(
                                get: { effect.color.hex },
                                set: { value in
                                    if let color = CaptureColor(hex: value) {
                                        state.changeEffect { $0.color = color }
                                    }
                                })
                        ).textFieldStyle(.roundedBorder)
                            .frame(width: metrics.scaled(Theme.Size.capturePropertyField * 1.5))
                            .accessibilityLabel(String(localized: "Video Effect Color"))
                    }
                    Spacer()
                    CaptureIconButton(title: String(localized: "Remove Video Effect"), symbol: "trash") {
                        state.endEditing()
                        state.change { $0.effects.removeAll { $0.id == effect.id } }
                        state.selectedEffectID = nil
                    }
                    CaptureIconButton(title: String(localized: "Apply Video Effect"), symbol: "checkmark") {
                        state.endEditing(); state.selectedEffectID = nil
                    }
                }
                if effect.kind == .text {
                    TextField(
                        "Video Text",
                        text: Binding(
                            get: { effect.text },
                            set: { value in
                                state.changeEffect { $0.text = value }
                            }), axis: .vertical
                    ).textFieldStyle(.roundedBorder).lineLimit(1...3)
                        .accessibilityLabel(String(localized: "Video Text")).focused($editingText)
                        .onChange(of: editingText) { _, editing in
                            if editing { state.beginEditing() } else { state.endEditing() }
                        }
                }
                DisclosureGroup("Position and Size") {
                    HStack(spacing: metrics.spacing.md) {
                        field(String(localized: "X %"), value: geometry(\.origin.x))
                        field(String(localized: "Y %"), value: geometry(\.origin.y))
                        field(String(localized: "Width %"), value: geometry(\.size.width))
                        field(String(localized: "Height %"), value: geometry(\.size.height))
                    }.padding(.top, metrics.spacing.sm)
                }
            }
        }
    }

    private func field(_ title: String, value: Binding<Double>) -> some View {
        HStack(spacing: metrics.spacing.xs) {
            Text(title)
            TextField(title, value: value, format: .number.precision(.fractionLength(0...3)))
                .textFieldStyle(.roundedBorder).frame(width: metrics.scaled(Theme.Size.capturePropertyField))
                .accessibilityLabel(String(localized: "Video Effect \(title)"))
        }
    }

    private func value(_ key: WritableKeyPath<CaptureVideoEffect, Double>) -> Binding<Double> {
        Binding(
            get: { state.selectedEffect?[keyPath: key] ?? 0 },
            set: { value in
                state.changeEffect { $0[keyPath: key] = value }
            })
    }

    private func geometry(_ key: WritableKeyPath<CGRect, CGFloat>) -> Binding<Double> {
        Binding(
            get: { Double(state.selectedEffect?.rect[keyPath: key] ?? 0) * 100 },
            set: { value in
                state.changeEffect { $0.rect[keyPath: key] = CGFloat(value / 100) }
            })
    }
}
