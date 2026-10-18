import AppKit
import SwiftUI

@MainActor
final class CaptureToolbarCustomizationController: NSObject, NSWindowDelegate {
    private var panel: NSPanel?
    private weak var coordinator: CaptureCoordinator?

    func show(_ coordinator: CaptureCoordinator) {
        if let panel { panel.makeKeyAndOrderFront(nil); return }
        self.coordinator = coordinator
        coordinator.editor?.finishEditing()
        let panel = NSPanel(
            contentRect: CGRect(origin: .zero, size: Theme.Size.captureToolbarCustomization),
            styleMask: [.titled, .closable, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.title = String(localized: "Customize Capture Toolbar")
        CaptureChrome.adopt(panel)
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.isRestorable = false
        panel.level =
            coordinator.workspace == nil
            ? .floating : NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 1)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.delegate = self
        let hosting = NSHostingController(
            rootView: CaptureToolbarCustomizationView().environment(coordinator))
        hosting.sizingOptions = []
        panel.contentViewController = hosting
        panel.setContentSize(Theme.Size.captureToolbarCustomization)
        panel.center()
        if let frame = coordinator.workspace?.target.screenFrame {
            panel.setFrameOrigin(
                CGPoint(x: frame.midX - panel.frame.width / 2, y: frame.midY - panel.frame.height / 2))
        }
        self.panel = panel
        panel.makeKeyAndOrderFront(nil)
    }

    func close() {
        guard let panel else { return }
        panel.delegate = nil
        panel.close()
        panel.contentViewController = nil
        self.panel = nil
    }

    func windowWillClose(_ notification: Notification) {
        panel?.contentViewController = nil
        panel = nil
        _ = coordinator?.overlay.focusExisting()
    }
}
