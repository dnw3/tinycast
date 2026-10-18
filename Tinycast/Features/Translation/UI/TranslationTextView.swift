import AppKit
import Carbon.HIToolbox

final class TranslationTextView: NSTextView {
    var onChange: ((String, Bool) -> Void)?
    var onSubmit: (() -> Void)?
    var onSelection: ((String) -> Void)?
    var onFocusChange: ((Bool) -> Void)?

    override func becomeFirstResponder() -> Bool {
        let became = super.becomeFirstResponder()
        if became { onFocusChange?(true) }
        return became
    }

    override func resignFirstResponder() -> Bool {
        let resigned = super.resignFirstResponder()
        if resigned { onFocusChange?(false) }
        return resigned
    }

    override func setSelectedRange(_ charRange: NSRange) {
        super.setSelectedRange(charRange)
        if NSMaxRange(charRange) <= (string as NSString).length {
            onSelection?((string as NSString).substring(with: charRange))
        }
    }

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
