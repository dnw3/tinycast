import Foundation

struct CaptureExportOptions: Equatable, Sendable {
    enum Format: String, CaseIterable, Sendable {
        case png, jpeg, heic, avif, webp
        var title: String { self == .webp ? "WebP" : rawValue.uppercased() }
        var identifier: String {
            switch self {
            case .png: "public.png"
            case .jpeg: "public.jpeg"
            case .heic: "public.heic"
            case .avif: "public.avif"
            case .webp: "org.webmproject.webp"
            }
        }
    }

    enum Scale: String, CaseIterable, Sendable {
        case original, oneX, half, quarter
        var title: String {
            switch self {
            case .original: "Original pixels"
            case .oneX: "1×"
            case .half: "50%"
            case .quarter: "25%"
            }
        }
    }

    enum Profile: String, CaseIterable, Sendable {
        case sRGB, displayP3
        var title: String { self == .sRGB ? "sRGB" : "Display P3" }
    }

    enum WebPCompression: String, CaseIterable, Sendable {
        case lossless, lossy
        var title: String { self == .lossless ? "Lossless" : "Lossy" }
    }

    var format: Format = .png
    var scale: Scale = .original
    var quality = 0.92
    var profile: Profile = .sRGB
    var webPCompression: WebPCompression = .lossless

    var showsQuality: Bool { format != .png && (format != .webp || webPCompression == .lossy) }

    func validatedDimensions(for document: CaptureDocument) throws -> CapturePixelSize {
        guard quality.isFinite, (0...1).contains(quality) else { throw Failure.quality }
        let size = try dimensions(for: document)
        if format == .webp, max(size.width, size.height) > 16_383 { throw Failure.webPDimensions }
        if !(format == .png && scale == .original && profile == .sRGB), size.width * size.height > 4_000_000 {
            throw Failure.encodingBudget
        }
        return size
    }

    enum Failure: LocalizedError {
        case encodingBudget, webPDimensions, quality
        var errorDescription: String? {
            switch self {
            case .encodingBudget: "Choose original-size PNG in sRGB, or reduce the export size to 4 million pixels."
            case .webPDimensions: "WebP supports up to 16,383 pixels per side. Choose PNG, or reduce the export size."
            case .quality: "Choose an export quality between 0 and 100%."
            }
        }
    }

    func dimensions(for document: CaptureDocument) throws -> CapturePixelSize {
        let factor: Double = switch scale {
        case .original: 1
        case .oneX: min(1, 1 / (document.captureScale ?? 1))
        case .half: 0.5
        case .quarter: 0.25
        }
        guard factor.isFinite, factor > 0, CaptureGeometry.valid(document.outputBounds),
            document.bounds.contains(document.outputBounds)
        else { throw CaptureRasterError.invalidSize }
        return try CapturePixelSize(
            width: max(1, Int(document.outputBounds.width * factor)),
            height: max(1, Int(document.outputBounds.height * factor)))
    }
}
