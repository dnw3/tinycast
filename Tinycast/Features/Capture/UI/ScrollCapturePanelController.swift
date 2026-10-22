import AppKit
import SwiftUI

@MainActor
final class ScrollCapturePanelController {
    private var panel: NSPanel?
    private var border: NSPanel?
    /// The result so far, beside the region, so the reader sees it grow without looking away.
    private var thumbnail: NSPanel?
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
        panel.onCancel = { [weak coordinator] in coordinator?.cancelScroll() }
        panel.title = String(localized: "Scrolling Capture")
        panel.level = .floating
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        let options = Options()
        let resize: (Bool) -> Void = { [weak panel] expanded in
            guard let panel else { return }
            panel.setFrame(expanded ? placement.expanded : placement.collapsed, display: false)
        }
        session.onPauseChange = { [weak session] paused in
            resize(paused || session?.hint != nil)
        }
        session.onHintChange = { [weak session] in
            guard let session else { return }
            resize(session.paused || session.hint != nil)
        }
        self.session = session
        let hosting = NSHostingView(
            rootView: Controls(
                session: session, options: options, resize: resize,
                showPreview: { [weak self] shown in self?.thumbnail?.setIsVisible(shown) })
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
        showThumbnail(for: session, region: region, controls: placement.expanded, screens: visibleFrames, metrics: metrics)
    }

    private func showThumbnail(
        for session: ScrollCaptureSession, region: CGRect, controls: CGRect, screens: [CGRect], metrics: InterfaceMetrics
    ) {
        guard
            let frame = CaptureControlPlacement.scrollingPreview(
                region: region, width: metrics.scaled(Theme.Size.captureScrollThumbnail), controls: controls,
                screens: screens, gap: metrics.spacing.md)
        else { return }
        let thumbnail = NSPanel(
            contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        thumbnail.level = .floating
        thumbnail.ignoresMouseEvents = true
        thumbnail.isReleasedWhenClosed = false
        thumbnail.hidesOnDeactivate = false
        thumbnail.isOpaque = false
        thumbnail.backgroundColor = .clear
        thumbnail.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        let hosting = NSHostingView(rootView: LivePreview(session: session).environment(\.metrics, metrics))
        hosting.sizingOptions = []
        thumbnail.contentView = hosting
        thumbnail.orderFrontRegardless()
        self.thumbnail = thumbnail
    }

    func focusExisting() -> Bool {
        guard let panel else { return false }
        border?.orderFrontRegardless()
        thumbnail?.orderFrontRegardless()
        panel.orderFrontRegardless()
        panel.makeKey()
        return true
    }

    func close() {
        session?.onPauseChange = nil; session?.onHintChange = nil; session = nil
        panel?.orderOut(nil); panel?.contentView = nil; panel = nil
        border?.orderOut(nil); border?.contentView = nil; border = nil
        thumbnail?.orderOut(nil); thumbnail?.contentView = nil; thumbnail = nil
    }

    private final class Panel: NSPanel {
        /// Escape on the focused controls; the shortcut in their menu works only while it is open.
        var onCancel: (() -> Void)?

        override var canBecomeKey: Bool { true }
        override var canBecomeMain: Bool { false }

        override func cancelOperation(_ sender: Any?) { onCancel?() }
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
    fileprivate final class Options {
        var preview = true
    }

    /// Fitted across, newest end in view: the bottom while scrolling on, the top while scrolling back.
    private struct LivePreview: View {
        let session: ScrollCaptureSession
        @Environment(\.metrics) private var metrics

        var body: some View {
            GeometryReader { proxy in
                if let preview = session.preview {
                    Image(decorative: preview, scale: 1).resizable()
                        .frame(width: fitted(preview, in: proxy.size).width, height: fitted(preview, in: proxy.size).height)
                        .frame(width: proxy.size.width, height: proxy.size.height, alignment: newest)
                        .clipped()
                }
            }
            .captureCard(metrics)
            .accessibilityElement()
            .accessibilityLabel(String(localized: "Captured so far"))
        }

        private func fitted(_ preview: CGImage, in size: CGSize) -> CGSize {
            let ratio = CGFloat(preview.height) / CGFloat(max(1, preview.width))
            return session.axis == .vertical
                ? CGSize(width: size.width, height: size.width * ratio)
                : CGSize(width: size.height / max(ratio, 0.001), height: size.height)
        }

        private var newest: Alignment {
            switch (session.axis == .vertical, session.growsAtStart) {
            case (true, true): .top
            case (true, false): .bottom
            case (false, true): .leading
            case (false, false): .trailing
            }
        }
    }

    private struct Controls: View {
        let session: ScrollCaptureSession
        let options: Options
        let resize: (Bool) -> Void
        let showPreview: (Bool) -> Void
        @Environment(CaptureCoordinator.self) private var coordinator

        private var metrics: InterfaceMetrics { coordinator.metrics }
        private var expanded: Bool { session.paused }

        var body: some View {
            VStack(spacing: metrics.spacing.xs) {
                bar
                if !expanded, let hint = session.hint {
                    HStack(spacing: metrics.spacing.sm) {
                        Text(hint).lineLimit(2).foregroundStyle(Theme.Colors.textPrimary)
                        if session.lost {
                            Button("Go On from Here") { coordinator.bridgeScroll() }
                                .buttonStyle(.modalAction(.standard, fillsWidth: false))
                                .tooltip(String(localized: "Adds what is on screen now and leaves out what was scrolled past"))
                        }
                    }
                    .captureNotice(metrics)
                }
            }
            .frame(maxHeight: .infinity, alignment: .top)
        }

        private var bar: some View {
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
                        title: session.paused ? String(localized: "Resume") : String(localized: "Pause"),
                        symbol: session.paused ? "play.fill" : "pause.fill", shortcut: "␣"
                    ) {
                        coordinator.toggleScrollPause()
                    }.keyboardShortcut(.space, modifiers: [])
                    CaptureIconButton(
                        title: String(localized: "Finish Scrolling"), symbol: "checkmark", shortcut: "↵",
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
                            "Show Live Preview",
                            isOn: Binding(
                                get: { options.preview },
                                set: { value in
                                    options.preview = value
                                    showPreview(value)
                                }))
                        Button("Record Diagnostic Frames") { coordinator.recordScrollDiagnostics() }
                            .disabled(session.diagnostics != nil)
                        Button("Select Again…") { coordinator.restartScroll() }
                        Button("Cancel Scrolling…") { coordinator.cancelScroll() }
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
                    Text(session.notice).lineLimit(2)
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, metrics.spacing.md)
                        .frame(height: metrics.scaled(Theme.Size.captureScrollDetails))
                }
            }
            .font(metrics.typography.bar)
            .foregroundStyle(Theme.Colors.textPrimary)
            .captureBar(metrics)
        }
    }
}
