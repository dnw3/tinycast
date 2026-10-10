import Foundation

enum CaptureControlPlacement {
    static func workspace(
        region: CGRect?, tools: CGSize, outputs: CGSize, screen: CGRect, gap: CGFloat
    ) -> (tools: CGRect, outputs: CGRect) {
        let safe = screen.insetBy(dx: gap, dy: gap)
        let tools = CGSize(width: min(tools.width, safe.width), height: min(tools.height, safe.height / 3))
        let outputs = CGSize(
            width: min(outputs.width, safe.width), height: min(outputs.height, safe.height - tools.height - gap))
        let region = region ?? CGRect(x: safe.midX, y: safe.minY, width: 0, height: 0)
        func clamped(_ point: CGPoint, size: CGSize) -> CGRect {
            CGRect(
                x: min(max(point.x, safe.minX), safe.maxX - size.width),
                y: min(max(point.y, safe.minY), safe.maxY - size.height),
                width: size.width, height: size.height)
        }
        let x = region.midX - tools.width / 2
        let below = region.minY - gap - tools.height
        let above = region.maxY + gap
        let y = below >= safe.minY ? below : above + tools.height <= safe.maxY ? above : safe.minY
        var toolbar = clamped(CGPoint(x: x, y: y), size: tools)
        let candidates = [
            CGPoint(x: region.maxX + gap, y: region.maxY - outputs.height),
            CGPoint(x: region.minX - gap - outputs.width, y: region.maxY - outputs.height),
            CGPoint(x: region.maxX - outputs.width, y: toolbar.maxY + gap),
            CGPoint(x: region.maxX - outputs.width, y: toolbar.minY - gap - outputs.height),
            CGPoint(x: safe.maxX - outputs.width, y: safe.maxY - outputs.height),
            CGPoint(x: safe.minX, y: safe.maxY - outputs.height),
            CGPoint(x: safe.maxX - outputs.width, y: safe.minY),
            safe.origin
        ].map { clamped($0, size: outputs) }
        if let output = candidates.first(where: { !$0.intersects(toolbar.insetBy(dx: -gap, dy: -gap)) }) {
            return (toolbar, output)
        }
        toolbar.origin.y = safe.minY
        return (toolbar, clamped(CGPoint(x: safe.maxX, y: safe.maxY), size: outputs))
    }

    static func frame(region: CGRect, size: CGSize, screens: [CGRect], gap: CGFloat) -> CGRect? {
        for screen in screens {
            let x = min(max(region.midX - size.width / 2, screen.minX), screen.maxX - size.width)
            let y = min(max(region.midY - size.height / 2, screen.minY), screen.maxY - size.height)
            let candidates = [
                CGRect(x: x, y: region.maxY + gap, width: size.width, height: size.height),
                CGRect(x: x, y: region.minY - gap - size.height, width: size.width, height: size.height),
                CGRect(x: region.maxX + gap, y: y, width: size.width, height: size.height),
                CGRect(x: region.minX - gap - size.width, y: y, width: size.width, height: size.height),
                CGRect(origin: screen.origin, size: size)
            ]
            if let placement = candidates.first(where: { screen.contains($0) && !$0.intersects(region) }) {
                return placement
            }
        }
        return nil
    }
}
