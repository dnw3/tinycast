import AppKit

final class CaptureTextEditor: NSTextView {
    var onFinish: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        if !hasMarkedText(),
            event.keyCode == 53 || (event.keyCode == 36 && event.modifierFlags.contains(.command))
        {
            onFinish?(); return
        }
        super.keyDown(with: event)
    }
}
