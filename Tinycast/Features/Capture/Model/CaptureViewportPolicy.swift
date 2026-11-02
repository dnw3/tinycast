import Foundation

enum CaptureViewportPolicy {
    enum Fit: Sendable { case window, width, height }

    static func preferredFit(image: CGSize) -> Fit {
        guard image.width.isFinite, image.height.isFinite, image.width > 0, image.height > 0 else { return .window }
        if image.height >= image.width * 2 { return .width }
        if image.width >= image.height * 2 { return .height }
        return .window
    }

    static func scale(image: CGSize, viewport: CGSize, fit: Fit) -> CGFloat {
        guard image.width.isFinite, image.height.isFinite,
            viewport.width.isFinite, viewport.height.isFinite,
            image.width > 0, image.height > 0, viewport.width > 0, viewport.height > 0
        else { return 1 }
        switch fit {
        case .window: return min(1, viewport.width / image.width, viewport.height / image.height)
        case .width: return min(1, viewport.width / image.width)
        case .height: return min(1, viewport.height / image.height)
        }
    }

    /// Bounded by area, not by its long side, so a long capture's preview keeps its width.
    static func previewSide(image: CGSize, pixels: CGFloat) -> Int {
        guard image.width.isFinite, image.height.isFinite, image.width > 0, image.height > 0, pixels > 0
        else { return 1 }
        let scale = min(1, (pixels / (image.width * image.height)).squareRoot())
        return max(1, Int(max(image.width, image.height) * scale))
    }

    /// A power of two at or above the screen's scale, so the tiles in view follow the window.
    static func detailLevel(displayScale: CGFloat) -> CGFloat {
        guard displayScale.isFinite, displayScale > 0 else { return 1 }
        var level: CGFloat = 1
        while level / 2 >= displayScale, level > coarsestLevel { level /= 2 }
        return level
    }

    static func needsTiles(previewScale: CGFloat, displayScale: CGFloat) -> Bool {
        previewScale < min(1, displayScale)
    }

    /// Every cell in view, aligned to the output's origin, so none is left to the preview.
    static func tiles(covering visible: CGRect, in output: CGRect, side: Int) -> [CGRect] {
        guard side > 0, [visible.minX, visible.minY, visible.width, visible.height].allSatisfy(\.isFinite)
        else { return [] }
        let shown = visible.intersection(output)
        guard !shown.isNull, shown.width > 0, shown.height > 0 else { return [] }
        let originX = Int(output.minX), originY = Int(output.minY)
        var cells: [CGRect] = []
        for y in stride(
            from: originY + (Int(shown.minY) - originY) / side * side, to: Int(shown.maxY.rounded(.up)), by: side)
        {
            for x in stride(
                from: originX + (Int(shown.minX) - originX) / side * side, to: Int(shown.maxX.rounded(.up)), by: side)
            {
                cells.append(
                    CGRect(
                        x: x, y: y, width: min(side, Int(output.maxX) - x), height: min(side, Int(output.maxY) - y)))
            }
        }
        return cells
    }

    private static let coarsestLevel: CGFloat = 1.0 / 64
}
