import Foundation

struct CaptureTextStyle: Codable, Equatable, Sendable {
    enum Alignment: String, Codable, CaseIterable, Sendable {
        case left, center, right
        var title: String { rawValue.capitalized }
    }

    var font: CaptureAnnotation.Font = .system
    var size = 24.0
    var color = CaptureColor(red: 0, green: 0, blue: 0)
    var bold = false
    var italic = false
    var underline = false
    var strikethrough = false
    var alignment: Alignment = .left
    var background: CaptureColor?
    var outline: CaptureColor?
    var outlineWidth = 2.0

    var isValid: Bool {
        size.isFinite && (6...768).contains(size)
            && outlineWidth.isFinite && (0.1...20).contains(outlineWidth)
    }

    mutating func apply(_ change: CaptureTextChange) {
        switch change {
        case let .font(value): font = value
        case let .size(value): size = value
        case let .color(value): color = value
        case let .bold(value): bold = value
        case let .italic(value): italic = value
        case let .underline(value): underline = value
        case let .strikethrough(value): strikethrough = value
        case let .alignment(value): alignment = value
        case let .background(value): background = value
        case let .outline(value): outline = value
        }
    }
}

enum CaptureTextChange: Sendable {
    case font(CaptureAnnotation.Font), size(Double), color(CaptureColor)
    case bold(Bool), italic(Bool), underline(Bool), strikethrough(Bool)
    case alignment(CaptureTextStyle.Alignment), background(CaptureColor?), outline(CaptureColor?)
}

struct CaptureTextFormat: Codable, Equatable, Sendable {
    struct Run: Codable, Equatable, Sendable {
        var location: Int
        var length: Int
        var style: CaptureTextStyle
        var range: NSRange { NSRange(location: location, length: length) }
    }

    var base: CaptureTextStyle
    var runs: [Run] = []

    func isValid(for text: String) -> Bool {
        guard base.isValid, runs.count <= 512 else { return false }
        let count = text.utf16.count
        let boundaries = Self.boundaries(in: text)
        var end = 0
        for run in runs {
            guard run.style.isValid, run.location >= end, run.length > 0, run.location <= count,
                run.length <= count - run.location, boundaries.contains(run.location),
                boundaries.contains(run.location + run.length)
            else { return false }
            end = run.location + run.length
        }
        return true
    }

    func style(at offset: Int) -> CaptureTextStyle {
        runs.first { offset >= $0.location && offset - $0.location < $0.length }?.style ?? base
    }

    mutating func apply(_ change: CaptureTextChange, to range: NSRange, in text: String) -> Bool {
        let count = text.utf16.count, boundaries = Self.boundaries(in: text)
        guard isValid(for: text), range.location >= 0, range.length > 0, range.location <= count,
            range.length <= count - range.location, boundaries.contains(range.location),
            boundaries.contains(range.location + range.length)
        else { return false }
        let end = range.location + range.length
        let splits = Set([0, count, range.location, end] + runs.flatMap { [$0.location, $0.location + $0.length] }).sorted()
        var replacement: [Run] = []
        for (start, finish) in zip(splits, splits.dropFirst()) where finish > start {
            var style = style(at: start)
            if start >= range.location && start < end { style.apply(change) }
            guard style.isValid else { return false }
            if let last = replacement.last, last.style == style {
                replacement[replacement.count - 1].length += finish - start
            } else { replacement.append(Run(location: start, length: finish - start, style: style)) }
        }
        guard replacement.count <= 512 else { return false }
        if range.location == 0, end == count { base.apply(change) }
        runs = replacement.filter { $0.style != base }
        return true
    }

    static func boundaries(in text: String) -> Set<Int> {
        Set(text.indices.map { $0.utf16Offset(in: text) } + [text.utf16.count])
    }
}
