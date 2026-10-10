import Foundation

struct CaptureImageLayer: Codable, Equatable, Sendable, Identifiable {
    let id: UUID
    let raster: String
    let source: CGRect
    var frame: CGRect
    var opacity = 1.0
    var rotation = 0.0
    var reflection: CaptureReflection?
    var backgroundMask: Mask?

    struct Mask: Codable, Equatable, Sendable {
        let raster: String
        let size: CapturePixelSize
        var enabled = true
        var bounds: CGRect { CGRect(x: 0, y: 0, width: size.width, height: size.height) }
        var isValid: Bool { UUID(uuidString: raster) != nil && size.width <= 1024 && size.height <= 1024 }
    }

    var rasterRegions: [(raster: String, source: CGRect)] {
        [(raster, source)] + (backgroundMask.map { [($0.raster, $0.bounds)] } ?? [])
    }

    var isValid: Bool {
        UUID(uuidString: raster) != nil && CaptureGeometry.valid(source) && source == source.integral
            && source.minX >= 0 && source.minY >= 0
            && source.maxX <= 30_000 && source.maxY <= 30_000
            && source.width * source.height <= 64_000_000
            && CaptureGeometry.valid(frame) && frame.width >= 1 && frame.height >= 1
            && abs(frame.minX) <= 30_000 && abs(frame.minY) <= 30_000
            && frame.width <= 30_000 && frame.height <= 30_000
            && opacity.isFinite && (0...1).contains(opacity)
            && rotation.isFinite && (-180...180).contains(rotation)
            && (backgroundMask?.isValid ?? true)
    }

    var bounds: CGRect {
        let angle = rotation * .pi / 180
        let width = abs(cos(angle)) * frame.width + abs(sin(angle)) * frame.height
        let height = abs(sin(angle)) * frame.width + abs(cos(angle)) * frame.height
        return CGRect(x: frame.midX - width / 2, y: frame.midY - height / 2, width: width, height: height)
    }

    static func placed(id: UUID, raster: String, size: CapturePixelSize, in bounds: CGRect) -> Self {
        let scale = min(1, min(bounds.width * 0.6 / CGFloat(size.width), bounds.height * 0.6 / CGFloat(size.height)))
        let width = max(1, CGFloat(size.width) * scale), height = max(1, CGFloat(size.height) * scale)
        return Self(id: id, raster: raster,
            source: CGRect(x: 0, y: 0, width: size.width, height: size.height),
            frame: CGRect(x: bounds.midX - width / 2, y: bounds.midY - height / 2, width: width, height: height))
    }
}
