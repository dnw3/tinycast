import AppKit
import SwiftUI

@MainActor
final class CaptureVideoController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private let activation: ActivationPolicy
    private weak var coordinator: CaptureCoordinator?

    init(activation: ActivationPolicy) { self.activation = activation }

    func show(_ coordinator: CaptureCoordinator) {
        self.coordinator = coordinator
        if focusExisting() { return }
        let metrics = coordinator.metrics
        let size = CGSize(
            width: metrics.scaled(Theme.Size.captureEditor.width),
            height: metrics.scaled(Theme.Size.captureEditor.height))
        let window = NSWindow(
            contentRect: CGRect(origin: .zero, size: size),
            styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = String(localized: "Recording")
        window.isReleasedWhenClosed = false
        window.isRestorable = false
        window.titlebarAppearsTransparent = true
        window.contentMinSize = Theme.Size.captureEditorMinimum
        window.delegate = self
        let hosting = NSHostingController(
            rootView: CaptureVideoView()
                .environment(coordinator).environment(\.metrics, metrics))
        hosting.sizingOptions = []
        window.contentViewController = hosting
        window.setContentSize(size)
        window.center()
        self.window = window
        activation.windowDidOpen(window)
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    func focusExisting() -> Bool {
        guard let window else { return false }
        window.deminiaturize(nil)
        NSApp.activate()
        (window.attachedSheet ?? window).makeKeyAndOrderFront(nil)
        return true
    }

    func close() {
        guard let window else { return }
        window.delegate = nil
        window.close()
        window.contentViewController = nil
        activation.windowDidClose(window)
        self.window = nil
    }

    func present(_ panel: NSSavePanel) async -> NSApplication.ModalResponse {
        activation.windowDidOpen(panel)
        defer { activation.windowDidClose(panel) }
        NSApp.activate()
        if let window { return await panel.beginSheetModal(for: window) }
        return await panel.begin()
    }

    var sharingView: NSView? { window?.contentView }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        coordinator?.requestClose()
        return false
    }
}
