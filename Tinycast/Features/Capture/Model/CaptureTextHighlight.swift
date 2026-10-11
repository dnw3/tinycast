import Foundation

struct CaptureTextHighlight: Sendable {
    private let snapshot: CaptureDocument
    let lines: [CGRect]
    private(set) var revision: Int

    init(document: CaptureDocument, lines: [CGRect]) {
        snapshot = Self.content(document)
        revision = document.revision
        self.lines = Array(lines.prefix(1000)).compactMap {
            guard CaptureGeometry.valid($0) else { return nil }
            let clipped = $0.intersection(document.outputBounds)
            return CaptureGeometry.valid(clipped) ? clipped : nil
        }
    }

    mutating func advance(to document: CaptureDocument) -> Bool {
        guard Self.content(document) == snapshot else { return false }
        revision = document.revision
        return true
    }

    func annotations(
        from first: CGPoint, to last: CGPoint, ink: CaptureAnnotation.Ink, color: CaptureColor?
    ) -> [CaptureAnnotation] {
        guard [first.x, first.y, last.x, last.y].allSatisfy(\.isFinite) else { return [] }
        let selection = CGRect(x: min(first.x, last.x), y: min(first.y, last.y) - 1,
            width: abs(first.x - last.x), height: abs(first.y - last.y) + 2)
        guard selection.width >= 1 else { return [] }
        return lines.compactMap { line in
            let overlap = line.intersection(selection)
            guard CaptureGeometry.valid(overlap), overlap.width >= 1 else { return nil }
            return CaptureAnnotation(id: UUID(), tool: .highlighter,
                points: [.init(x: overlap.minX, y: line.midY), .init(x: overlap.maxX, y: line.midY)],
                ink: ink, width: min(128, max(1, line.height / 5)), color: color)
        }
    }

    private static func content(_ document: CaptureDocument) -> CaptureDocument {
        var copy = document
        copy.revision = 0
        copy.edit.annotations.removeAll { $0.tool == .highlighter }
        return copy
    }
}
