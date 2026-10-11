import AppKit

@main
struct CaptureTextEditorTests {
    @MainActor static func main() throws {
        NSApplication.shared.setActivationPolicy(.prohibited)
        let editor = CaptureTextEditor(frame: CGRect(x: 0, y: 0, width: 320, height: 200))
        let window = NSWindow(contentRect: editor.frame, styleMask: [], backing: .buffered, defer: false)
        window.contentView = editor
        window.makeFirstResponder(editor)
        let text = "Hello 中文 👩🏽‍💻\nSecond paragraph"
        let base = CaptureTextStyle()
        editor.load(text, format: CaptureTextFormat(base: base), scale: 2)
        editor.setSelectedRange(NSRange(location: 0, length: 5))
        let undo = editor.undoManager!
        undo.beginUndoGrouping()
        editor.apply(.bold(true))
        undo.endUndoGrouping()
        var captured = editor.captured()!
        precondition(captured.0 == text && captured.1.style(at: 0).bold && !captured.1.style(at: 6).bold)
        precondition(captured.1.style(at: 0).size == 24)
        undo.undo()
        precondition(!editor.captured()!.1.style(at: 0).bold)
        undo.redo()
        precondition(editor.captured()!.1.style(at: 0).bold)
        editor.setSelectedRange((text as NSString).range(of: "中文"))
        editor.apply(.font(.serif))
        editor.apply(.italic(true))
        editor.apply(.background(CaptureColor(red: 255, green: 255, blue: 0)))
        captured = editor.captured()!
        let chinese = (text as NSString).range(of: "中文").location
        precondition(captured.1.style(at: chinese).font == .serif && captured.1.style(at: chinese).italic)
        precondition(captured.1.style(at: chinese).background != nil && captured.1.style(at: 0).background == nil)
        editor.apply(.alignment(.right))
        captured = editor.captured()!
        precondition(captured.1.style(at: 0).alignment == .right)
        let second = (text as NSString).range(of: "Second").location
        precondition(captured.1.style(at: second).alignment == .left)
        let reopened = CaptureTextEditor(frame: editor.frame)
        reopened.load(captured.0, format: captured.1, scale: 0.5)
        precondition(reopened.captured()!.1 == captured.1)
        editor.setSelectedRange(NSRange(location: (editor.string as NSString).length, length: 0))
        editor.apply(.size(48))
        editor.insertText("!", replacementRange: NSRange(location: NSNotFound, length: 0))
        captured = editor.captured()!
        precondition(captured.1.style(at: captured.0.utf16.count - 1).size == 48)
        precondition(captured.1.style(at: 0).size == 24)
        editor.setMarkedText("拼", selectedRange: NSRange(location: 1, length: 0),
            replacementRange: NSRange(location: NSNotFound, length: 0))
        precondition(editor.hasMarkedText())
        editor.apply(.underline(true))
        precondition(editor.hasMarkedText(), "Formatting must preserve composition")
        editor.insertText("拼音", replacementRange: NSRange(location: NSNotFound, length: 0))
        precondition(!editor.hasMarkedText() && editor.string.hasSuffix("拼音"))
        precondition(editor.captured()!.1.style(at: editor.string.utf16.count - 1).underline)
        try paste(editor)
        window.contentView = nil
        print("Native TextKit local styles, undo, scaled re-edit, paragraph alignment, IME and private RTF paste passed")
    }

    @MainActor static func paste(_ editor: CaptureTextEditor) throws {
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        let source = NSAttributedString(string: "Pasted", attributes: [.font: NSFont.boldSystemFont(ofSize: 30),
            .strikethroughStyle: NSUnderlineStyle.single.rawValue, .link: URL(string: "https://example.com/")!])
        let data = try source.data(from: NSRange(location: 0, length: source.length),
            documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf])
        board.setData(data, forType: .rtf)
        editor.load("", format: CaptureTextFormat(base: CaptureTextStyle()), scale: 2)
        precondition(editor.readSelection(from: board, type: .rtf))
        let captured = editor.captured()!
        precondition(captured.0 == "Pasted" && captured.1.style(at: 0).bold && captured.1.style(at: 0).strikethrough)
        precondition(captured.1.style(at: 0).size == 30)
        precondition(editor.textStorage!.attribute(.link, at: 0, effectiveRange: nil) == nil)
    }
}
