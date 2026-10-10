import Foundation

struct CaptureVideoTimeline: Sendable {
    struct Segment: Sendable {
        let sourceStart: Double
        let sourceEnd: Double
        let outputStart: Double
        let duration: Double
        let hold: Bool
    }

    let segments: [Segment]
    var duration: Double { segments.last.map { $0.outputStart + $0.duration } ?? 0 }

    init(_ edit: CaptureVideoEdit) {
        var ranges: [CaptureVideoEdit.Range] = []
        var cursor = edit.start
        for cut in edit.cuts.sorted(by: { $0.start < $1.start }) {
            let end = min(edit.end, cut.start)
            if end > cursor { ranges.append(.init(start: cursor, end: end)) }
            cursor = max(cursor, cut.end)
        }
        if cursor < edit.end { ranges.append(.init(start: cursor, end: edit.end)) }
        var result: [Segment] = []
        var output = 0.0
        func append(start: Double, end: Double, duration: Double, hold: Bool) {
            guard duration > 0 else { return }
            result.append(Segment(sourceStart: start, sourceEnd: end,
                outputStart: output, duration: duration, hold: hold))
            output += duration
        }
        for range in ranges {
            cursor = range.start
            for hold in edit.holds.sorted(by: { $0.position < $1.position })
                where hold.position >= range.start && hold.position < range.end
            {
                append(start: cursor, end: hold.position, duration: (hold.position - cursor) / edit.speed, hold: false)
                append(start: hold.position, end: min(range.end, hold.position + 1 / 600.0),
                    duration: hold.duration, hold: true)
                cursor = hold.position
            }
            append(start: cursor, end: range.end, duration: (range.end - cursor) / edit.speed, hold: false)
        }
        segments = result
    }

    func sourceTime(at output: Double) -> Double? {
        guard output.isFinite, output >= 0, output < duration,
            let segment = segments.first(where: { output < $0.outputStart + $0.duration }) else { return nil }
        if segment.hold { return segment.sourceStart }
        return segment.sourceStart + (output - segment.outputStart) / segment.duration
            * (segment.sourceEnd - segment.sourceStart)
    }

    func outputTime(at source: Double) -> Double {
        guard source.isFinite else { return 0 }
        for segment in segments {
            if source <= segment.sourceStart { return segment.outputStart }
            if source < segment.sourceEnd {
                return segment.outputStart + (source - segment.sourceStart)
                    / (segment.sourceEnd - segment.sourceStart) * segment.duration
            }
        }
        return max(0, duration - 1 / 600.0)
    }
}
