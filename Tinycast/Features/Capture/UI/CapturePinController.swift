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
    @ObservationIgnored private var panel: NSPanel?

    init(document: CaptureDocument, source: CaptureSource) {
        self.document = document
        self.source = source
    }

    func show(preview: CGImage, coordinator: CaptureCoordinator) {
        let bounds = document.outputBounds
        let scale = min(1, Theme.Size.capturePinMaximum / max(bounds.width, bounds.height))
        let size = CGSize(
            width: max(Theme.Size.capturePinMinimum, bounds.width * scale),
            height: max(Theme.Size.capturePinMinimum, bounds.height * scale))
        let panel = Panel(
            contentRect: CGRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel, .resizable], backing: .buffered, defer: false)
        panel.level = .floating
        panel.title = String(localized: "Pinned Screenshot")
        panel.isFloatingPanel = true
        panel.isMovableByWindowBackground = true
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.acceptsMouseMovedEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.aspectRatio = size
        panel.minSize = CGSize(width: Theme.Size.capturePinMinimum, height: Theme.Size.capturePinMinimum)
        let hosting = PinHostingView(rootView: PinView(preview: preview, pin: self).environment(coordinator))
        hosting.sizingOptions = []
        hosting.frame = CGRect(origin: .zero, size: size)
        hosting.autoresizingMask = [.width, .height]
        hosting.hoverChanged = { [weak self] in self?.hovering = $0 }
        panel.contentView = hosting
        panel.setContentSize(size)
        panel.center()
        panel.orderFrontRegardless()
        self.panel = panel
    }

    func cycleOpacity() {
        opacityValue = opacityValue > 0.25 ? opacityValue - 0.25 : 1
        panel?.alphaValue = opacityValue
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
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .overlay(alignment: .topTrailing) {
                    if pin.hovering || accessibilityFocused {
                        CaptureToolFlow(spacing: metrics.spacing.xxs) {
                            CaptureIconButton(title: String(localized: "Copy"), symbol: "doc.on.doc") {
                                coordinator.copyPin(pin)
                            }
                            CaptureIconButton(
                                title: String(localized: "Save"), symbol: "square.and.arrow.down"
                            ) {
                                coordinator.save(
                                    CaptureEditorState(document: pin.document, source: pin.source))
                            }
                            CaptureIconButton(title: String(localized: "Edit"), symbol: "pencil") {
                                coordinator.editPin(pin)
                            }
                            CaptureIconButton(
                                title: String(localized: "Opacity \(Int(pin.opacityValue * 100))%"),
                                symbol: "circle.lefthalf.filled"
                            ) {
                                pin.cycleOpacity()
                            }
                            CaptureIconButton(title: String(localized: "Close Pin"), symbol: "xmark") {
                                coordinator.closePin(pin)
                            }
                        }
                        .font(metrics.typography.bar)
                        .padding(metrics.spacing.sm)
                        .background(Theme.Colors.panelScrim)
                    }
                }
                .onHover { pin.hovering = $0 }
                .accessibilityElement(children: .contain)
                .accessibilityHidden(false)
                .accessibilityLabel(String(localized: "Pinned screenshot"))
                .accessibilityFocused($accessibilityFocused)
                .accessibilityAction(named: "Copy") { coordinator.copyPin(pin) }
                .accessibilityAction(named: "Save") {
                    coordinator.save(CaptureEditorState(document: pin.document, source: pin.source))
                }
                .accessibilityAction(named: "Edit") { coordinator.editPin(pin) }
                .accessibilityAction(named: "Close") { coordinator.closePin(pin) }
                .environment(\.metrics, metrics)
        }
    }

    private final class Panel: NSPanel {
        override var canBecomeKey: Bool { true }
        override var canBecomeMain: Bool { false }
    }

    private final class PinHostingView<Content: View>: NSHostingView<Content> {
        var hoverChanged: (Bool) -> Void = { _ in }
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
        override func mouseDown(with event: NSEvent) {
            hoverChanged(true)
            super.mouseDown(with: event)
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
            let scale = max(
                Theme.Size.capturePinMinimum / min(old.width, old.height),
                min(factor, Theme.Size.capturePinMaximum * 2 / max(old.width, old.height)))
            window.setFrame(
                CGRect(
                    x: old.minX + point.x * (1 - scale), y: old.minY + point.y * (1 - scale),
                    width: old.width * scale, height: old.height * scale), display: true)
        }
    }
}
