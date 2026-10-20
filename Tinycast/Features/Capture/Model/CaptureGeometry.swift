import Foundation

enum CaptureGeometry {
    static func valid(_ rect: CGRect) -> Bool {
        rect.origin.x.isFinite && rect.origin.y.isFinite && rect.width.isFinite && rect.height.isFinite
            && rect.width > 0 && rect.height > 0
    }

    static func selection(from first: CGPoint, to last: CGPoint, in bounds: CGRect) -> CGRect? {
        guard first.x.isFinite, first.y.isFinite, last.x.isFinite, last.y.isFinite else { return nil }
        let rect = CGRect(
            x: min(first.x, last.x), y: min(first.y, last.y),
            width: abs(first.x - last.x), height: abs(first.y - last.y)
        ).intersection(bounds)
        return valid(rect) ? rect : nil
    }

    static func pixels(_ rect: CGRect, screen: CGRect, scale: CGFloat) -> CGRect? {
        guard valid(rect), valid(screen), scale.isFinite, scale > 0 else { return nil }
        let local = rect.intersection(screen)
        guard valid(local) else { return nil }
        let left = floor((local.minX - screen.minX) * scale)
        let top = floor((screen.maxY - local.maxY) * scale)
        return CGRect(
            x: left, y: top, width: ceil((local.maxX - screen.minX) * scale) - left,
            height: ceil((screen.maxY - local.minY) * scale) - top)
    }

    /// Whole pixels that stay inside `rect`, so a region trimmed to a window never pokes past it.
    static func innerPixels(_ rect: CGRect, scale: CGFloat) -> CGRect {
        let left = ceil(rect.minX * scale), top = ceil(rect.minY * scale)
        return CGRect(
            x: left, y: top, width: floor(rect.maxX * scale) - left, height: floor(rect.maxY * scale) - top)
    }

    static func integralCrop(_ rect: CGRect, in bounds: CGRect) -> CGRect? {
        guard valid(rect), valid(bounds) else { return nil }
        let result = rect.integral.intersection(bounds)
        return valid(result) ? result : nil
    }
}
