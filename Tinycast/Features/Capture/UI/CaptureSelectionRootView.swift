import AppKit

@MainActor
final class CaptureSelectionRootView: NSView {
    let selection: NSView
    private let preview = CALayer()

    init(frame: CGRect, selection: NSView, image: CGImage?, scale: CGFloat) {
        self.selection = selection
        super.init(frame: frame)
        wantsLayer = true
        layer?.masksToBounds = true
        preview.contentsGravity = .resize
        preview.contentsScale = scale
        preview.actions = ["contents": NSNull(), "bounds": NSNull(), "position": NSNull()]
        preview.frame = bounds
        preview.contents = image
        layer?.addSublayer(preview)
        selection.frame = bounds
        selection.autoresizingMask = [.width, .height]
        selection.wantsLayer = true
        addSubview(selection)
    }

    required init?(coder: NSCoder) { nil }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        preview.frame = bounds
        CATransaction.commit()
    }
}
