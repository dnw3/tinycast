import CoreGraphics

enum TranslationWindowGeometry {
    static func frame(size: CGSize, topRight: CGPoint, visibleFrame: CGRect, margin: CGFloat) -> CGRect {
        let bounds = visibleFrame.insetBy(dx: margin, dy: margin)
        let width = min(size.width, bounds.width)
        let height = min(size.height, bounds.height)
        return CGRect(
            x: min(max(topRight.x - width, bounds.minX), bounds.maxX - width),
            y: min(max(topRight.y - height, bounds.minY), bounds.maxY - height),
            width: width, height: height)
    }
}
