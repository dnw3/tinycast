import SwiftUI

/// The waiting pill: who is asking and what, with a way back to the card that answers it.
struct AgentWaitingHUDView: View {
    let message: String
    let onView: () -> Void
    let onDismiss: () -> Void
    @State private var hovered = false
    @Environment(\.metrics) private var metrics

    var body: some View {
        HStack(spacing: metrics.spacing.md) {
            Button(action: onDismiss) { mark }
                .buttonStyle(.plain)
                .accessibilityLabel(String(localized: "Dismiss"))
            Text(message)
                .font(metrics.typography.bar)
                .foregroundStyle(Color.primary)
                .lineLimit(1)
                .frame(maxWidth: metrics.size.hudMaxWidth, alignment: .leading)
                .fixedSize()
            Button("View", action: onView)
                .buttonStyle(.modalAction(.primary, fillsWidth: false))
        }
        .padding(.leading, metrics.spacing.xl)
        // The button's capsule sits inside the pill's at the same inset all round.
        .padding([.trailing, .vertical], metrics.spacing.xs)
        .hudCapsule(tint: Theme.Colors.waiting)
        .onHover { isHovered in
            withAnimation(.easeOut(duration: Theme.Duration.hover)) { hovered = isHovered }
        }
    }

    /// The hand turns into the way to wave the pill off, as the progress pill's spinner does.
    private var mark: some View {
        Group {
            if hovered {
                Image(systemName: "xmark")
                    .font(metrics.typography.menuIcon.weight(.semibold))
                    .foregroundStyle(Theme.Colors.textSecondary)
            } else {
                Image(systemName: "hand.raised.fill")
                    .font(metrics.typography.menuIcon)
                    .foregroundStyle(Theme.Colors.waiting)
            }
        }
        .frame(width: metrics.size.menuIcon, height: metrics.size.menuIcon)
        .contentShape(.rect)
        .transition(.opacity)
    }
}
