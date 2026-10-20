import Observation
import SwiftUI

/// Whether AI Chat's hidden sidebar has slid out over the transcript; one per window.
@MainActor
@Observable
final class AIChatSidebarPeek {
    /// Reported by the split view: only a collapsed sidebar can slide out.
    var isCollapsed = false
    /// The pinned sidebar's last width, so sliding out and pinning cover the same ground.
    var width = Theme.Size.aiChatSidebarMinimum
    private(set) var isShown = false

    func show() {
        guard isCollapsed, !isShown else { return }
        withAnimation(Self.motion(Theme.Duration.enter)) { isShown = true }
    }

    func hide() {
        guard isShown else { return }
        withAnimation(Self.motion(Theme.Duration.exit)) { isShown = false }
    }

    /// The split view's own sidebar takes its place at once, so nothing slides twice.
    func pin() {
        isShown = false
    }

    private static func motion(_ duration: TimeInterval) -> Animation? {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? nil : .snappy(duration: duration)
    }
}
