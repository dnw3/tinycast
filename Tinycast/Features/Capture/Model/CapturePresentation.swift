import Foundation

struct CapturePresentation: Codable, Equatable, Sendable {
    enum Background: String, Codable, CaseIterable, Sendable {
        case transparent, solid, gradient, grid
        var title: String { rawValue.capitalized }
    }

    var background: Background = .gradient
    var color = CaptureColor(red: 55, green: 88, blue: 155)
    var secondary = CaptureColor(red: 146, green: 84, blue: 168)
    var padding = 48.0
    var radius = 16.0
    var shadow = 20.0
    var windowFrame = false

    var isValid: Bool {
        [padding, radius, shadow].allSatisfy(\.isFinite)
            && (0...160).contains(padding) && (0...80).contains(radius) && (0...60).contains(shadow)
    }

    var headerHeight: Double { windowFrame ? 32 : 0 }

    func frame(for content: CGRect) -> CGRect {
        CGRect(x: content.minX, y: content.minY - headerHeight,
            width: content.width, height: content.height + headerHeight)
    }

    func bounds(for content: CGRect) -> CGRect {
        frame(for: content).insetBy(dx: -padding.rounded(), dy: -padding.rounded())
    }
}
