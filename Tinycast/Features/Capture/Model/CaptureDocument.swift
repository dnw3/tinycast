import Foundation

struct CaptureDocument: Codable, Equatable, Sendable, Identifiable {
    let id: UUID
    let createdAt: Date
    var size: CapturePixelSize
    var pieces: [Piece]
    var axis: Axis?
    var captureScale: Double?
    var edit = Edit()
    var revision = 0

    enum Axis: String, Codable, CaseIterable, Sendable {
        case vertical, horizontal
    }

    struct Piece: Codable, Equatable, Sendable {
        let raster: String
        var source: CGRect
        var origin: CGPoint
        var reflection: CaptureReflection?
        var bounds: CGRect { CGRect(origin: origin, size: source.size) }
    }

    struct Edit: Codable, Equatable, Sendable {
        var annotations: [CaptureAnnotation] = []
        var crop: CGRect?
        var adjustments: CaptureImageAdjustments?
        var imageLayers: [CaptureImageLayer]?
        var presentation: CapturePresentation?
        var translation: CaptureTranslation?
        var isEmpty: Bool {
            annotations.isEmpty && crop == nil && (adjustments?.isIdentity ?? true)
                && (imageLayers?.isEmpty ?? true) && presentation == nil && translation == nil
        }
    }

    var bounds: CGRect { CGRect(x: 0, y: 0, width: size.width, height: size.height) }
    var contentBounds: CGRect { edit.crop ?? bounds }
    var outputBounds: CGRect { edit.presentation?.bounds(for: contentBounds) ?? contentBounds }
    var needsPreservation: Bool { !edit.isEmpty || pieces.count > 1 || pieces.contains { $0.reflection != nil } }

    func validated() throws -> Self {
        guard !pieces.isEmpty || !imageLayers.isEmpty && axis == nil, pieces.count <= 1000, revision >= 0,
            captureScale.map({ $0.isFinite && (0.1...8).contains($0) }) ?? true,
            createdAt.timeIntervalSince1970.isFinite,
            pieces.allSatisfy({ piece in
                UUID(uuidString: piece.raster) != nil && CaptureGeometry.valid(piece.source)
                    && piece.source == piece.source.integral && piece.bounds == piece.bounds.integral
                    && bounds.contains(piece.bounds) && piece.source.minX >= 0 && piece.source.minY >= 0
            }),
            edit.crop.map({ CaptureGeometry.valid($0) && $0 == $0.integral && bounds.contains($0) }) ?? true,
            edit.adjustments?.isValid ?? true,
            edit.presentation?.isValid ?? true,
            edit.translation?.isValid ?? true,
            imageLayers.count <= 32, imageLayers.allSatisfy(\.isValid),
            Set(imageLayers.map(\.id)).count == imageLayers.count,
            Set(imageLayers.map(\.id)).isDisjoint(with: edit.annotations.map(\.id)),
            imageLayers.reduce(0.0, { $0 + $1.source.width * $1.source.height }) <= 64_000_000,
            edit.annotations.count <= 1000,
            Set(edit.annotations.map(\.id)).count == edit.annotations.count,
            edit.annotations.allSatisfy(\.isValid)
        else { throw CaptureRasterError.invalidTile }
        _ = try CapturePixelSize(width: Int(outputBounds.width), height: Int(outputBounds.height))
        var edge: CGFloat = 0
        for piece in pieces {
            if axis == .horizontal {
                guard piece.origin == CGPoint(x: edge, y: 0), piece.source.height == bounds.height else {
                    throw CaptureRasterError.invalidTile
                }
                edge += piece.source.width
            } else {
                guard piece.origin == CGPoint(x: 0, y: edge), piece.source.width == bounds.width else {
                    throw CaptureRasterError.invalidTile
                }
                edge += piece.source.height
            }
        }
        guard pieces.isEmpty || edge == (axis == .horizontal ? bounds.width : bounds.height) else {
            throw CaptureRasterError.invalidTile
        }
        return self
    }

    var imageLayers: [CaptureImageLayer] { edit.imageLayers ?? [] }
    var rasterRegions: [(raster: String, source: CGRect)] {
        pieces.map { ($0.raster, $0.source) } + imageLayers.flatMap(\.rasterRegions)
    }
}
