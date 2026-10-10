import Foundation

struct CaptureTranslation: Codable, Equatable, Sendable {
    struct Block: Codable, Equatable, Identifiable, Sendable {
        let id: UUID
        let source: String
        var text: String
        var rect: CGRect
        var background: CaptureColor
        var included = true
        var reflection: CaptureReflection?

        var isValid: Bool {
            !source.isEmpty && source.utf8.count <= 12_000 && !text.isEmpty && text.utf8.count <= 12_000
                && CaptureGeometry.valid(rect) && abs(rect.minX) <= 60_000 && abs(rect.minY) <= 60_000
                && rect.width <= 30_000 && rect.height <= 30_000
        }
    }

    var target: String
    var blocks: [Block]
    var enabled = true

    var isValid: Bool {
        !target.isEmpty && target.utf8.count <= 64 && !blocks.isEmpty && blocks.count <= 32
            && blocks.allSatisfy(\.isValid) && Set(blocks.map(\.id)).count == blocks.count
            && blocks.reduce(0, { $0 + $1.text.utf8.count }) <= 96_000
    }

    static func paragraphs(_ lines: [(text: String, rect: CGRect)], in bounds: CGRect) -> [(text: String, rect: CGRect)] {
        var groups: [(text: String, rect: CGRect, last: CGRect)] = []
        let ordered = lines.filter { !$0.text.isEmpty && CaptureGeometry.valid($0.rect.intersection(bounds)) }.sorted {
            Int($0.rect.midY / 8) == Int($1.rect.midY / 8)
                ? $0.rect.minX < $1.rect.minX : $0.rect.minY < $1.rect.minY
        }
        for line in ordered {
            let index = groups.lastIndex { group in
                let gap = line.rect.minY - group.last.maxY
                return gap >= -line.rect.height * 0.2 && gap < line.rect.height * 0.8
                    && (0.65...1.5).contains(line.rect.height / group.last.height)
                    && abs(line.rect.minX - group.last.minX) < max(12, line.rect.height * 0.7)
            }
            if let index {
                groups[index].text += "\n" + line.text
                groups[index].rect = groups[index].rect.union(line.rect)
                groups[index].last = line.rect
            } else { groups.append((line.text, line.rect, line.rect)) }
        }
        return groups.map { ($0.text, $0.rect.insetBy(dx: -2, dy: -2).integral.intersection(bounds)) }
    }
}
