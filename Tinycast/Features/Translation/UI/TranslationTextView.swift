import AppKit
import Carbon.HIToolbox

final class TranslationTextView: NSTextView {
    var onChange: ((String, Bool) -> Void)?
    var onSubmit: (() -> Void)?

    override func didChangeText() {
        super.didChangeText()
        reportChange()
    }

    override func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {
        super.setMarkedText(string, selectedRange: selectedRange, replacementRange: replacementRange)
        reportChange()
    }

    override func unmarkText() {
        super.unmarkText()
        reportChange()
    }

    override func insertText(_ insertString: Any, replacementRange: NSRange) {
        super.insertText(insertString, replacementRange: replacementRange)
        reportChange()
    }

    private func reportChange() { onChange?(string, hasMarkedText()) }

    override func keyDown(with event: NSEvent) {
        let modifiers = event.modifierFlags.intersection([.command, .shift, .option, .control])
        let isReturn = [kVK_Return, kVK_ANSI_KeypadEnter].contains(Int(event.keyCode))
        guard isReturn, modifiers.isEmpty, !hasMarkedText() else {
            super.keyDown(with: event)
            return
        }
        if !event.isARepeat { onSubmit?() }
    }
}
