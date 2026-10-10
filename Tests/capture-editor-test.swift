import AppKit

@main
@MainActor
struct CaptureEditorTests {
    static func main() {
        _ = NSApplication.shared
        let window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 400, height: 240),
            styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let editor = CaptureTextEditor(frame: window.contentView!.bounds)
        editor.isRichText = false
        editor.allowsUndo = true
        window.contentView = editor
        window.makeFirstResponder(editor)
        var finishes = 0
        editor.onFinish = { finishes += 1 }
        let insertion = NSRange(location: NSNotFound, length: 0)

        for (characters, code, modifiers) in [
            ("\r", UInt16(36), NSEvent.ModifierFlags.command),
            ("\u{1b}", UInt16(53), NSEvent.ModifierFlags())
        ] {
            editor.string = ""
            editor.setMarkedText("ni", selectedRange: NSRange(location: 2, length: 0), replacementRange: insertion)
            editor.keyDown(with: key(characters, code: code, modifiers: modifiers, window: window))
            precondition(finishes == 0, "a composing shortcut submitted the annotation")
        }
        editor.string = ""
        editor.setMarkedText("nihao", selectedRange: NSRange(location: 5, length: 0), replacementRange: insertion)
        editor.insertText("你好", replacementRange: insertion)
        precondition(!editor.hasMarkedText() && editor.string == "你好")
        editor.insertText(" 👨‍👩‍👧‍👦 e\u{301}", replacementRange: insertion)
        let firstLine = editor.string
        editor.keyDown(with: key("\r", code: 36, window: window))
        precondition(finishes == 0 && editor.string == firstLine + "\n")
        editor.insertText("第二行", replacementRange: insertion)
        let text = editor.string
        editor.keyDown(with: key("\r", code: 36, modifiers: .command, window: window))
        precondition(finishes == 1 && editor.string == text)
        editor.keyDown(with: key("\u{1b}", code: 53, window: window))
        precondition(finishes == 2 && editor.string == text)

        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        editor.setSelectedRange(NSRange(location: 0, length: (text as NSString).length))
        let types = editor.writablePasteboardTypes
        board.declareTypes(types, owner: nil)
        _ = editor.writeSelection(to: board, types: types)
        precondition(board.string(forType: .string) == text)
        editor.breakUndoCoalescing()
        editor.undoManager?.removeAllActions()
        editor.insertText("替换", replacementRange: editor.selectedRange())
        editor.breakUndoCoalescing()
        editor.undoManager?.undo()
        precondition(editor.string == text)
        print("Capture TextKit composition, commit, multiline, Unicode, private copy and undo passed")
    }

    static func key(
        _ text: String, code: UInt16, modifiers: NSEvent.ModifierFlags = [], window: NSWindow
    ) -> NSEvent {
        NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: modifiers, timestamp: 0,
            windowNumber: window.windowNumber, context: nil, characters: text,
            charactersIgnoringModifiers: text, isARepeat: false, keyCode: code)!
    }
}
