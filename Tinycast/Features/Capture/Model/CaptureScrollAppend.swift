import Foundation

enum CaptureScrollAppend {
    /// `atStart` grows the result before its first line from the frame's leading lines.
    static func plan(
        document: CaptureDocument, frame: CapturePixelSize, raster: String, offset: Int?, trailing: Int,
        atStart: Bool = false
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
        if atStart, previous > 0 {
            return try prepend(document: document, frame: frame, raster: raster, amount: amount, trailing: trailing)
        }
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

    private static func prepend(
        document: CaptureDocument, frame: CapturePixelSize, raster: String, amount: Int, trailing: Int
    ) throws -> (document: CaptureDocument, source: CGRect) {
        let vertical = document.axis != .horizontal
        let along = { (point: CGPoint) in vertical ? point.y : point.x }
        let span = { (size: CGSize) in vertical ? size.height : size.width }
        let previous = vertical ? document.size.height : document.size.width
        let dropped = CGFloat(min(trailing, previous))
        var next = document
        next.pieces = document.pieces.compactMap { piece in
            var piece = piece
            let start = along(piece.origin), end = start + span(piece.source.size)
            guard end > dropped else { return nil }
            let cut = max(0, dropped - start)
            if vertical {
                piece.source.origin.y += cut
                piece.source.size.height -= cut
                piece.origin.y = max(start, dropped) + CGFloat(amount)
            } else {
                piece.source.origin.x += cut
                piece.source.size.width -= cut
                piece.origin.x = max(start, dropped) + CGFloat(amount)
            }
            return piece
        }
        let added = amount + Int(dropped)
        let source = CGRect(
            x: 0, y: 0, width: vertical ? frame.width : added, height: vertical ? added : frame.height)
        next.size = try CapturePixelSize(
            width: vertical ? frame.width : previous + amount, height: vertical ? previous + amount : frame.height)
        next.pieces.insert(.init(raster: raster, source: CGRect(origin: .zero, size: source.size), origin: .zero), at: 0)
        next.revision += 1
        return (try next.validated(), source)
    }
}
