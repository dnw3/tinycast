import AppKit
import SwiftUI

@MainActor
final class CaptureCountdownController {
    private var panel: NSPanel?

    func show(_ coordinator: CaptureCoordinator, frame: CGRect) {
        close()
        let metrics = coordinator.metrics
        let size = CGSize(width: metrics.scaled(Theme.Size.captureCountdown.width),
            height: metrics.scaled(Theme.Size.captureCountdown.height))
        let panel = Panel(contentRect: CGRect(x: frame.midX - size.width / 2,
            y: frame.maxY - size.height - metrics.spacing.xxl, width: size.width, height: size.height),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.coordinator = coordinator
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        let hosting = NSHostingView(rootView: Countdown().environment(coordinator).environment(\.metrics, metrics))
        hosting.sizingOptions = []
        panel.contentView = hosting
        panel.setContentSize(size)
        panel.orderFrontRegardless()
        self.panel = panel
    }

    func close() {
        panel?.orderOut(nil)
        panel?.contentView = nil
        panel = nil
    }

    private final class Panel: NSPanel {
        weak var coordinator: CaptureCoordinator?
        override var canBecomeKey: Bool { true }
        override var canBecomeMain: Bool { false }
        override func keyDown(with event: NSEvent) {
            if event.keyCode == 53 { coordinator?.cancelWork() } else { super.keyDown(with: event) }
        }
    }

    private struct Countdown: View {
        @Environment(CaptureCoordinator.self) private var coordinator
        @Environment(\.metrics) private var metrics

        var body: some View {
            HStack(spacing: metrics.spacing.md) {
                SymbolImage(name: "timer", size: metrics.scaled(Theme.Size.captureGlyph))
                Text("Capturing in \(coordinator.countdown ?? 0)…").monospacedDigit()
                Spacer()
                CaptureIconButton(title: "Cancel Delayed Capture", symbol: "xmark") { coordinator.cancelWork() }
            }
            .font(metrics.typography.bar).padding(.horizontal, metrics.spacing.lg)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.Colors.panelScrim).background(GlassEffectView())
            .clipShape(RoundedRectangle(cornerRadius: metrics.radius.row))
        }
    }
}
