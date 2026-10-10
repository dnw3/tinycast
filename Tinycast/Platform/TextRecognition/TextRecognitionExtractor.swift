import Foundation
import ImageIO
import PDFKit
import Vision

nonisolated enum TextRecognitionExtractor {
    static let maximumTextBytes = 32_000
    private static let maximumFileBytes = 32_000_000
    private static let maximumPages = 64
    private static let maximumDimension = 4096
    private static let maximumPixels = 2048 * 2048
    private static let stripHeight = 2048
    /// Taller than any line of text, so every line lies whole inside at least one strip.
    private static let stripOverlap = 256

    enum Failure: Error { case unreadable }

    static func capture(at url: URL) async throws -> TextRecognitionResult {
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard (1...1_048_576).contains(size) else { throw Failure.unreadable }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let data = try handle.read(upToCount: 1_048_577) ?? Data()
        guard data.count <= 1_048_576 else { throw Failure.unreadable }
        let request = try JSONDecoder().decode(TextRecognitionResult.Request.self, from: data)
        guard request.tiles.count <= 1024 else { throw Failure.unreadable }
        var result = TextRecognitionResult(
            requestID: request.requestID, revision: request.revision, boxes: [], truncated: false)
        for tile in request.tiles {
            try Task.checkCancellation()
            guard !tile.filename.contains("/"), tile.filename.hasSuffix(".png"),
                tile.rect.origin.x.isFinite, tile.rect.origin.y.isFinite,
                tile.rect.minX >= -320, tile.rect.minY >= -320,
                tile.rect.maxX <= 30_000, tile.rect.maxY <= 30_000,
                tile.rect.width > 0, tile.rect.height > 0,
                let source = CGImageSourceCreateWithURL(
                    url.deletingLastPathComponent().appendingPathComponent(tile.filename) as CFURL, nil),
                let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
                let width = properties[kCGImagePropertyPixelWidth] as? Int,
                let height = properties[kCGImagePropertyPixelHeight] as? Int,
                (1...1024).contains(width), (1...1024).contains(height),
                request.content != .text
                    ? abs(CGFloat(width) * tile.rect.height - CGFloat(height) * tile.rect.width)
                        <= max(tile.rect.width, tile.rect.height)
                    : CGFloat(width) == tile.rect.width && CGFloat(height) == tile.rect.height,
                let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
            else { throw Failure.unreadable }
            let boxes = try await captureBoxes(image, content: request.content, size: tile.rect.size)
            let readingRange = tile.readingRange(among: request.tiles)
            for box in boxes {
                let rect = box.rect.offsetBy(dx: tile.rect.minX, dy: tile.rect.minY)
                guard request.content != .text || readingRange.contains(rect.midY) else { continue }
                result.append(.init(text: box.text, rect: rect), mergingTextFragments: request.content == .text)
                if result.truncated {
                    result.orderForReading()
                    return result
                }
            }
        }
        result.orderForReading()
        return result
    }

    private static func captureBoxes(
        _ image: CGImage, content: TextRecognitionResult.Content, size: CGSize
    ) async throws -> [TextRecognitionResult.Box] {
        switch content {
        case .text:
            var recognition = RecognizeTextRequest()
            recognition.recognitionLevel = .accurate
            recognition.minimumTextHeightFraction = 0
            recognition.automaticallyDetectsLanguage = true
            let observations = try await recognition.perform(on: image)
            return observations.compactMap { observation in
                guard let text = observation.topCandidates(1).first?.string else { return nil }
                return .init(text: text, rect: observation.boundingBox.toImageCoordinates(size, origin: .upperLeft))
            }
        case .qr:
            var recognition = DetectBarcodesRequest()
            recognition.symbologies = [.qr, .microQR]
            let observations = try await recognition.perform(on: image)
            return observations.compactMap { observation in
                guard let text = observation.payloadString else { return nil }
                return .init(text: text, rect: observation.boundingBox.toImageCoordinates(size, origin: .upperLeft))
            }
        case .faces:
            let observations = try await DetectFaceRectanglesRequest().perform(on: image)
            return observations.map {
                .init(text: "Face", rect: $0.boundingBox.toImageCoordinates(size, origin: .upperLeft))
            }
        case .people:
            var recognition = DetectHumanRectanglesRequest()
            recognition.upperBodyOnly = false
            let observations = try await recognition.perform(on: image)
            return observations.map {
                .init(text: "Person", rect: $0.boundingBox.toImageCoordinates(size, origin: .upperLeft))
            }
        }
    }

    static func extract(at url: URL, isPDF: Bool) async throws -> String {
        try Task.checkCancellation()
        let values = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
        guard values.isRegularFile == true, let size = values.fileSize,
            size <= maximumFileBytes
        else { return "" }
        if isPDF { return try await extractPDF(url) }
        guard let image = autoreleasepool(invoking: { image(at: url) }) else { throw Failure.unreadable }
        return bounded(try await recognize(image))
    }

    private static func image(at url: URL) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
            let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
            let width = properties[kCGImagePropertyPixelWidth] as? Double,
            let height = properties[kCGImagePropertyPixelHeight] as? Double,
            width.isFinite, height.isFinite, width > 0, height > 0
        else { return nil }
        let scale = min(1, sqrt(Double(maximumPixels) / width / height))
        let dimension = Int(min(Double(maximumDimension), max(1, max(width, height) * scale)))
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: dimension,
            kCGImageSourceShouldCacheImmediately: true
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    /// Full-width strips, so no line is cut across columns and the text keeps its reading order.
    private static func recognize(_ image: CGImage) async throws -> String {
        var text = ""
        for top in stride(from: 0, to: max(1, image.height - stripOverlap), by: stripHeight - stripOverlap) {
            try Task.checkCancellation()
            let height = min(stripHeight, image.height - top)
            let rect = CGRect(x: 0, y: top, width: image.width, height: height)
            guard let strip = image.cropping(to: rect) else { continue }
            let owned = ownedRows(isFirst: top == 0, isLast: top + height == image.height, height: height)
            let content = try await recognizeStrip(strip, keepingCentresIn: owned)
            if !text.isEmpty, !content.isEmpty { text += "\n" }
            text += bounded(content, bytes: maximumTextBytes - text.utf8.count)
            if text.utf8.count >= maximumTextBytes - 4 { return text }
        }
        return text
    }

    /// Adjacent strips split their overlap down the middle, so a line there is kept exactly once.
    private static func ownedRows(isFirst: Bool, isLast: Bool, height: Int) -> Range<Double> {
        let lower = isFirst ? -.infinity : Double(stripOverlap / 2)
        let upper = isLast ? .infinity : Double(height - stripOverlap / 2)
        return lower..<upper
    }

    private static func recognizeStrip(
        _ strip: CGImage, keepingCentresIn rows: Range<Double>
    ) async throws -> String {
        try Task.checkCancellation()
        var request = RecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.minimumTextHeightFraction = 0
        request.automaticallyDetectsLanguage = true
        let observations = try await request.perform(on: strip)
        try Task.checkCancellation()
        let size = CGSize(width: strip.width, height: strip.height)
        return
            observations
            .filter { rows.contains($0.boundingBox.toImageCoordinates(size, origin: .upperLeft).midY) }
            .compactMap { $0.topCandidates(1).first?.string }
            .joined(separator: "\n")
    }

    private static func extractPDF(_ url: URL) async throws -> String {
        guard let document = PDFDocument(url: url), !document.isLocked else {
            throw Failure.unreadable
        }
        var text = ""
        for index in 0..<min(document.pageCount, maximumPages) {
            try Task.checkCancellation()
            guard let page = document.page(at: index) else { continue }
            var content = autoreleasepool { page.string ?? "" }
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if content.isEmpty, let image = autoreleasepool(invoking: { render(page) }) {
                content = try await recognize(image)
            }
            if !text.isEmpty, !content.isEmpty { text += "\n" }
            text += bounded(content, bytes: maximumTextBytes - text.utf8.count)
            if text.utf8.count >= maximumTextBytes - 4 { break }
        }
        return text
    }

    private static func render(_ page: PDFPage) -> CGImage? {
        guard let reference = page.pageRef else { return nil }
        let bounds = page.bounds(for: .mediaBox)
        guard bounds.width.isFinite, bounds.height.isFinite,
            bounds.width > 0, bounds.height > 0
        else { return nil }
        let scale = min(
            2, CGFloat(maximumDimension) / max(bounds.width, bounds.height),
            sqrt(CGFloat(maximumPixels) / bounds.width / bounds.height))
        let width = max(1, Int(bounds.width * scale))
        let height = max(1, Int(bounds.height * scale))
        guard
            let context = CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
        else { return nil }
        let rect = CGRect(x: 0, y: 0, width: width, height: height)
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(rect)
        context.concatenate(
            reference.getDrawingTransform(
                .mediaBox, rect: rect, rotate: 0, preserveAspectRatio: true))
        context.drawPDFPage(reference)
        return context.makeImage()
    }

    private static func bounded(_ text: String, bytes: Int = maximumTextBytes) -> String {
        var prefix = text.utf8.prefix(max(0, bytes))
        while !prefix.isEmpty, String(bytes: prefix, encoding: .utf8) == nil {
            prefix = prefix.dropLast()
        }
        return String(bytes: prefix, encoding: .utf8) ?? ""
    }
}
