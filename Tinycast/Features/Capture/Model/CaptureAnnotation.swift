import Foundation

struct CaptureAnnotation: Codable, Equatable, Sendable, Identifiable {
    enum Tool: String, Codable, CaseIterable, Sendable {
        case select, arrow, rectangle, ellipse, text, pen, number, cover, pixelate, crop
        case line, curvedArrow, highlighter, ruler, spotlight, blur, erase, emoji, magnifier

        var title: String { self == .curvedArrow ? "Curved Arrow" : rawValue.capitalized }
        var key: String {
            switch self {
            case .select: "v"
            case .arrow: "a"
            case .rectangle: "r"
            case .ellipse: "o"
            case .text: "t"
            case .pen: "p"
            case .number: "n"
            case .cover: "b"
            case .pixelate: "m"
            case .crop: "c"
            case .line: "l"
            case .curvedArrow: "q"
            case .highlighter: "h"
            case .ruler: "u"
            case .spotlight: "s"
            case .blur: "f"
            case .erase: "e"
            case .emoji: "j"
            case .magnifier: "g"
            }
        }
        static func shortcut(_ key: String?) -> Tool? {
            allCases.first { $0.key == key?.lowercased() }
        }
        var symbol: String {
            switch self {
            case .select: "cursorarrow"
            case .arrow: "arrow.up.right"
            case .rectangle: "rectangle"
            case .ellipse: "circle"
            case .text: "textformat"
            case .pen: "pencil.tip"
            case .number: "number.circle"
            case .cover: "square.fill"
            case .pixelate: "square.grid.3x3.fill"
            case .crop: "crop"
            case .line: "line.diagonal"
            case .curvedArrow: "arrow.up.right"
            case .highlighter: "highlighter"
            case .ruler: "ruler"
            case .spotlight: "light.beacon.max"
            case .blur: "drop.halffull"
            case .erase: "eraser"
            case .emoji: "face.smiling"
            case .magnifier: "plus.magnifyingglass"
            }
        }
    }

    enum ArrowStyle: String, Codable, CaseIterable, Sendable {
        case single, double, thick, open
        var title: String { rawValue.capitalized }
    }

    enum ShapeStyle: String, Codable, CaseIterable, Sendable {
        case outline, fill, both
        var title: String {
            switch self {
            case .outline: "Outline"
            case .fill: "Fill"
            case .both: "Outline and Fill"
            }
        }
    }

    enum Font: String, Codable, CaseIterable, Sendable {
        case system, serif, monospaced
        var title: String { rawValue.capitalized }
    }

    enum Ink: String, Codable, CaseIterable, Sendable {
        case red, blue, yellow, black, white
        var rgba: [Double] {
            switch self {
            case .red: [0.95, 0.22, 0.25, 1]
            case .blue: [0.1, 0.5, 1, 1]
            case .yellow: [1, 0.8, 0.1, 1]
            case .black: [0, 0, 0, 1]
            case .white: [1, 1, 1, 1]
            }
        }
    }

    let id: UUID
    var tool: Tool
    var points: [CGPoint]
    var ink: Ink = .red
    var width: Double = 4
    var text = ""
    var rotation: Double?
    var font: Font?
    var fontSize: Double?
    var filled: Bool?
    var color: CaptureColor?
    var reflection: CaptureReflection?
    var magnification: Double?
    var arrowStyle: ArrowStyle?
    var reversed: Bool?
    var shapeStyle: ShapeStyle?
    var cornerRadius: Double?
    var controlPoint: CGPoint?
    var controlCenter: CGPoint?
    var textFormat: CaptureTextFormat?
    var numberFormat: CaptureNumberFormat?
    var numberLeader: Bool?
    var smoothed: Bool?
    var effectiveShapeStyle: ShapeStyle { shapeStyle ?? (filled == true ? .fill : .outline) }
    var rgba: [Double] { color?.rgba ?? ink.rgba }
    var effectiveTextFormat: CaptureTextFormat {
        textFormat ?? CaptureTextFormat(base: CaptureTextStyle(font: font ?? .system, size: fontSize ?? width * 6,
            color: CaptureColor(red: UInt8((rgba[0] * 255).rounded()), green: UInt8((rgba[1] * 255).rounded()),
                blue: UInt8((rgba[2] * 255).rounded()))))
    }

    var transformCenter: CGPoint {
        let bounds = tool == .number ? numberBounds : drawingBounds
        return controlCenter ?? CGPoint(x: bounds.midX, y: bounds.midY)
    }

    var bounds: CGRect {
        let rect = drawingBounds
        let corners = [CGPoint(x: rect.minX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.minY),
            CGPoint(x: rect.minX, y: rect.maxY), CGPoint(x: rect.maxX, y: rect.maxY)].map(transformed)
        let xs = corners.map(\.x), ys = corners.map(\.y)
        return CGRect(x: xs.min()!, y: ys.min()!, width: xs.max()! - xs.min()!, height: ys.max()! - ys.min()!)
    }

    var curveControl: CGPoint {
        if let controlPoint { return controlPoint }
        guard let first = points.first, let last = points.last else { return .zero }
        return CGPoint(x: (first.x + last.x) / 2 - (last.y - first.y) / 4,
            y: (first.y + last.y) / 2 + (last.x - first.x) / 4)
    }

    var displayedControl: CGPoint? {
        if tool == .curvedArrow { return transformed(curveControl) }
        if tool == .number, numberLeader == true, points.count > 1, let last = points.last { return transformed(last) }
        return nil
    }

    func transformed(_ point: CGPoint) -> CGPoint {
        let center = transformCenter
        let x = (point.x - center.x) * (reflection?.horizontal == true ? -1 : 1)
        let y = (point.y - center.y) * (reflection?.vertical == true ? -1 : 1)
        let angle = (rotation ?? 0) * .pi / 180
        return CGPoint(x: center.x + x * cos(angle) - y * sin(angle),
            y: center.y + x * sin(angle) + y * cos(angle))
    }

    func untransformed(_ point: CGPoint) -> CGPoint {
        let center = transformCenter
        let angle = -(rotation ?? 0) * .pi / 180
        let x = point.x - center.x, y = point.y - center.y
        return CGPoint(x: center.x + (x * cos(angle) - y * sin(angle)) * (reflection?.horizontal == true ? -1 : 1),
            y: center.y + (x * sin(angle) + y * cos(angle)) * (reflection?.vertical == true ? -1 : 1))
    }

    var drawingBounds: CGRect {
        guard let first = points.first else { return .zero }
        if tool == .number {
            let badge = numberBounds
            guard numberLeader == true, let last = points.last else { return badge }
            return badge.union(CGRect(x: last.x - width / 2, y: last.y - width / 2, width: width, height: width))
        }
        let outline = tool == .curvedArrow ? points + [curveControl] : points
        return outline.dropFirst().reduce(CGRect(origin: first, size: .zero)) { rect, point in
            CGRect(
                x: min(rect.minX, point.x), y: min(rect.minY, point.y),
                width: max(rect.maxX, point.x) - min(rect.minX, point.x),
                height: max(rect.maxY, point.y) - min(rect.minY, point.y))
        }
    }

    var numberBounds: CGRect {
        let origin = points.first ?? .zero, side = max(28, width * 9)
        return CGRect(x: origin.x, y: origin.y, width: side, height: side)
    }

    var numberLabel: String { numberFormat?.label ?? text }

    var isValid: Bool {
        !points.isEmpty && points.count <= 20_000 && width.isFinite && (1...128).contains(width)
            && points.allSatisfy {
                $0.x.isFinite && $0.y.isFinite && abs($0.x) <= 30_000 && abs($0.y) <= 30_000
            }
            && text.utf8.count <= 32_000 && tool != .select && tool != .crop
            && (textFormat.map { $0.isValid(for: text) } ?? true)
            && (numberFormat.map(\.isValid) ?? true)
            && (tool != .number || numberLeader != true || points.count > 1)
            && (rotation.map { $0.isFinite && (-180...180).contains($0) } ?? true)
            && (fontSize.map { $0.isFinite && (6...768).contains($0) } ?? true)
            && (cornerRadius.map { $0.isFinite && (0...256).contains($0) } ?? true)
            && [controlPoint, controlCenter].compactMap { $0 }.allSatisfy {
                $0.x.isFinite && $0.y.isFinite && abs($0.x) <= 30_000 && abs($0.y) <= 30_000
            }
            && (magnification.map { $0.isFinite && (2...8).contains($0) } ?? true)
    }

    mutating func move(by delta: CGSize) {
        points = points.map { CGPoint(x: $0.x + delta.width, y: $0.y + delta.height) }
        controlPoint = controlPoint.map { CGPoint(x: $0.x + delta.width, y: $0.y + delta.height) }
        controlCenter = controlCenter.map { CGPoint(x: $0.x + delta.width, y: $0.y + delta.height) }
    }

    mutating func sizeEmoji(_ size: Double, in bounds: CGRect) {
        guard tool == .emoji, let first = points.first, size.isFinite else { return }
        let side = min(min(bounds.width, bounds.height), min(768, max(6, size)) * 1.5)
        let origin = CGPoint(x: max(bounds.minX, min(first.x, bounds.maxX - side)),
            y: max(bounds.minY, min(first.y, bounds.maxY - side)))
        fontSize = max(6, side / 1.5)
        points = [origin, CGPoint(x: origin.x + side, y: origin.y + side)]
    }
}
