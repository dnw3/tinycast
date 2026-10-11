import AppKit

@MainActor
final class CaptureOverlayController {
    private var panels: [NSPanel] = []
    private var pool: [CGDirectDisplayID: Panel] = [:]
    private weak var active: NSPanel?
    private var suspended = false

    func show(_ coordinator: CaptureCoordinator, workspace: CaptureWorkspaceState) {
        close()
        for screen in NSScreen.screens {
            guard let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
            else { continue }
            let panel = pool[id] ?? Panel(
                contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered, defer: false)
            pool[id] = panel
            panel.setFrame(screen.frame, display: false)
            panel.animationBehavior = .none
            panel.level = .screenSaver
            let image = workspace.displays?.snapshot(for: screen.frame)?.preview
                ?? (screen.frame == workspace.target.screenFrame ? workspace.preview : nil)
            panel.colorSpace = screen.colorSpace
            panel.backgroundColor = image == nil ? .clear : .black
            panel.isOpaque = image != nil
            panel.hasShadow = false
            panel.isReleasedWhenClosed = false
            panel.hidesOnDeactivate = false
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.coordinator = coordinator
            let view = CaptureSelectionView(
                frame: CGRect(origin: .zero, size: screen.frame.size), coordinator: coordinator,
                workspace: workspace, screen: screen)
            panel.contentView = CaptureSelectionRootView(
                frame: view.frame, selection: view, image: image, scale: screen.backingScaleFactor)
            panel.acceptsMouseMovedEvents = true
            panels.append(panel)
            view.layoutSubtreeIfNeeded()
            panel.displayIfNeeded()
            panel.orderFrontRegardless()
            panel.resetCursorRects()
            if screen.frame == workspace.target.screenFrame {
                active = panel
                panel.makeKey()
                panel.makeFirstResponder(view)
                view.updatePointer()
            }
        }
        let connected = Set(NSScreen.screens.compactMap {
            $0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
        })
        pool = pool.filter { connected.contains($0.key) }
    }

    func suspend() {
        guard !suspended else { return }
        suspended = true
        for panel in panels { panel.orderOut(nil) }
        NSCursor.arrow.set()
    }

    func resume() {
        guard suspended else { return }
        suspended = false
        for panel in panels { panel.orderFrontRegardless() }
        active?.makeKey()
        ((active?.contentView as? CaptureSelectionRootView)?.selection as? CaptureSelectionView)?.updatePointer()
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
        for panel in panels {
            panel.orderOut(nil)
            panel.makeFirstResponder(nil)
            panel.contentView = nil
        }
        panels.removeAll()
        active = nil
        suspended = false
        NSCursor.arrow.set()
    }

    private final class Panel: NSPanel {
        weak var coordinator: CaptureCoordinator?
        override var canBecomeKey: Bool { true }
        override var canBecomeMain: Bool { false }

        override func performKeyEquivalent(with event: NSEvent) -> Bool {
            if let coordinator, CaptureWorkspaceKeys.handleSave(event, coordinator: coordinator) { return true }
            if !(firstResponder is NSTextView), let coordinator,
                CaptureWorkspaceKeys.handle(event, coordinator: coordinator)
            { return true }
            return super.performKeyEquivalent(with: event)
        }
    }
}
