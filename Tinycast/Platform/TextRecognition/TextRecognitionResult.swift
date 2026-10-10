import Foundation

struct TextRecognitionResult: Codable, Sendable {
    enum Content: String, Codable, Sendable { case text, qr, faces, people }
    struct Box: Codable, Sendable {
        let text: String
        let rect: CGRect

        func combining(_ other: Self) -> Self? {
            let overlap = rect.intersection(other.rect)
            guard !overlap.isNull, overlap.width > 0,
                overlap.height > min(rect.height, other.rect.height) * 0.7,
                abs(rect.midY - other.rect.midY) < max(rect.height, other.rect.height) * 0.4
            else { return nil }
            if overlap.width * overlap.height > min(rect.width * rect.height, other.rect.width * other.rect.height) * 0.5 {
                if text.contains(other.text) { return self }
                if other.text.contains(text) { return other }
            }
            if overlap.width > min(rect.width, other.rect.width) * 0.9 {
                if text.count > other.text.count * 2, rect.width > other.rect.width * 2 { return self }
                if other.text.count > text.count * 2, other.rect.width > rect.width * 2 { return other }
            }
            let left = rect.minX <= other.rect.minX ? self : other
            let right = rect.minX <= other.rect.minX ? other : self
            guard left.rect.maxX < right.rect.maxX else { return nil }
            let prefix = Array(left.text), suffix = Array(right.text)
            let maximum = min(256, prefix.count, suffix.count)
            guard maximum >= 2 else { return nil }
            for length in stride(from: maximum, through: 2, by: -1)
                where prefix.suffix(length).elementsEqual(suffix.prefix(length)) {
                return Self(text: left.text + String(suffix.dropFirst(length)), rect: rect.union(other.rect))
            }
            return nil
        }
    }
    let requestID: UUID
    let revision: Int
    var boxes: [Box]
    var truncated: Bool
    var text: String { boxes.map(\.text).joined(separator: "\n") }

    mutating func append(_ box: Box, mergingTextFragments: Bool = false) {
        var candidate = box
        var retained: [Box] = []
        if mergingTextFragments {
            for existing in boxes {
                if let combined = existing.combining(candidate) { candidate = combined } else { retained.append(existing) }
            }
        } else { retained = boxes }
        guard
            !retained.contains(where: {
                let overlap = $0.rect.intersection(candidate.rect)
                return $0.text == candidate.text && !overlap.isNull
                    && overlap.width * overlap.height > min(
                        $0.rect.width * $0.rect.height, candidate.rect.width * candidate.rect.height) * 0.5
            })
        else { return }
        guard retained.count < 1000,
            retained.reduce(0, { $0 + $1.text.utf8.count + 1 }) + candidate.text.utf8.count + 1 <= 32_000
        else {
            truncated = true
            return
        }
        boxes = retained
        boxes.append(candidate)
    }

    mutating func orderForReading() {
        boxes.sort {
            let first = Int($0.rect.midY / 8), second = Int($1.rect.midY / 8)
            return first == second ? $0.rect.minX < $1.rect.minX : first < second
        }
    }

    struct Request: Codable, Sendable {
        struct Tile: Codable, Sendable {
            let filename: String
            let rect: CGRect

            func readingRange(among tiles: [Self]) -> Range<CGFloat> {
                var lower = rect.minY, upper = rect.maxY
                for tile in tiles where tile.rect.minX == rect.minX && tile.rect.width == rect.width {
                    if tile.rect.minY < rect.minY, tile.rect.maxY > rect.minY {
                        lower = max(lower, (rect.minY + min(rect.maxY, tile.rect.maxY)) / 2)
                    }
                    if tile.rect.minY > rect.minY, tile.rect.minY < rect.maxY {
                        upper = min(upper, (max(rect.minY, tile.rect.minY) + rect.maxY) / 2)
                    }
                }
                return lower..<max(lower, upper)
            }
        }
        let requestID: UUID
        let revision: Int
        let tiles: [Tile]
        var content: Content = .text
    }
}
