import Foundation

struct CapturePixelSize: Codable, Equatable, Sendable {
    static let maximumEdge = 30_000
    static let maximumPixels = 64_000_000

    let width: Int
    let height: Int

    var rowBytes: Int { width * 4 }
    var byteCount: Int { rowBytes * height }

    init(width: Int, height: Int) throws {
        guard width > 0, height > 0,
            width <= Self.maximumEdge, height <= Self.maximumEdge,
            width * height <= Self.maximumPixels
        else { throw CaptureRasterError.invalidSize }
        self.width = width
        self.height = height
    }

    init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            width: values.decode(Int.self, forKey: .width),
            height: values.decode(Int.self, forKey: .height))
    }
}
