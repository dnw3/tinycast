import SwiftUI

struct CaptureRedactionReview: View {
    @Bindable var state: CaptureEditorState
    @Environment(\.metrics) private var metrics
    private var included: Int { state.redactionCandidates.filter(\.included).count }

    var body: some View {
        if state.redactionCandidates.indices.contains(state.redactionIndex) {
            VStack(alignment: .leading, spacing: metrics.spacing.xs) {
                Text("Review suggested areas · check the image for missed information")
                    .font(metrics.typography.bar).foregroundStyle(Theme.Colors.textSecondary)
                HStack(spacing: metrics.spacing.sm) {
                    Toggle("Include", isOn: $state.redactionCandidates[state.redactionIndex].included)
                        .toggleStyle(.checkbox)
                    Text(state.redactionCandidates[state.redactionIndex].label).lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text("\(state.redactionIndex + 1)/\(state.redactionCandidates.count)").monospacedDigit()
                    CaptureIconButton(title: String(localized: "Previous Area"), symbol: "chevron.left") {
                        state.redactionIndex =
                            (state.redactionIndex + state.redactionCandidates.count - 1)
                            % state.redactionCandidates.count
                    }
                    CaptureIconButton(title: String(localized: "Next Area"), symbol: "chevron.right") {
                        state.redactionIndex = (state.redactionIndex + 1) % state.redactionCandidates.count
                    }
                    Button("Cover \(included) \(included == 1 ? "Area" : "Areas")") {
                        state.applyRedactions()
                    }
                    .disabled(!state.redactionCandidates.contains(where: \.included))
                    CaptureIconButton(title: String(localized: "Dismiss Suggestions"), symbol: "xmark") {
                        state.redactionCandidates = []
                    }
                }
                .font(metrics.typography.bar)
            }
            .padding(metrics.spacing.sm)
            .background(Theme.Colors.panelScrim, in: RoundedRectangle(cornerRadius: metrics.radius.row))
            .disabled(state.busy)
        }
    }
}
