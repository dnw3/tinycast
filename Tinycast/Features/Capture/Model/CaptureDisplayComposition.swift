import Foundation

enum CaptureDisplayComposition {
    struct Display: Sendable {
        let id: UInt32
        let frame: CGRect
        let scale: CGFloat
    }

    struct Slice: Sendable {
        let displayID: UInt32
        let source: CGRect
        let frame: CGRect
    }

    struct Layout: Sendable {
        let size: CapturePixelSize
        let scale: CGFloat
        let slices: [Slice]
    }

    static func layout(region: CGRect, displays: [Display]) throws -> Layout {
        guard CaptureGeometry.valid(region), !displays.isEmpty, displays.count <= 32,
            Set(displays.map(\.id)).count == displays.count,
            displays.allSatisfy({ CaptureGeometry.valid($0.frame) && $0.scale.isFinite && (0.1...8).contains($0.scale) })
        else { throw CaptureRasterError.invalidSize }
        let selected = displays.filter { CaptureGeometry.valid($0.frame.intersection(region)) }
        guard let scale = selected.map(\.scale).max() else { throw CaptureRasterError.invalidSize }
        guard region.width * scale <= 30_000, region.height * scale <= 30_000 else {
            throw CaptureRasterError.invalidSize
        }
        let size = try CapturePixelSize(width: Int(ceil(region.width * scale)), height: Int(ceil(region.height * scale)))
        let slices = selected.compactMap { display -> Slice? in
            guard let pixels = CaptureGeometry.pixels(region, screen: display.frame, scale: display.scale) else { return nil }
            let frame = CaptureSelectionGeometry.frame(pixels: pixels, in: display.frame, scale: display.scale)
            return Slice(displayID: display.id, source: pixels, frame: CGRect(
                x: (frame.minX - region.minX) * scale, y: (region.maxY - frame.maxY) * scale,
                width: frame.width * scale, height: frame.height * scale))
        }
        guard slices.reduce(0.0, { $0 + $1.source.width * $1.source.height }) <= 64_000_000 else {
            throw CaptureRasterError.invalidSize
        }
        return Layout(size: size, scale: scale, slices: slices)
    }
}
