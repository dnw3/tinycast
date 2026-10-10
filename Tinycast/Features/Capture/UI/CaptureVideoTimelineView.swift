import SwiftUI

struct CaptureVideoTimelineView: View {
    let state: CaptureVideoState
    @Environment(\.metrics) private var metrics
    @State private var cutStart = 0.0
    @State private var cutEnd = 1.0
    @State private var holdPosition = 0.0
    @State private var holdDuration = 1.0

    var body: some View {
        DisclosureGroup("Cut and Freeze") {
            VStack(alignment: .leading, spacing: metrics.spacing.sm) {
                Text("Times refer to the original recording. Changes outside the trimmed range are kept for later.")
                    .foregroundStyle(Theme.Colors.textSecondary)
                HStack(spacing: metrics.spacing.md) {
                    seconds("Cut From", value: $cutStart)
                    seconds("To", value: $cutEnd)
                    CaptureIconButton(title: "Remove Interval", symbol: "scissors") {
                        state.change { $0.cuts.append(.init(start: cutStart, end: cutEnd)) }
                    }
                    Spacer()
                    seconds("Freeze At", value: $holdPosition)
                    seconds("For", value: $holdDuration)
                    CaptureIconButton(title: "Add Freeze Frame", symbol: "snowflake") {
                        state.change { $0.holds.append(.init(position: holdPosition, duration: holdDuration)) }
                    }
                }
                if !state.edit.cuts.isEmpty || !state.edit.holds.isEmpty {
                    ScrollView {
                        VStack(alignment: .leading, spacing: metrics.spacing.xs) {
                            ForEach(state.edit.cuts.indices, id: \.self) { index in
                                let range = state.edit.cuts[index]
                                row("Cut \(range.start.formatted())–\(range.end.formatted()) s") {
                                    state.change { $0.cuts.remove(at: index) }
                                }
                            }
                            ForEach(state.edit.holds.indices, id: \.self) { index in
                                let hold = state.edit.holds[index]
                                row("Freeze \(hold.position.formatted()) s for \(hold.duration.formatted()) s") {
                                    state.change { $0.holds.remove(at: index) }
                                }
                            }
                        }
                    }.frame(maxHeight: metrics.scaled(100))
                }
            }.padding(.top, metrics.spacing.sm)
        }
    }

    private func seconds(_ title: String, value: Binding<Double>) -> some View {
        HStack(spacing: metrics.spacing.xs) {
            Text(title)
            TextField(title, value: value, format: .number.precision(.fractionLength(0...3)))
                .textFieldStyle(.roundedBorder).frame(width: metrics.scaled(68))
                .accessibilityLabel(title)
        }
    }

    private func row(_ title: String, remove: @escaping () -> Void) -> some View {
        HStack {
            Text(title).monospacedDigit()
            Spacer()
            CaptureIconButton(title: "Remove \(title)", symbol: "xmark", action: remove)
        }
    }
}
