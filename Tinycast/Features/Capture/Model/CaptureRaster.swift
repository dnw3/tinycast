import Foundation

struct CaptureRaster: Codable, Equatable, Sendable {
    static let tileSide = 1024

    let size: CapturePixelSize

    var columns: Int { (size.width - 1) / Self.tileSide + 1 }
    var rows: Int { (size.height - 1) / Self.tileSide + 1 }

    func tile(column: Int, row: Int) -> Tile? {
        guard (0..<columns).contains(column), (0..<rows).contains(row) else { return nil }
        return Tile(
            column: column, row: row,
            width: min(Self.tileSide, size.width - column * Self.tileSide),
            height: min(Self.tileSide, size.height - row * Self.tileSide))
    }

    struct Tile: Equatable, Sendable {
        let column: Int
        let row: Int
        let width: Int
        let height: Int

        var filename: String { "\(column)-\(row).rgba" }
        var rowBytes: Int { width * 4 }
        var byteCount: Int { rowBytes * height }
    }
}
