import Foundation

enum CaptureAnnotationPlacement {
    struct Result: Sendable {
        let offset: CGSize
        let verticalGuide: CGFloat?
        let horizontalGuide: CGFloat?
    }

    static func moved(
        _ rect: CGRect, by delta: CGSize, in bounds: CGRect, aligning targets: [CGRect], tolerance: CGFloat
    ) -> Result {
        func clamped(_ delta: CGSize) -> CGSize {
            CGSize(width: max(bounds.minX - rect.minX, min(bounds.maxX - rect.maxX, delta.width)),
                height: max(bounds.minY - rect.minY, min(bounds.maxY - rect.maxY, delta.height)))
        }
        let offset = clamped(delta), moved = rect.offsetBy(dx: offset.width, dy: offset.height)
        func match(_ edges: [CGFloat], to candidates: [CGFloat]) -> (delta: CGFloat, guide: CGFloat)? {
            var best: (delta: CGFloat, guide: CGFloat)?
            for edge in edges {
                for candidate in candidates {
                    let distance = candidate - edge
                    if abs(distance) <= tolerance, best == nil || abs(distance) < abs(best!.delta) {
                        best = (distance, candidate)
                    }
                }
            }
            return best
        }
        let x = match([moved.minX, moved.midX, moved.maxX], to: targets.flatMap { [$0.minX, $0.midX, $0.maxX] })
        let y = match([moved.minY, moved.midY, moved.maxY], to: targets.flatMap { [$0.minY, $0.midY, $0.maxY] })
        let aligned = CGSize(width: offset.width + (x?.delta ?? 0), height: offset.height + (y?.delta ?? 0))
        let result = clamped(aligned)
        return Result(offset: result, verticalGuide: result.width == aligned.width ? x?.guide : nil,
            horizontalGuide: result.height == aligned.height ? y?.guide : nil)
    }
}
