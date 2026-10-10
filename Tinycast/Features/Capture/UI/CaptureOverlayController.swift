import AppKit

@MainActor
final class CaptureOverlayController {
    private var panels: [NSPanel] = []
    private weak var active: NSPanel?
    private var suspended = false

    func show(_ coordinator: CaptureCoordinator, workspace: CaptureWorkspaceState) {
        close()
        for screen in NSScreen.screens {
            let panel = Panel(
                contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered, defer: false)
            panel.level = .screenSaver
            panel.colorSpace = .sRGB
            panel.backgroundColor = .clear
            panel.isOpaque = false
            panel.hasShadow = false
            panel.isReleasedWhenClosed = false
            panel.hidesOnDeactivate = false
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.coordinator = coordinator
            let view = CaptureSelectionView(
                frame: CGRect(origin: .zero, size: screen.frame.size), coordinator: coordinator,
                workspace: workspace, screen: screen)
            panel.contentView = view
            panel.acceptsMouseMovedEvents = true
            panels.append(panel)
            panel.orderFrontRegardless()
            if screen.frame == workspace.target.screenFrame {
                active = panel
                panel.makeKey()
                panel.makeFirstResponder(view)
            }
        }
    }

    func suspend() {
        guard !suspended else { return }
        suspended = true
        for panel in panels { panel.orderOut(nil) }
    }

    func resume() {
        guard suspended else { return }
        suspended = false
        for panel in panels { panel.orderFrontRegardless() }
        active?.makeKey()
    }

    func focusExisting() -> Bool {
        guard !panels.isEmpty else { return false }
        if !suspended {
            for panel in panels { panel.orderFrontRegardless() }
            active?.makeKey()
        }
        return true
    }

    func close() {
        for panel in panels { panel.orderOut(nil); panel.contentView = nil }
        panels.removeAll()
        active = nil
        suspended = false
    }

    private final class Panel: NSPanel {
        weak var coordinator: CaptureCoordinator?
        override var canBecomeKey: Bool { true }
        override var canBecomeMain: Bool { false }

        override func performKeyEquivalent(with event: NSEvent) -> Bool {
            if !(firstResponder is NSTextView), let coordinator,
                CaptureWorkspaceKeys.handle(event, coordinator: coordinator)
            { return true }
            return super.performKeyEquivalent(with: event)
        }
    }
}
