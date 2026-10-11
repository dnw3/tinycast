import Accelerate
import Foundation

final class CaptureCompositeReader {
    private let document: CaptureDocument
    private let directory: URL
    private var currentRaster: String?
    private var reader: CaptureRasterReader?
    private var rowBuffer: [UInt8] = []

    init(document: CaptureDocument, directory: URL) throws {
        self.document = try document.validated()
        self.directory = directory
    }

    func read(rect: CGRect) throws -> Data {
        guard CaptureGeometry.valid(rect), document.bounds.contains(rect) else {
            throw CaptureRasterError.invalidRow
        }
        let width = Int(rect.width)
        let height = Int(rect.height)
        guard width * height <= 4_194_304 else { throw CaptureRasterError.invalidSize }
        var data = Data(count: width * height * 4)
        try data.withUnsafeMutableBytes { destination in
            for piece in document.pieces {
                let intersection = rect.intersection(piece.bounds)
                guard CaptureGeometry.valid(intersection) else { continue }
                if currentRaster != piece.raster {
                    reader = try CaptureRasterReader(
                        directory: directory.appendingPathComponent(piece.raster))
                    currentRaster = piece.raster
                    rowBuffer = [UInt8](repeating: 0, count: reader!.raster.size.rowBytes)
                }
                guard let reader,
                    CGRect(x: 0, y: 0, width: reader.raster.size.width, height: reader.raster.size.height)
                        .contains(piece.source)
                else { throw CaptureRasterError.invalidTile }
                for y in Int(intersection.minY)..<Int(intersection.maxY) {
                    try Task.checkCancellation()
                    let localY = y - Int(piece.origin.y)
                    let sourceY = Int(piece.source.minY)
                        + (piece.reflection?.vertical == true ? Int(piece.source.height) - 1 - localY : localY)
                    try rowBuffer.withUnsafeMutableBytes { try reader.read(row: sourceY, into: $0) }
                    let sourceX = Int(intersection.minX - piece.origin.x + piece.source.minX)
                    let destinationOffset =
                        ((y - Int(rect.minY)) * width + Int(intersection.minX - rect.minX)) * 4
                    try rowBuffer.withUnsafeMutableBytes { source in
                        let output = destination.baseAddress!.advanced(by: destinationOffset)
                        if piece.reflection?.horizontal == true {
                            let start = Int(piece.source.maxX - intersection.maxX + piece.origin.x)
                            var input = vImage_Buffer(data: source.baseAddress!.advanced(by: start * 4), height: 1,
                                width: vImagePixelCount(intersection.width), rowBytes: Int(intersection.width) * 4)
                            var result = vImage_Buffer(data: output, height: 1,
                                width: input.width, rowBytes: input.rowBytes)
                            guard vImageHorizontalReflect_ARGB8888(&input, &result, vImage_Flags(kvImageDoNotTile))
                                == kvImageNoError else { throw CaptureRasterError.invalidTile }
                        } else {
                            output.copyMemory(from: source.baseAddress!.advanced(by: sourceX * 4),
                                byteCount: Int(intersection.width) * 4)
                        }
                    }
                }
            }
        }
        try CaptureImageLayerRenderer.composite(document.imageLayers, directory: directory, rect: rect, into: &data)
        try CaptureCensorRenderer.mask(document.edit.annotations, rect: rect, pixels: &data)
        return data
    }
}
