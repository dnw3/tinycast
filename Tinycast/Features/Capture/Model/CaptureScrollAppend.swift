import Foundation

enum CaptureScrollAppend {
    static func plan(
        document: CaptureDocument, frame: CapturePixelSize, raster: String, offset: Int?, trailing: Int
    ) throws -> (document: CaptureDocument, source: CGRect) {
        let vertical = document.axis != .horizontal
        let length = vertical ? frame.height : frame.width
        let amount = offset ?? length
        let previous = document.pieces.isEmpty ? 0 : (vertical ? document.size.height : document.size.width)
        guard amount > 0, trailing >= 0, amount + trailing <= length,
            document.pieces.count < 1000,
            document.pieces.isEmpty
                || (vertical ? frame.width == document.size.width : frame.height == document.size.height)
        else { throw CaptureRasterError.invalidSize }
        var next = document
        let retained = max(0, previous - trailing)
        next.pieces = document.pieces.compactMap { piece in
            var piece = piece
            let start = vertical ? piece.origin.y : piece.origin.x
            let end = vertical ? piece.bounds.maxY : piece.bounds.maxX
            guard start < CGFloat(retained) else { return nil }
            if end > CGFloat(retained) {
                if vertical {
                    piece.source.size.height = CGFloat(retained) - start
                } else {
                    piece.source.size.width = CGFloat(retained) - start
                }
            }
            return piece
        }
        let appended = amount + (previous == 0 ? 0 : trailing)
        let source = CGRect(
            x: vertical ? 0 : length - appended, y: vertical ? length - appended : 0,
            width: vertical ? frame.width : appended, height: vertical ? appended : frame.height)
        next.size = try CapturePixelSize(
            width: vertical ? frame.width : retained + appended,
            height: vertical ? retained + appended : frame.height)
        next.pieces.append(
            .init(
                raster: raster, source: CGRect(origin: .zero, size: source.size),
                origin: CGPoint(x: vertical ? 0 : retained, y: vertical ? retained : 0)))
        next.revision += 1
        return (try next.validated(), source)
    }
}
