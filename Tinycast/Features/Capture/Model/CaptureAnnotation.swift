import Foundation

struct CaptureAnnotation: Codable, Equatable, Sendable, Identifiable {
    enum Tool: String, Codable, CaseIterable, Sendable {
        case select, arrow, rectangle, ellipse, text, pen, number, cover, pixelate, crop
        case line, curvedArrow, highlighter, ruler, spotlight, blur, erase, emoji, magnifier

        var title: String { self == .curvedArrow ? "Curved Arrow" : rawValue.capitalized }
        var advanced: Bool {
            [.line, .curvedArrow, .highlighter, .ruler, .spotlight, .blur, .erase, .emoji, .magnifier].contains(self)
        }
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
    var rgba: [Double] { color?.rgba ?? ink.rgba }

    var bounds: CGRect {
        let rect = drawingBounds
        let angle = (rotation ?? 0) * .pi / 180
        let width = abs(rect.width * cos(angle)) + abs(rect.height * sin(angle))
        let height = abs(rect.width * sin(angle)) + abs(rect.height * cos(angle))
        return CGRect(x: rect.midX - width / 2, y: rect.midY - height / 2, width: width, height: height)
    }

    var curveControl: CGPoint {
        guard let first = points.first, let last = points.last else { return .zero }
        return CGPoint(x: (first.x + last.x) / 2 - (last.y - first.y) / 4,
            y: (first.y + last.y) / 2 + (last.x - first.x) / 4)
    }

    var drawingBounds: CGRect {
        guard let first = points.first else { return .zero }
        if tool == .number {
            let side = max(28, width * 9)
            return CGRect(x: first.x, y: first.y, width: side, height: side)
        }
        let outline = tool == .curvedArrow ? points + [curveControl] : points
        return outline.dropFirst().reduce(CGRect(origin: first, size: .zero)) { rect, point in
            CGRect(
                x: min(rect.minX, point.x), y: min(rect.minY, point.y),
                width: max(rect.maxX, point.x) - min(rect.minX, point.x),
                height: max(rect.maxY, point.y) - min(rect.minY, point.y))
        }
    }

    var isValid: Bool {
        !points.isEmpty && points.count <= 20_000 && width.isFinite && (1...128).contains(width)
            && points.allSatisfy {
                $0.x.isFinite && $0.y.isFinite && abs($0.x) <= 30_000 && abs($0.y) <= 30_000
            }
            && text.utf8.count <= 32_000 && tool != .select && tool != .crop
            && (rotation.map { $0.isFinite && (-180...180).contains($0) } ?? true)
            && (fontSize.map { $0.isFinite && (6...768).contains($0) } ?? true)
            && (magnification.map { $0.isFinite && (2...8).contains($0) } ?? true)
    }

    mutating func move(by delta: CGSize) {
        points = points.map { CGPoint(x: $0.x + delta.width, y: $0.y + delta.height) }
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
