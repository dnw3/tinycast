import SwiftUI

/// The volume as used, selected-to-clean and free, on the volume HUD's track recipe.
struct StorageBar: View {

    @Environment(\.metrics) private var metrics
    let total: Int64
    let available: Int64
    let selected: Int64

    private var used: Int64 { max(0, total - available) }

    private func fraction(_ bytes: Int64) -> CGFloat {
        total > 0 ? CGFloat(min(max(bytes, 0), total)) / CGFloat(total) : 0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: metrics.spacing.sm) {
            GeometryReader { geometry in
                let width = geometry.size.width
                let usedWidth = width * fraction(used)
                // Selected bytes are part of used; drawn at its trailing end, where they will free up.
                let selectedWidth = min(usedWidth, width * fraction(selected))
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.Colors.controlSurface)
                    Capsule().fill(Theme.Colors.textTertiary).frame(width: usedWidth)
                    Rectangle()
                        .fill(Theme.Colors.textPrimary)
                        .frame(width: selectedWidth)
                        .offset(x: usedWidth - selectedWidth)
                }
                .clipShape(Capsule())
            }
            .frame(height: metrics.size.storageBarHeight)
            HStack(spacing: metrics.spacing.lg) {
                legend(String(localized: "Used"), used, Theme.Colors.textTertiary)
                legend(String(localized: "Selected"), selected, Theme.Colors.textPrimary)
                Spacer(minLength: 0)
                legend(String(localized: "Available"), available, Theme.Colors.controlSurface)
            }
        }
        .animation(.easeOut(duration: Theme.Duration.exit), value: selected)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(String(localized: "Storage"))
        .accessibilityValue(
            String(
                localized: """
                    \(CleanupCoordinator.format(used)) used, \(CleanupCoordinator.format(available)) available, \
                    \(CleanupCoordinator.format(selected)) selected
                    """))
    }

    private func legend(_ title: String, _ bytes: Int64, _ color: Color) -> some View {
        HStack(spacing: metrics.spacing.xs) {
            Circle().fill(color).frame(width: metrics.size.colorDot, height: metrics.size.colorDot)
            Text(title).foregroundStyle(.secondary)
            Text(CleanupCoordinator.format(bytes)).monospacedDigit()
        }
        .font(metrics.typography.keyCap)
    }
}
