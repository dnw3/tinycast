import SwiftUI

struct CaptureNumberControls: View {
    @Bindable var state: CaptureEditorState
    @Environment(\.metrics) private var metrics

    var body: some View {
        CapturePickerMenu(
            title: String(localized: "Number Format"), symbol: "number",
            options: CaptureNumberFormat.Style.allCases.map {
                ($0, Bundle.main.localizedString(forKey: $0.title, value: nil, table: nil))
            },
            selection: Binding(
                get: { state.numberStyle },
                set: {
                    state.numberStyle = $0; state.updateSelectedStyle()
                }))
        HStack(spacing: metrics.spacing.xxs) {
            Text("Next")
            TextField("Next Number", value: $state.nextNumber, format: .number)
                .frame(width: metrics.scaled(Theme.Size.capturePropertyField))
                .captureField(metrics)
                .onSubmit { state.nextNumber = min(3999, max(1, state.nextNumber)) }
                .accessibilityLabel(String(localized: "Next Number")).tooltip(
                    String(localized: "Start or continue numbering from this value · 1–3999"))
        }.fixedSize()
        CaptureIconButton(
            title: String(localized: "Leader"), symbol: "line.diagonal.arrow", selected: state.numberLeader,
            hint: String(localized: "Drag from the number to the point it identifies")
        ) {
            state.numberLeader.toggle(); state.updateSelectedStyle()
        }
    }
}
