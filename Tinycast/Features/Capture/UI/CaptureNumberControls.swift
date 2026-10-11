import SwiftUI

struct CaptureNumberControls: View {
    @Bindable var state: CaptureEditorState
    @Environment(\.metrics) private var metrics

    var body: some View {
        Picker(
            "Number Format",
            selection: Binding(
                get: { state.numberStyle },
                set: {
                    state.numberStyle = $0; state.updateSelectedStyle()
                })
        ) {
            ForEach(CaptureNumberFormat.Style.allCases, id: \.self) {
                Text(LocalizedStringKey($0.title)).tag($0)
            }
        }.fixedSize()
        HStack(spacing: metrics.spacing.xxs) {
            Text("Next")
            TextField("Next Number", value: $state.nextNumber, format: .number)
                .frame(width: metrics.scaled(Theme.Size.capturePropertyField))
                .onSubmit { state.nextNumber = min(3999, max(1, state.nextNumber)) }
                .accessibilityLabel(String(localized: "Next Number")).tooltip(
                    String(localized: "Start or continue numbering from this value · 1–3999"))
        }.fixedSize()
        Toggle(
            "Leader",
            isOn: Binding(
                get: { state.numberLeader },
                set: {
                    state.numberLeader = $0; state.updateSelectedStyle()
                })
        ).toggleStyle(.checkbox).tooltip(String(localized: "Drag from the number to the point it identifies"))
    }
}
