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
}
