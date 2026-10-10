import Foundation

struct CaptureImageMaskReader {
    let size: CapturePixelSize
    let pixels: Data

    nonisolated init(_ mask: CaptureImageLayer.Mask, directory: URL) throws {
        guard mask.isValid else { throw CaptureRasterError.invalidTile }
        size = mask.size
        let document = CaptureDocument(id: UUID(), createdAt: .distantPast, size: size,
            pieces: [.init(raster: mask.raster, source: mask.bounds, origin: .zero)])
        pixels = try CaptureCompositeReader(document: document, directory: directory).read(rect: mask.bounds)
    }

    nonisolated func apply(to data: inout Data, rect: CGRect, source: CGRect) {
        data.withUnsafeMutableBytes { (bytes: UnsafeMutableRawBufferPointer) in
            pixels.withUnsafeBytes { (mask: UnsafeRawBufferPointer) in
                for y in 0..<Int(rect.height) {
                    let my = max(0, min(Double(size.height - 1),
                        (rect.minY + Double(y) + 0.5 - source.minY) / source.height * Double(size.height) - 0.5))
                    let y0 = Int(my), y1 = min(size.height - 1, y0 + 1), dy = my - Double(y0)
                    for x in 0..<Int(rect.width) {
                        let mx = max(0, min(Double(size.width - 1),
                            (rect.minX + Double(x) + 0.5 - source.minX) / source.width * Double(size.width) - 0.5))
                        let x0 = Int(mx), x1 = min(size.width - 1, x0 + 1), dx = mx - Double(x0)
                        let top = Double(mask[(y0 * size.width + x0) * 4 + 3]) * (1 - dx)
                            + Double(mask[(y0 * size.width + x1) * 4 + 3]) * dx
                        let bottom = Double(mask[(y1 * size.width + x0) * 4 + 3]) * (1 - dx)
                            + Double(mask[(y1 * size.width + x1) * 4 + 3]) * dx
                        let alpha = (top * (1 - dy) + bottom * dy) / 255
                        let offset = (y * Int(rect.width) + x) * 4
                        bytes[offset + 3] = UInt8((Double(bytes[offset + 3]) * alpha).rounded())
                        if bytes[offset + 3] == 0 {
                            bytes[offset] = 0; bytes[offset + 1] = 0; bytes[offset + 2] = 0
                        }
                    }
                }
            }
        }
    }
}
