import AppKit
import Carbon.HIToolbox
import OSLog
import SwiftUI

@MainActor
final class TranslationPanelController: NSObject, NSWindowDelegate {
    private var panel: TranslationPanel?
    private weak var coordinator: TranslationCoordinator?
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.tinycast.app", category: "TranslationWindow")
    var isKey: Bool { panel?.isKeyWindow == true }

    func present(_ coordinator: TranslationCoordinator, metrics: InterfaceMetrics) {
        dismiss()
        self.coordinator = coordinator
        let hosting = NSHostingView(
            rootView: TranslationView(onSize: { [weak self] in self?.resize(to: $0) })
                .environment(coordinator).environment(\.metrics, metrics))
        hosting.sizingOptions = []
        hosting.setFrameSize(metrics.size.translationMiniPanel)
        let panel = TranslationPanel(content: hosting)
        panel.delegate = self
        panel.onClose = { [weak coordinator] in coordinator?.cancel() }
        panel.onCopy = { [weak coordinator] in coordinator?.copy() }
        panel.onDeliver = { [weak coordinator] in coordinator?.deliver() }
        self.panel = panel
        if let visible = NSScreen.underCursor?.visibleFrame {
            panel.setFrame(
                TranslationWindowGeometry.frame(
                    size: panel.frame.size, topRight: CGPoint(x: visible.maxX, y: visible.maxY),
                    visibleFrame: visible, margin: Theme.Size.translationScreenMargin), display: false)
            logger.debug("Present frame=\(String(describing: panel.frame), privacy: .public)")
            logger.debug("Display visibleFrame=\(String(describing: visible), privacy: .public)")
        }
        panel.fadeIn(duration: Theme.Duration.enter) { [weak self] in self?.focus() }
    }

    func focus() {
        guard let panel else { return }
        panel.makeKeyAndOrderFront(nil)
        panel.orderFrontRegardless()
        panel.contentView?.layoutSubtreeIfNeeded()
        if let content = panel.contentView, let editor = editor(in: content) {
            panel.makeFirstResponder(editor)
        }
    }

    func dismiss() {
        guard let closing = panel else { return }
        panel = nil
        coordinator = nil
        closing.delegate = nil
        closing.onClose = nil
        closing.onCopy = nil
        closing.onDeliver = nil
        logger.info("Dismiss translation window")
        closing.fadeOut(duration: Theme.Duration.exit)
    }

    private func resize(to size: CGSize) {
        guard let panel, size.width > 0, size.height > 0,
            let visible = (panel.screen ?? NSScreen.main)?.visibleFrame
        else { return }
        let frame = TranslationWindowGeometry.frame(
            size: CGSize(width: ceil(size.width), height: ceil(size.height)),
            topRight: CGPoint(x: panel.frame.maxX, y: panel.frame.maxY),
            visibleFrame: visible, margin: Theme.Size.translationScreenMargin)
        guard frame != panel.frame else { return }
        if frame.width != panel.frame.width {
            logger.debug("Resize frame=\(String(describing: frame), privacy: .public)")
        }
        panel.setFrame(frame, display: true)
    }

    func windowDidResignKey(_ notification: Notification) {
        guard let panel, notification.object as? NSWindow === panel else { return }
        if let state = coordinator?.state {
            logger.info(
                "Resign key: pinned=\(state.isPinned) delivering=\(state.isDelivering) dismiss=\(state.dismissesOnBlur)"
            )
        }
        coordinator?.windowLostFocus()
    }

    private func editor(in view: NSView) -> TranslationTextView? {
        if let editor = view as? TranslationTextView { return editor }
        for subview in view.subviews {
            if let editor = editor(in: subview) { return editor }
        }
        return nil
    }
}

final class TranslationPanel: NSPanel {
    var onClose: (() -> Void)?
    var onCopy: (() -> Void)?
    var onDeliver: (() -> Void)?

    init(content: NSView) {
        super.init(
            contentRect: NSRect(origin: .zero, size: content.frame.size),
            styleMask: [.borderless, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered, defer: false)
        title = String(localized: "Translation")
        isFloatingPanel = true
        hidesOnDeactivate = false
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isMovableByWindowBackground = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        animationBehavior = .none
        isReleasedWhenClosed = false
        isRestorable = false
        contentView = content
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        handleChord(event) || super.performKeyEquivalent(with: event)
    }

    private func handleChord(_ event: NSEvent) -> Bool {
        guard (firstResponder as? NSTextView)?.hasMarkedText() != true else { return false }
        let modifiers = event.modifierFlags.intersection([.command, .shift, .option, .control])
        if modifiers == .command, [kVK_Return, kVK_ANSI_KeypadEnter].contains(Int(event.keyCode)) {
            if !event.isARepeat { onDeliver?() }
            return true
        }
        if modifiers == [.command, .shift], event.charactersIgnoringModifiers?.lowercased() == "c" {
            if !event.isARepeat { onCopy?() }
            return true
        }
        guard let editor = firstResponder as? NSTextView else { return false }
        let key = event.charactersIgnoringModifiers?.lowercased()
        if modifiers == [.command, .shift], key == "z" {
            editor.undoManager?.redo()
            return true
        }
        guard modifiers == .command else { return false }
        switch key {
        case "a": editor.selectAll(nil)
        case "c": editor.copy(nil)
        case "v": editor.paste(nil)
        case "x": editor.cut(nil)
        case "z": editor.undoManager?.undo()
        default: return false
        }
        return true
    }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown, handleChord(event) { return }
        if event.type == .keyDown, Int(event.keyCode) == kVK_Escape,
            (firstResponder as? NSTextView)?.hasMarkedText() != true
        {
            if !event.isARepeat { onClose?() }
            return
        }
        super.sendEvent(event)
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
