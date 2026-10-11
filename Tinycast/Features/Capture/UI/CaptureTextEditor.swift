import AppKit
import CoreText

final class CaptureTextEditor: NSTextView, NSTextViewDelegate {
    var onFinish: (() -> Void)?
    var onStyle: ((CaptureTextStyle) -> Void)?
    private var scale = 1.0
    private var base = CaptureTextStyle()
    private var pending: [CaptureTextChange] = []
    private var pendingLocation: Int?
    private var committingMarkedText = false

    func load(_ text: String, format: CaptureTextFormat, scale: Double) {
        self.scale = scale
        base = format.base
        isRichText = true
        importsGraphics = false
        usesFontPanel = false
        allowsUndo = true
        delegate = self
        textStorage?.setAttributedString(attributed(text, format: format))
        typingAttributes = attributes(base)
    }

    func captured() -> (String, CaptureTextFormat)? {
        let text = String(string.prefix(4000))
        guard let storage = textStorage else { return nil }
        var format = CaptureTextFormat(base: base)
        var runs: [CaptureTextFormat.Run] = []
        var location = 0
        for character in text {
            let length = String(character).utf16.count
            let style = style(storage.attributes(at: location, effectiveRange: nil))
            if let last = runs.last, last.style == style {
                runs[runs.count - 1].length += length
            } else { runs.append(.init(location: location, length: length, style: style)) }
            location += length
        }
        format.runs = runs.filter { $0.style != format.base }
        return format.isValid(for: text) ? (text, format) : nil
    }

    func apply(_ change: CaptureTextChange) {
        if hasMarkedText() {
            pendingLocation = pendingLocation ?? markedRange().location
            pending.append(change)
            return
        }
        var range = selectedRange()
        if range.length == 0 {
            var next = style(typingAttributes)
            next.apply(change)
            guard next.isValid else { return }
            typingAttributes = attributes(next)
            base = next
            onStyle?(next)
            return
        }
        let text = string as NSString
        if case .alignment = change { range = text.paragraphRange(for: range) }
        range = text.rangeOfComposedCharacterSequences(for: range)
        guard let storage = textStorage, shouldChangeText(in: range, replacementString: nil) else { return }
        let replacement = NSMutableAttributedString(attributedString: storage.attributedSubstring(from: range))
        var valid = true
        replacement.enumerateAttributes(in: NSRange(location: 0, length: replacement.length)) { current, part, _ in
            var next = style(current)
            next.apply(change)
            if !next.isValid { valid = false; return }
            replacement.setAttributes(attributes(next), range: part)
        }
        guard valid else { return }
        replace(range, with: replacement)
        didChangeText()
        reportStyle()
    }

    private func replace(_ range: NSRange, with replacement: NSAttributedString) {
        guard let storage = textStorage else { return }
        let previous = storage.attributedSubstring(from: range)
        let selection = selectedRange()
        undoManager?.registerUndo(withTarget: self) { editor in editor.replace(range, with: previous) }
        storage.replaceCharacters(in: range, with: replacement)
        setSelectedRange(selection)
    }

    func textViewDidChangeSelection(_ notification: Notification) { reportStyle() }

    func textDidChange(_ notification: Notification) {
        guard !hasMarkedText(), !committingMarkedText, let start = pendingLocation else { return }
        flushPending(NSRange(location: start, length: max(0, selectedRange().location - start)))
    }

    override func insertText(_ insertString: Any, replacementRange: NSRange) {
        committingMarkedText = hasMarkedText()
        super.insertText(insertString, replacementRange: replacementRange)
        committingMarkedText = false
        if !hasMarkedText(), let start = pendingLocation {
            flushPending(NSRange(location: start, length: max(0, selectedRange().location - start)))
        }
    }

    override func unmarkText() {
        let range = markedRange()
        super.unmarkText()
        if !committingMarkedText, range.location != NSNotFound { flushPending(range) }
    }

    private func flushPending(_ range: NSRange) {
        guard !pending.isEmpty else { return }
        let selection = selectedRange()
        let changes = pending
        pending.removeAll()
        pendingLocation = nil
        setSelectedRange(range)
        for change in changes { apply(change) }
        setSelectedRange(selection)
    }

    override var readablePasteboardTypes: [NSPasteboard.PasteboardType] { [.rtf, .string] }

    override func readSelection(from pboard: NSPasteboard, type: NSPasteboard.PasteboardType) -> Bool {
        guard readablePasteboardTypes.contains(type) else { return false }
        let start = selectedRange().location
        guard super.readSelection(from: pboard, type: type) else { return false }
        if type == .rtf, scale != 1, let storage = textStorage {
            let range = NSRange(location: start, length: max(0, selectedRange().location - start))
            storage.enumerateAttribute(.font, in: range) { value, range, _ in
                if let font = value as? NSFont, let scaled = NSFont(descriptor: font.fontDescriptor,
                    size: font.pointSize * scale)
                { storage.addAttribute(.font, value: scaled, range: range) }
            }
        }
        if let (text, format) = captured() {
            let selection = selectedRange()
            textStorage?.setAttributedString(attributed(text, format: format))
            setSelectedRange(NSRange(location: min(selection.location, text.utf16.count), length: 0))
        }
        return true
    }

    private func reportStyle() {
        let selection = selectedRange()
        if let storage = textStorage, selection.location < storage.length {
            onStyle?(style(storage.attributes(at: selection.location, effectiveRange: nil)))
        } else { onStyle?(style(typingAttributes)) }
    }

    private func attributed(_ text: String, format: CaptureTextFormat) -> NSAttributedString {
        let result = NSMutableAttributedString(string: text, attributes: attributes(format.base))
        for run in format.runs { result.setAttributes(attributes(run.style), range: run.range) }
        return result
    }

    private func attributes(_ style: CaptureTextStyle) -> [NSAttributedString.Key: Any] {
        var scaled = style
        scaled.size *= scale
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = switch style.alignment {
        case .left: .left
        case .center: .center
        case .right: .right
        }
        var result: [NSAttributedString.Key: Any] = [.font: CaptureTextRenderer.font(scaled) as NSFont,
            .foregroundColor: color(style.color), .paragraphStyle: paragraph,
            .underlineStyle: style.underline ? NSUnderlineStyle.single.rawValue : 0,
            .strikethroughStyle: style.strikethrough ? NSUnderlineStyle.single.rawValue : 0,
            NSAttributedString.Key("TinycastFont"): style.font.rawValue]
        if let background = style.background { result[.backgroundColor] = color(background) }
        if let outline = style.outline {
            result[.strokeColor] = color(outline)
            result[.strokeWidth] = -style.outlineWidth
        }
        return result
    }

    private func style(_ attributes: [NSAttributedString.Key: Any]) -> CaptureTextStyle {
        var result = base
        if let font = attributes[.font] as? NSFont {
            let traits = font.fontDescriptor.symbolicTraits
            result.font = CaptureAnnotation.Font(rawValue: attributes[NSAttributedString.Key("TinycastFont")] as? String ?? "")
                ?? (traits.contains(.monoSpace) ? .monospaced : .system)
            result.size = min(768, max(6, font.pointSize / scale))
            result.bold = traits.contains(.bold)
            result.italic = traits.contains(.italic)
        }
        result.color = captureColor(attributes[.foregroundColor]) ?? base.color
        result.underline = (attributes[.underlineStyle] as? Int ?? 0) != 0
        result.strikethrough = (attributes[.strikethroughStyle] as? Int ?? 0) != 0
        result.background = captureColor(attributes[.backgroundColor])
        result.outline = captureColor(attributes[.strokeColor])
        result.outlineWidth = min(20, max(0.1, abs(attributes[.strokeWidth] as? Double ?? 2)))
        if let paragraph = attributes[.paragraphStyle] as? NSParagraphStyle {
            result.alignment = switch paragraph.alignment {
            case .center: .center
            case .right: .right
            default: .left
            }
        }
        return result
    }

    private func captureColor(_ value: Any?) -> CaptureColor? {
        guard let color = (value as? NSColor)?.usingColorSpace(.sRGB) else { return nil }
        return CaptureColor(red: UInt8(min(255, max(0, (color.redComponent * 255).rounded()))),
            green: UInt8(min(255, max(0, (color.greenComponent * 255).rounded()))),
            blue: UInt8(min(255, max(0, (color.blueComponent * 255).rounded()))))
    }

    private func color(_ value: CaptureColor) -> NSColor {
        NSColor(srgbRed: Double(value.red) / 255, green: Double(value.green) / 255,
            blue: Double(value.blue) / 255, alpha: 1)
    }

    override func keyDown(with event: NSEvent) {
        if event.modifierFlags.contains(.command), !event.modifierFlags.contains(.control),
            let key = event.charactersIgnoringModifiers?.lowercased()
        {
            let current = style(typingAttributes)
            if key == "b" { apply(.bold(!current.bold)); return }
            if key == "i" { apply(.italic(!current.italic)); return }
            if key == "u" { apply(.underline(!current.underline)); return }
        }
        if !hasMarkedText(),
            event.keyCode == 53 || (event.keyCode == 36 && event.modifierFlags.contains(.command))
        {
            onFinish?(); return
        }
        super.keyDown(with: event)
    }
}
