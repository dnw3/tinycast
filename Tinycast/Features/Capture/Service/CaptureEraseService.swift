import Foundation

enum CaptureEraseService {
    nonisolated static func color(document: CaptureDocument, directory: URL, around rect: CGRect) throws -> CaptureColor {
        let bounds = document.outputBounds
        guard CaptureGeometry.valid(rect), bounds.contains(rect) else { throw CaptureRasterError.invalidSize }
        var points: [CGPoint] = []
        for step in 0..<8 {
            let fraction = (CGFloat(step) + 0.5) / 8
            points += [CGPoint(x: rect.minX + rect.width * fraction, y: rect.minY - 2),
                CGPoint(x: rect.minX + rect.width * fraction, y: rect.maxY + 1),
                CGPoint(x: rect.minX - 2, y: rect.minY + rect.height * fraction),
                CGPoint(x: rect.maxX + 1, y: rect.minY + rect.height * fraction)]
        }
        let colors = try points.filter { bounds.contains($0) && !rect.contains($0) }.map { point in
            try Task.checkCancellation()
            return try autoreleasepool { try CaptureRenderer.color(document: document, directory: directory, at: point) }
        }
        guard !colors.isEmpty else { throw Failure.noSurroundingPixels }
        let groups = Dictionary(grouping: colors) {
            Int($0.red / 16) << 8 | Int($0.green / 16) << 4 | Int($0.blue / 16)
        }
        let key = groups.keys.sorted().max { groups[$0]!.count < groups[$1]!.count }!
        let samples = groups[key]!
        func median(_ channel: KeyPath<CaptureColor, UInt8>) -> UInt8 {
            samples.map { $0[keyPath: channel] }.sorted()[samples.count / 2]
        }
        return CaptureColor(red: median(\.red), green: median(\.green), blue: median(\.blue))
    }

    enum Failure: LocalizedError {
        case noSurroundingPixels
        var errorDescription: String? { "Leave some background outside the erase area, then try again." }
    }
}
