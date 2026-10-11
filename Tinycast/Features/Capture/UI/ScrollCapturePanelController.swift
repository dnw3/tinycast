import AppKit
import SwiftUI

@MainActor
final class ScrollCapturePanelController {
    private var panel: NSPanel?
    private var border: NSPanel?
    private weak var session: ScrollCaptureSession?

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
        let screens = NSScreen.screens
        let visibleFrames =
            screens.filter { $0.frame == frame }.map(\.visibleFrame)
            + screens.filter { $0.frame != frame }.map(\.visibleFrame)
        guard
            let placement = CaptureControlPlacement.scrolling(
                region: region, row: size, detailsHeight: metrics.scaled(Theme.Size.captureScrollDetails),
                screens: visibleFrames, gap: metrics.spacing.md)
        else { throw Failure.noSpace }
        let panel = Panel(
            contentRect: placement.collapsed,
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.title = String(localized: "Scrolling Capture")
        panel.level = .floating
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        let details = Details()
        let resize: (Bool) -> Void = { [weak panel] expanded in
            guard let panel else { return }
            panel.setFrame(expanded ? placement.expanded : placement.collapsed, display: false)
        }
        session.onPauseChange = { paused in resize(paused || details.shown) }
        self.session = session
        let hosting = NSHostingView(
            rootView: Controls(session: session, details: details, resize: resize)
                .environment(coordinator).environment(\.metrics, metrics))
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

    func focusExisting() -> Bool {
        guard let panel else { return false }
        border?.orderFrontRegardless()
        panel.orderFrontRegardless()
        panel.makeKey()
        return true
    }

    func close() {
        session?.onPauseChange = nil; session = nil
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
        var errorDescription: String? {
            String(localized: "Leave space outside the selected region for the capture controls.")
        }
    }

    @Observable
    fileprivate final class Details {
        var shown = false
    }

    private struct Controls: View {
        let session: ScrollCaptureSession
        let details: Details
        let resize: (Bool) -> Void
        @Environment(CaptureCoordinator.self) private var coordinator

        private var metrics: InterfaceMetrics { coordinator.metrics }
        private var expanded: Bool { session.paused || details.shown }

        var body: some View {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: metrics.spacing.xxs) {
                    Text("\(session.document.size.width) × \(session.document.size.height)")
                        .monospacedDigit().lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, metrics.spacing.md)
                        .accessibilityLabel(String(localized: "Captured size"))
                        .accessibilityValue(
                            "\(session.document.size.width) × \(session.document.size.height) pixels"
                        )
                        .tooltip(session.notice)
                    CaptureIconButton(
                        title: String(localized: "Auto Scroll"), symbol: "arrow.down.to.line",
                        shortcut: "A", selected: session.automatic
                    ) { coordinator.toggleAutomaticScroll() }
                    .keyboardShortcut("a", modifiers: [])
                    CaptureIconButton(
                        title: session.paused ? String(localized: "Continue") : String(localized: "Pause"),
                        symbol: session.paused ? "play.fill" : "pause.fill", shortcut: "Space"
                    ) {
                        coordinator.toggleScrollPause()
                    }.keyboardShortcut(.space, modifiers: [])
                    CaptureIconButton(
                        title: String(localized: "Finish Scrolling"), symbol: "checkmark", shortcut: "Return",
                        selected: true
                    ) { coordinator.finishScroll() }
                    .keyboardShortcut(.return, modifiers: [])
                    CaptureIconButton(
                        title: String(localized: "Finish and Save As…"), symbol: "square.and.arrow.down",
                        shortcut: "⇧⌘S"
                    ) { coordinator.finishScroll(saveAs: true) }
                    .keyboardShortcut("s", modifiers: [.command, .shift])
                    .disabled(session.document.pieces.isEmpty)
                    Menu {
                        Toggle(
                            "Show Preview and Details",
                            isOn: Binding(
                                get: { details.shown },
                                set: { value in
                                    resize(session.paused || value)
                                    details.shown = value
                                }))
                        Button("Select Again…") { coordinator.restartScroll() }
                        Button("Cancel Capture") { coordinator.cancelScroll() }
                            .keyboardShortcut(.escape, modifiers: [])
                    } label: {
                        CaptureToolbarGlyph(symbol: "ellipsis")
                    }
                    .menuStyle(CaptureToolbarMenuStyle()).fixedSize()
                    .accessibilityLabel(String(localized: "More Scrolling Actions")).tooltip(
                        String(localized: "More Scrolling Actions"))
                }
                .frame(height: metrics.scaled(Theme.Size.captureScrollBar.height) - metrics.spacing.xs * 2)
                if expanded {
                    HStack(spacing: metrics.spacing.md) {
                        if details.shown, let preview = session.preview {
                            Image(decorative: preview, scale: 1).resizable().scaledToFit()
                                .frame(
                                    width: metrics.scaled(Theme.Size.captureScrollPreview),
                                    height: metrics.scaled(Theme.Size.captureScrollPreview))
                        }
                        VStack(alignment: .leading, spacing: metrics.spacing.xs) {
                            Text(session.notice).lineLimit(2)
                            if details.shown {
                                Text(
                                    session.axis.rawValue.capitalized + " · "
                                        + "\(session.document.size.width) × \(session.document.size.height)"
                                )
                                .monospacedDigit()
                            }
                        }
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(height: metrics.scaled(Theme.Size.captureScrollDetails))
                }
            }
            .font(metrics.typography.bar)
            .padding(metrics.spacing.xs)
            .foregroundStyle(Theme.Colors.textPrimary)
            .background {
                RoundedRectangle(cornerRadius: metrics.radius.row).fill(.clear)
                    .frosted(in: RoundedRectangle(cornerRadius: metrics.radius.row))
            }
        }
    }
}
