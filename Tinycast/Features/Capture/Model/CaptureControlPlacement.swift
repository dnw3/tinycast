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
            CGPoint(x: max(region.maxX, toolbar.maxX) + gap, y: region.maxY - outputs.height),
            CGPoint(x: min(region.minX, toolbar.minX) - gap - outputs.width, y: region.maxY - outputs.height),
            CGPoint(x: region.maxX - outputs.width, y: toolbar.maxY + gap),
            CGPoint(x: region.maxX - outputs.width, y: toolbar.minY - gap - outputs.height),
            CGPoint(x: safe.maxX - outputs.width, y: safe.maxY - outputs.height),
            CGPoint(x: safe.minX, y: safe.maxY - outputs.height),
            CGPoint(x: safe.maxX - outputs.width, y: safe.minY),
            safe.origin
        ].map { clamped($0, size: outputs) }
        let clear = candidates.filter { !$0.intersects(toolbar.insetBy(dx: -gap, dy: -gap)) }
        if let output = clear.first(where: { !$0.intersects(region) }) ?? clear.first {
            return (toolbar, output)
        }
        toolbar.origin.y = safe.minY
        return (toolbar, clamped(CGPoint(x: safe.maxX, y: safe.maxY), size: outputs))
    }

    static func scrolling(
        region: CGRect, row: CGSize, detailsHeight: CGFloat, screens: [CGRect], gap: CGFloat
    ) -> (collapsed: CGRect, expanded: CGRect)? {
        let size = CGSize(width: row.width, height: row.height + detailsHeight)
        guard let expanded = frame(region: region, size: size, screens: screens, gap: gap) else { return nil }
        let collapsed = CGRect(x: expanded.minX, y: expanded.maxY - row.height,
            width: row.width, height: row.height)
        return (collapsed, expanded)
    }

    /// A strip beside the region, as tall as it, clear of it and its controls; nil without room.
    static func scrollingPreview(
        region: CGRect, width: CGFloat, controls: CGRect, screens: [CGRect], gap: CGFloat
    ) -> CGRect? {
        for screen in screens where screen.intersects(region) {
            let top = min(region.maxY, screen.maxY), bottom = max(region.minY, screen.minY)
            guard top - bottom > width else { continue }
            let candidates = [
                CGRect(x: region.maxX + gap, y: bottom, width: width, height: top - bottom),
                CGRect(x: region.minX - gap - width, y: bottom, width: width, height: top - bottom)
            ]
            if let placement = candidates.first(where: {
                screen.contains($0) && !$0.intersects(region) && !$0.intersects(controls)
            }) {
                return placement
            }
        }
        return nil
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
