import AppKit
import SwiftUI

struct TranslationInputView: NSViewRepresentable {
    let text: String
    let metrics: InterfaceMetrics
    let onChange: (String, Bool) -> Void
    let onSubmit: () -> Void
    var onSelection: ((String) -> Void)?

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        let editor = TranslationTextView(usingTextLayoutManager: true)
        editor.isRichText = false
        editor.allowsUndo = true
        editor.drawsBackground = false
        editor.isVerticallyResizable = true
        editor.isHorizontallyResizable = false
        editor.autoresizingMask = [.width]
        editor.textContainer?.widthTracksTextView = true
        editor.textContainerInset = NSSize(width: metrics.spacing.sm, height: metrics.spacing.md)
        editor.string = text
        editor.setAccessibilityLabel("Source text")
        scroll.documentView = editor
        update(editor)
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let editor = scroll.documentView as? TranslationTextView else { return }
        if editor.string != text, !editor.hasMarkedText() {
            editor.string = text
            editor.undoManager?.removeAllActions()
        }
        update(editor)
    }

    private func update(_ editor: TranslationTextView) {
        editor.onChange = onChange
        editor.onSubmit = onSubmit
        editor.onSelection = onSelection
        editor.font = metrics.typography.bodyNSFont
        editor.textColor = NSColor(Theme.Colors.textPrimary)
        editor.insertionPointColor = NSColor(Theme.Colors.textPrimary)
    }
}
