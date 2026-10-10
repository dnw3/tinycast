import Foundation

enum CaptureSelectionConstraint {
    enum Aspect: String, CaseIterable, Sendable {
        case free, square, landscape, portrait, photo
        var title: String {
            switch self {
            case .free: "Free"
            case .square: "1:1"
            case .landscape: "16:9"
            case .portrait: "9:16"
            case .photo: "4:3"
            }
        }
        var ratio: CGFloat? {
            switch self {
            case .free: nil
            case .square: 1
            case .landscape: 16 / 9
            case .portrait: 9 / 16
            case .photo: 4 / 3
            }
        }
    }

    static func selection(from anchor: CGPoint, to point: CGPoint, ratio: CGFloat?, in bounds: CGRect) -> CGRect? {
        guard let ratio, ratio.isFinite, ratio > 0 else {
            return CaptureGeometry.selection(from: anchor, to: point, in: bounds)
        }
        let right = point.x >= anchor.x, up = point.y >= anchor.y
        let maxWidth = right ? bounds.maxX - anchor.x : anchor.x - bounds.minX
        let maxHeight = up ? bounds.maxY - anchor.y : anchor.y - bounds.minY
        let height = min(max(abs(point.y - anchor.y), abs(point.x - anchor.x) / ratio), maxHeight, maxWidth / ratio)
        guard height >= 2, height * ratio >= 2 else { return nil }
        let width = max(0, height) * ratio
        return CGRect(x: right ? anchor.x : anchor.x - width, y: up ? anchor.y : anchor.y - height,
            width: width, height: max(0, height))
    }

    static func resized(
        _ rect: CGRect, handle: CaptureSelectionGeometry.Handle, to point: CGPoint,
        ratio: CGFloat?, in bounds: CGRect) -> CGRect
    {
        guard let ratio else { return CaptureSelectionGeometry.resized(rect, handle: handle, to: point, in: bounds) }
        let unit = handle.unitPoint
        if unit.x != 0.5, unit.y != 0.5 {
            let anchor = CGPoint(x: unit.x == 0 ? rect.maxX : rect.minX, y: unit.y == 0 ? rect.maxY : rect.minY)
            let constrained = CGPoint(x: unit.x == 0 ? min(point.x, anchor.x - 2) : max(point.x, anchor.x + 2),
                y: unit.y == 0 ? min(point.y, anchor.y - 2) : max(point.y, anchor.y + 2))
            return selection(from: anchor, to: constrained, ratio: ratio, in: bounds) ?? rect
        }
        if unit.x == 0.5 {
            let anchor = unit.y == 0 ? rect.maxY : rect.minY
            let maximum = min(unit.y == 0 ? anchor - bounds.minY : bounds.maxY - anchor,
                2 * min(rect.midX - bounds.minX, bounds.maxX - rect.midX) / ratio)
            let height = min(maximum, max(2, unit.y == 0 ? anchor - point.y : point.y - anchor))
            return CGRect(x: rect.midX - height * ratio / 2, y: unit.y == 0 ? anchor - height : anchor,
                width: height * ratio, height: height)
        }
        let anchor = unit.x == 0 ? rect.maxX : rect.minX
        let maximum = min(unit.x == 0 ? anchor - bounds.minX : bounds.maxX - anchor,
            2 * min(rect.midY - bounds.minY, bounds.maxY - rect.midY) * ratio)
        let width = min(maximum, max(2, unit.x == 0 ? anchor - point.x : point.x - anchor))
        return CGRect(x: unit.x == 0 ? anchor - width : anchor, y: rect.midY - width / ratio / 2,
            width: width, height: width / ratio)
    }

    static func sized(_ rect: CGRect, pixels: CGSize, scale: CGFloat, in bounds: CGRect) -> CGRect? {
        guard pixels.width.isFinite, pixels.height.isFinite, scale.isFinite, scale > 0,
            pixels.width >= 1, pixels.height >= 1, pixels.width <= bounds.width * scale,
            pixels.height <= bounds.height * scale
        else { return nil }
        let size = CGSize(width: pixels.width.rounded() / scale, height: pixels.height.rounded() / scale)
        return CGRect(x: min(rect.minX, bounds.maxX - size.width),
            y: max(bounds.minY, rect.maxY - size.height), width: size.width, height: size.height)
    }

    static func snapped(_ point: CGPoint, edges: [CGRect], tolerance: CGFloat) -> CGPoint {
        func nearest(_ value: CGFloat, candidates: [CGFloat]) -> CGFloat {
            candidates.filter { abs($0 - value) <= tolerance }.min { abs($0 - value) < abs($1 - value) } ?? value
        }
        return CGPoint(x: nearest(point.x, candidates: edges.flatMap { [$0.minX, $0.maxX] }),
            y: nearest(point.y, candidates: edges.flatMap { [$0.minY, $0.maxY] }))
    }
}

struct CaptureSavedRegion: Codable, Sendable {
    let displayID: UInt32
    let screenSize: CGSize
    let rect: CGRect

    var isValid: Bool {
        CaptureGeometry.valid(CGRect(origin: .zero, size: screenSize)) && CaptureGeometry.valid(rect)
            && CGRect(origin: .zero, size: screenSize).contains(rect)
    }
}
