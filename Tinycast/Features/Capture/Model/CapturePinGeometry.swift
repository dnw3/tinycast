import Foundation

nonisolated enum CapturePinGeometry {
    static func fitted(_ size: CGSize, maximum: CGFloat) -> CGSize {
        let scale = min(1, maximum / max(size.width, size.height))
        return CGSize(width: size.width * scale, height: size.height * scale)
    }

    static func resized(
        _ frame: CGRect, factor: CGFloat, anchor: CGPoint, minimum: CGFloat, maximum: CGFloat
    ) -> CGRect {
        guard factor.isFinite, factor > 0 else { return frame }
        let longest = max(frame.width, frame.height)
        let scale = max(min(1, minimum / longest), min(factor, maximum / longest))
        return CGRect(x: frame.minX + anchor.x * (1 - scale),
            y: frame.minY + anchor.y * (1 - scale), width: frame.width * scale, height: frame.height * scale)
    }
}
