import SwiftUI

/// A strategy's colour, the same wherever the strategy is named.
struct ProxyTintDot: View {
    let tint: ProxyStrategy.Tint
    var size: CGFloat = 10

    var body: some View {
        Circle()
            .fill(tint.color)
            .frame(width: size, height: size)
            .frame(width: Theme.Size.settingsRowIcon, height: Theme.Size.settingsRowIcon)
            .accessibilityHidden(true)
    }
}

extension ProxyStrategy.Tint {
    var color: Color {
        switch self {
        case .blue: .blue
        case .cyan: .cyan
        case .purple: .purple
        case .orange: .orange
        case .green: .green
        case .pink: .pink
        }
    }
}
