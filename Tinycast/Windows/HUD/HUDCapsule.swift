import SwiftUI

/// Every HUD pill's surface, lit from behind its leading mark in that mark's colour.
struct HUDCapsule: ViewModifier {
    private static let glowOpacity = 0.14
    private static let glowRadius: CGFloat = 150
    private static let rimOpacity = 0.25

    let tint: Color
    /// A hovered pill that takes clicks: the fill lifts and the rim stops fading out.
    let isLit: Bool
    @Environment(\.metrics) private var metrics

    func body(content: Content) -> some View {
        content
            .background { glow }
            // Not glass: with nothing to lens it falls back to an opaque backing and shows.
            .background(isLit ? Theme.Colors.controlHover : Theme.Colors.panelScrim)
            .background(GlassEffectView())
            .clipShape(Capsule())
            .overlay { rim }
    }

    private var glow: some View {
        GeometryReader { proxy in
            Capsule().fill(
                RadialGradient(
                    colors: [tint.opacity(Self.glowOpacity), tint.opacity(0.03), .clear],
                    center: UnitPoint(
                        x: (metrics.spacing.xl + metrics.size.menuIcon / 2) / proxy.size.width,
                        y: 0.5),
                    startRadius: 0, endRadius: Self.glowRadius))
        }
    }

    private var rim: some View {
        Capsule().strokeBorder(
            isLit
                ? AnyShapeStyle(Theme.Colors.border)
                : AnyShapeStyle(
                    LinearGradient(
                        colors: [tint.opacity(Self.rimOpacity), tint.opacity(0.06), .clear],
                        startPoint: .leading, endPoint: .trailing)),
            lineWidth: Theme.Size.hairline)
    }
}

extension View {
    /// The mark that lights it sits `xl` in from the leading edge, as every pill's does.
    func hudCapsule(tint: Color, isLit: Bool = false) -> some View {
        modifier(HUDCapsule(tint: tint, isLit: isLit))
    }
}
