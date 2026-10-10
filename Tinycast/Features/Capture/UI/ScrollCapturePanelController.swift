import AppKit
import SwiftUI

@MainActor
final class ScrollCapturePanelController {
    private var panel: NSPanel?
    private var border: NSPanel?

    func show(_ session: ScrollCaptureSession, coordinator: CaptureCoordinator) throws {
        close()
        let frame = session.target.screenFrame
        let region = CGRect(
            x: frame.minX + session.region.minX,
            y: frame.maxY - session.region.maxY,
            width: session.region.width, height: session.region.height)
        let metrics = coordinator.metrics
        let size = CGSize(
            width: metrics.scaled(Theme.Size.captureScrollBar.width),
            height: metrics.scaled(Theme.Size.captureScrollBar.height))
        guard
            let placement = CaptureControlPlacement.frame(
                region: region, size: size, screens: [frame] + NSScreen.screens.map(\.frame),
                gap: metrics.spacing.md)
        else { throw Failure.noSpace }
        let panel = Panel(
            contentRect: placement,
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .floating
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        let hosting = NSHostingView(rootView: Controls(session: session).environment(coordinator))
        hosting.sizingOptions = []
        hosting.frame = CGRect(origin: .zero, size: size)
        panel.contentView = hosting
        panel.setContentSize(size)
        panel.orderFrontRegardless()
        self.panel = panel
        let border = NSPanel(
            contentRect: region.insetBy(dx: -2, dy: -2), styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false)
        border.level = .floating
        border.ignoresMouseEvents = true
        border.isReleasedWhenClosed = false
        border.hidesOnDeactivate = false
        border.isOpaque = false
        border.backgroundColor = .clear
        border.contentView = BorderView()
        border.orderFrontRegardless()
        self.border = border
    }

    func close() {
        panel?.orderOut(nil); panel?.contentView = nil; panel = nil
        border?.orderOut(nil); border?.contentView = nil; border = nil
    }

    private final class Panel: NSPanel {
        override var canBecomeKey: Bool { true }
        override var canBecomeMain: Bool { false }
    }

    private final class BorderView: NSView {
        override func draw(_ dirtyRect: NSRect) {
            NSColor.controlAccentColor.setStroke()
            let path = NSBezierPath(rect: bounds.insetBy(dx: 1, dy: 1))
            path.lineWidth = Theme.Size.hairline * 2
            path.stroke()
        }
    }

    enum Failure: LocalizedError {
        case noSpace
        var errorDescription: String? { "Leave space outside the selected region for the capture controls." }
    }

    private struct Controls: View {
        let session: ScrollCaptureSession
        @Environment(CaptureCoordinator.self) private var coordinator

        private var metrics: InterfaceMetrics { coordinator.metrics }

        var body: some View {
            VStack(alignment: .leading, spacing: metrics.spacing.md) {
                HStack(spacing: metrics.spacing.md) {
                    Text(
                        "\(session.axis.rawValue.capitalized) · \(session.document.size.width) × \(session.document.size.height)"
                    )
                    .monospacedDigit()
                    Spacer()
                    Button(session.automatic ? "Manual" : "Auto Scroll") {
                        coordinator.toggleAutomaticScroll()
                    }.keyboardShortcut("a", modifiers: []).tooltip("Toggle Automatic Scrolling  A")
                    Button(session.paused ? "Continue" : "Pause") {
                        if session.paused { session.resume() } else { session.pause() }
                    }.keyboardShortcut(.space, modifiers: [])
                    Button("Finish") { coordinator.finishScroll() }.keyboardShortcut(.return, modifiers: [])
                    Button("Cancel") { coordinator.cancelScroll() }.keyboardShortcut(.escape, modifiers: [])
                }
                HStack(spacing: metrics.spacing.md) {
                    if let preview = session.preview {
                        Image(decorative: preview, scale: 1).resizable().scaledToFit()
                            .frame(
                                width: metrics.scaled(Theme.Size.captureScrollPreview),
                                height: metrics.scaled(Theme.Size.captureScrollPreview))
                    }
                    Text(session.notice).foregroundStyle(Theme.Colors.textSecondary)
                    Spacer()
                    if session.paused {
                        Button("Select Again…") { coordinator.restartScroll() }
                    }
                }
            }
            .font(metrics.typography.bar)
            .padding(metrics.spacing.xl)
            .background(Theme.Colors.panelScrim)
            .background(GlassEffectView())
            .clipShape(RoundedRectangle(cornerRadius: metrics.radius.row))
        }
    }
}
