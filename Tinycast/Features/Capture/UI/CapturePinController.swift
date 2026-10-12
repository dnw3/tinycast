import AppKit
import Observation
import SwiftUI

@MainActor
@Observable
final class CapturePinController: Identifiable {
    let id = UUID()
    let document: CaptureDocument
    let source: CaptureSource
    private var hovering = false
    private var opacityValue = 1.0
    private var zoom = 1.0
    private var initialSize = CGSize.zero
    var windowID: CGWindowID? { panel.map { CGWindowID($0.windowNumber) } }
    @ObservationIgnored private var panel: NSPanel?

    init(document: CaptureDocument, source: CaptureSource) {
        self.document = document
        self.source = source
    }

    func show(preview: CGImage, coordinator: CaptureCoordinator) {
        let bounds = document.outputBounds
        let size = CapturePinGeometry.fitted(bounds.size, maximum: Theme.Size.capturePinMaximum)
        initialSize = size
        let panel = Panel(
            contentRect: CGRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel, .resizable], backing: .buffered, defer: false)
        panel.level = .floating
        panel.title = String(localized: "Pinned Screenshot")
        panel.isFloatingPanel = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isMovableByWindowBackground = true
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.acceptsMouseMovedEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.aspectRatio = size
        let minimumScale = min(1, Theme.Size.capturePinMinimum / max(size.width, size.height))
        panel.minSize = CGSize(width: size.width * minimumScale, height: size.height * minimumScale)
        let hosting = PinHostingView(rootView: PinView(preview: preview, pin: self).environment(coordinator))
        hosting.sizingOptions = []
        hosting.frame = CGRect(origin: .zero, size: size)
        hosting.autoresizingMask = [.width, .height]
        hosting.hoverChanged = { [weak self] in self?.hovering = $0 }
        hosting.resized = { [weak self] width in
            guard let self else { return }
            self.zoom = width / self.initialSize.width
        }
        panel.handleKey = { [weak self, weak coordinator] event in
            guard let self, let coordinator else { return false }
            let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
                .subtracting([.capsLock, .numericPad, .function])
            if event.keyCode == 53 && modifiers.isEmpty {
                coordinator.closePin(self)
                return true
            }
            guard modifiers == .command || modifiers == [.command, .shift] else { return false }
            switch event.charactersIgnoringModifiers?.lowercased() {
            case "c" where modifiers == .command: coordinator.copyPin(self)
            case "s":
                let state = CaptureEditorState(document: self.document, source: self.source)
                if modifiers.contains(.shift) { coordinator.saveAs(state) } else { coordinator.save(state) }
            case "w" where modifiers == .command: coordinator.closePin(self)
            case "0" where modifiers == .command: self.resetZoom()
            default: return false
            }
            return true
        }
        panel.contentView = hosting
        panel.setContentSize(size)
        panel.center()
        let offset = CGFloat(max(0, coordinator.pins.count - 1)) * 24
        panel.setFrameOrigin(CGPoint(x: panel.frame.minX + offset, y: panel.frame.minY - offset))
        panel.orderFrontRegardless()
        self.panel = panel
    }

    func cycleOpacity() {
        opacityValue = opacityValue > 0.25 ? opacityValue - 0.25 : 1
    }
    func resetZoom() {
        guard let panel else { return }
        let frame = panel.frame
        panel.setFrame(CGRect(x: frame.midX - initialSize.width / 2,
            y: frame.midY - initialSize.height / 2, width: initialSize.width, height: initialSize.height),
            display: true)
        zoom = 1
    }

    func close() { panel?.orderOut(nil); panel?.contentView = nil; panel = nil }

    private struct PinView: View {
        let preview: CGImage
        let pin: CapturePinController
        @Environment(CaptureCoordinator.self) private var coordinator
        @AccessibilityFocusState private var accessibilityFocused: Bool

        private var metrics: InterfaceMetrics { coordinator.metrics }

        var body: some View {
            Image(decorative: preview, scale: 1).resizable().scaledToFit()
                .opacity(pin.opacityValue)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .overlay { PinDragHandle() }
                .contextMenu { actions }
                .overlay(alignment: .topTrailing) {
                    if pin.hovering || accessibilityFocused {
                        HStack(spacing: metrics.spacing.xxs) {
                            Menu {
                                actions
                            } label: {
                                CaptureToolbarGlyph(symbol: "ellipsis")
                            }
                            .menuStyle(CaptureToolbarMenuStyle())
                            .accessibilityLabel(Text("More Actions")).tooltip(String(localized: "More Actions"))
                            CaptureIconButton(title: String(localized: "Close Pin"), symbol: "xmark") {
                                coordinator.closePin(pin)
                            }
                        }
                        .padding(metrics.spacing.xxs)
                        .background {
                            RoundedRectangle(cornerRadius: metrics.radius.barControl).fill(.clear)
                                .frosted(in: RoundedRectangle(cornerRadius: metrics.radius.barControl))
                        }
                        .padding(metrics.spacing.xxs)
                    }
                }
                .overlay(alignment: .bottomLeading) {
                    if pin.hovering || accessibilityFocused {
                        Button(action: pin.resetZoom) {
                            Text(pin.zoom, format: .percent.precision(.fractionLength(0)))
                                .monospacedDigit().font(metrics.typography.bar)
                        }
                        .buttonStyle(.plain)
                        .frame(minWidth: metrics.scaled(Theme.Size.captureTool),
                            minHeight: metrics.scaled(Theme.Size.captureTool))
                        .tooltip(String(localized: "Reset Zoom"))
                        .accessibilityLabel(Text("Reset Zoom"))
                        .padding(metrics.spacing.xxs)
                        .background {
                            RoundedRectangle(cornerRadius: metrics.radius.barControl).fill(.clear)
                                .frosted(in: RoundedRectangle(cornerRadius: metrics.radius.barControl))
                        }
                        .padding(metrics.spacing.xxs)
                    }
                }
                .foregroundStyle(Theme.Colors.textPrimary)
                .onHover { pin.hovering = $0 }
                .accessibilityElement(children: .contain)
                .accessibilityHidden(false)
                .accessibilityLabel(String(localized: "Pinned screenshot"))
                .accessibilityFocused($accessibilityFocused)
                .accessibilityAction(named: "Copy") { coordinator.copyPin(pin) }
                .accessibilityAction(named: "Save") {
                    coordinator.saveAs(CaptureEditorState(document: pin.document, source: pin.source))
                }
                .accessibilityAction(named: "Edit") { coordinator.editPin(pin) }
                .accessibilityAction(named: "Close") { coordinator.closePin(pin) }
                .environment(\.metrics, metrics)
        }

        private var snapshot: CaptureEditorState {
            CaptureEditorState(document: pin.document, source: pin.source)
        }

        @ViewBuilder private var actions: some View {
            Button("Copy") { coordinator.copyPin(pin) }.keyboardShortcut("c", modifiers: .command)
            Button("Save As…") { coordinator.saveAs(snapshot) }
                .keyboardShortcut("s", modifiers: [.command, .shift])
            Button("Quick Save") { coordinator.save(snapshot) }.keyboardShortcut("s", modifiers: .command)
            Button("Show Quick Save Folder") { coordinator.revealQuickSaveFolder() }
            Divider()
            Button("Edit") { coordinator.editPin(pin) }
            Button("Reset Zoom", action: pin.resetZoom).keyboardShortcut("0", modifiers: .command)
            Button(String(localized: "Opacity \(Int(pin.opacityValue * 100))%"), action: pin.cycleOpacity)
            Divider()
            Button("Close Pin") { coordinator.closePin(pin) }.keyboardShortcut("w", modifiers: .command)
        }
    }

    private struct PinDragHandle: NSViewRepresentable {
        func makeNSView(context: Context) -> NSView { DragView() }
        func updateNSView(_ nsView: NSView, context: Context) {}

        private final class DragView: NSView {
            override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
            override func resetCursorRects() { addCursorRect(bounds, cursor: .openHand) }
            override func mouseDown(with event: NSEvent) {
                window?.makeKey()
                window?.performDrag(with: event)
            }
        }
    }

    private final class Panel: NSPanel {
        var handleKey: (NSEvent) -> Bool = { _ in false }
        override func performKeyEquivalent(with event: NSEvent) -> Bool {
            handleKey(event) || super.performKeyEquivalent(with: event)
        }
        override func keyDown(with event: NSEvent) {
            if !handleKey(event) { super.keyDown(with: event) }
        }
        override var canBecomeKey: Bool { true }
        override var canBecomeMain: Bool { false }
    }

    private final class PinHostingView<Content: View>: NSHostingView<Content> {
        var hoverChanged: (Bool) -> Void = { _ in }
        var resized: (CGFloat) -> Void = { _ in }
        private var hoverTracking: NSTrackingArea?

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            if let hoverTracking { removeTrackingArea(hoverTracking) }
            let tracking = NSTrackingArea(
                rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                owner: self, userInfo: nil)
            addTrackingArea(tracking)
            hoverTracking = tracking
        }

        override func mouseEntered(with event: NSEvent) { hoverChanged(true) }
        override func mouseExited(with event: NSEvent) { hoverChanged(false) }
        override func setFrameSize(_ newSize: NSSize) {
            super.setFrameSize(newSize)
            resized(newSize.width)
        }

        override func scrollWheel(with event: NSEvent) {
            resize(factor: exp(-event.scrollingDeltaY * 0.01), point: event.locationInWindow)
        }
        override func magnify(with event: NSEvent) {
            resize(factor: 1 + event.magnification, point: event.locationInWindow)
        }
        private func resize(factor: CGFloat, point: CGPoint) {
            guard let window else { return }
            let old = window.frame
            window.setFrame(CapturePinGeometry.resized(old, factor: factor, anchor: point,
                minimum: Theme.Size.capturePinMinimum, maximum: Theme.Size.capturePinMaximum * 2), display: true)
        }
    }
}
