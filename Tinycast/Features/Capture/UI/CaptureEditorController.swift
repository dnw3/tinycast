import AppKit
import SwiftUI

@MainActor
final class CaptureEditorController: NSObject, NSWindowDelegate {
    private var window: Window?
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
        let window = Window(
            contentRect: CGRect(origin: .zero, size: size),
            styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = String(localized: "Capture")
        window.isReleasedWhenClosed = false
        window.isRestorable = false
        window.titlebarAppearsTransparent = true
        window.contentMinSize = CGSize(
            width: metrics.scaled(Theme.Size.captureEditorMinimum.width),
            height: metrics.scaled(Theme.Size.captureEditorMinimum.height))
        window.delegate = self
        window.coordinator = coordinator
        let hosting = NSHostingController(rootView: CaptureEditorView().environment(coordinator))
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

    private final class Window: NSWindow {
        weak var coordinator: CaptureCoordinator?
        override func performKeyEquivalent(with event: NSEvent) -> Bool {
            if let coordinator, CaptureWorkspaceKeys.handleSave(event, coordinator: coordinator) {
                return true
            }
            guard !(firstResponder is NSTextView), let coordinator, let state = coordinator.editor else {
                return super.performKeyEquivalent(with: event)
            }
            if coordinator.savePanel != nil { return super.performKeyEquivalent(with: event) }
            if state.busy {
                if event.keyCode == 53 { coordinator.cancelWork() }
                return true
            }
            let key = event.charactersIgnoringModifiers?.lowercased()
            if event.modifierFlags.contains(.command) {
                switch key {
                case "c": coordinator.copy(); return true
                case "v": coordinator.addImage(clipboard: true); return true
                case "s":
                    if event.modifierFlags.contains(.shift) {
                        coordinator.saveAs()
                    } else {
                        coordinator.save()
                    }
                    return true
                case "w": coordinator.requestClose(); return true
                case "z":
                    if event.modifierFlags.contains(.shift) { state.redoEdit() } else { state.undoEdit() }
                    return true
                case "0": state.fit(); return true
                case "1": state.setZoom(1); return true
                default: break
                }
            }
            if event.keyCode == 53 {
                if state.pickingColor {
                    state.cancelPickingColor()
                } else if !state.redactionCandidates.isEmpty {
                    state.redactionCandidates = []
                } else if state.imageAdjustments {
                    state.finishEditing()
                    state.imageAdjustments = false
                } else if state.presentationControls {
                    state.finishEditing()
                    state.presentationControls = false
                } else if state.translationReview != nil {
                    state.translationReview = nil
                } else if state.selected != nil {
                    state.selected = nil
                } else if state.tool != .select {
                    state.selectTool(.select)
                } else {
                    coordinator.requestClose()
                }
                return true
            }
            return super.performKeyEquivalent(with: event)
        }
    }
}
