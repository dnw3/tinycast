import Foundation

enum ScrollStitchPolicy {
    struct Frame: Sendable {
        let length: Int
        let lanes: Int
        let rgb: [UInt8]
        var originalRGB: [UInt8]?

        func difference(
            to other: Frame, shift: Int, start: Int, end: Int, stride step: Int, textured: Bool = false,
            selectedLanes: Range<Int>? = nil
        ) -> Double {
            var sum = 0, count = 0
            for line in Swift.stride(from: start, to: end, by: step) {
                let previous = line + shift
                guard (0..<length).contains(previous) else { continue }
                for lane in selectedLanes ?? 0..<lanes {
                    if textured, lane > 0 {
                        let here = (line * lanes + lane) * 3
                        let there = (previous * lanes + lane) * 3
                        let contrast = (0..<3).reduce(0) {
                            $0 + abs(Int(rgb[here + $1]) - Int(rgb[here + $1 - 3]))
                                + abs(Int(other.rgb[there + $1]) - Int(other.rgb[there + $1 - 3]))
                        }
                        if contrast < 48 { continue }
                    }
                    for channel in 0..<3 {
                        let index = (line * lanes + lane) * 3 + channel
                        let previousIndex = (previous * lanes + lane) * 3 + channel
                        sum += abs(Int(rgb[index]) - Int(other.rgb[previousIndex]))
                        count += 1
                    }
                }
            }
            return count == 0 ? 255 : Double(sum) / Double(count)
        }
    }

    enum Decision: Equatable, Sendable {
        case duplicate
        case append(offset: Int, fixedLeading: Int, fixedTrailing: Int)
        case reverse
        case uncertain
    }

    static func match(previous: Frame, current: Frame) -> Decision {
        guard previous.length == current.length, previous.lanes == current.lanes,
            current.length >= 40, current.lanes > 0,
            current.rgb.count == current.length * current.lanes * 3,
            previous.rgb.count == current.rgb.count
        else { return .uncertain }
        let length = current.length
        if current.difference(to: previous, shift: 0, start: 0, end: length, stride: 2) < 0.8 {
            return .duplicate
        }
        let limit = length / 4
        let originalPrevious = Frame(length: previous.length, lanes: previous.lanes,
            rgb: previous.originalRGB ?? previous.rgb)
        let originalCurrent = Frame(length: current.length, lanes: current.lanes,
            rgb: current.originalRGB ?? current.rgb)
        var leading = 0, trailing = 0
        while leading < limit,
            originalCurrent.difference(to: originalPrevious,
                shift: 0, start: leading, end: leading + 1, stride: 1) < 1.2
        {
            leading += 1
        }
        while trailing < limit,
            originalCurrent.difference(to: originalPrevious,
                shift: 0, start: length - trailing - 1, end: length - trailing, stride: 1) < 1.2
        {
            trailing += 1
        }
        if !distinctEdge(originalCurrent, start: 0, end: leading) { leading = 0 }
        if !distinctEdge(originalCurrent, start: length - trailing, end: length) { trailing = 0 }
        let start = leading + 4, end = length - trailing - 4
        guard end - start > length / 2 else { return .uncertain }
        var candidates: [(Int, Double)] = []
        let maximum = (end - start) * 2 / 3
        for shift in -maximum...maximum where abs(shift) >= 2 {
            let lower = max(start, start - shift), upper = min(end, end - shift)
            let score = current.difference(
                to: previous, shift: shift, start: lower, end: upper,
                stride: max(1, (upper - lower) / 40), textured: true)
            candidates.append((shift, score))
        }
        candidates.sort { $0.1 < $1.1 }
        candidates = candidates.prefix(32).map { candidate in
            let lower = max(start, start - candidate.0), upper = min(end, end - candidate.0)
            return (candidate.0, current.difference(to: previous, shift: candidate.0,
                start: lower, end: upper, stride: 1, textured: true))
        }.sorted { $0.1 < $1.1 }
        guard let best = candidates.first, best.1 < 5 else { return .uncertain }
        let bestError = patchError(previous: previous, current: current,
            shift: best.0, start: start, end: end)
        let alternatives = candidates.prefix(32).filter { abs($0.0 - best.0) > 3 }
        guard !alternatives.isEmpty, alternatives.allSatisfy({ candidate in
            patchError(previous: previous, current: current, shift: candidate.0, start: start, end: end)
                > bestError * 1.8 + 1.5
        }) else { return .uncertain }
        let lower = max(start, start - best.0), upper = min(end, end - best.0)
        guard
            (0..<current.lanes).allSatisfy({ lane in
                current.difference(
                    to: previous, shift: best.0, start: lower, end: upper, stride: 1,
                    selectedLanes: lane..<(lane + 1)) < 5
            })
        else {
            return .uncertain
        }
        return best.0 > 0 ? .append(offset: best.0, fixedLeading: leading, fixedTrailing: trailing) : .reverse
    }

    private static func patchError(previous: Frame, current: Frame, shift: Int, start: Int, end: Int) -> Double {
        let lower = max(start, start - shift), upper = min(end, end - shift)
        var maximum = 0.0
        for line in stride(from: lower, to: upper, by: 16) {
            for lane in 0..<current.lanes {
                maximum = max(maximum, current.difference(to: previous, shift: shift,
                    start: line, end: min(upper, line + 32), stride: 1, selectedLanes: lane..<(lane + 1)))
            }
        }
        return maximum
    }

    private static func distinctEdge(_ frame: Frame, start: Int, end: Int) -> Bool {
        guard start < end else { return false }
        let first = (start * frame.lanes) * 3
        for index in stride(from: first, to: end * frame.lanes * 3, by: 3) {
            let contrast = (0..<3).reduce(0) { $0 + abs(Int(frame.rgb[index + $1]) - Int(frame.rgb[first + $1])) }
            if contrast >= 48 { return true }
        }
        var difference = 0
        for channel in 0..<3 {
            let values = stride(from: channel, to: frame.rgb.count, by: 3).map { frame.rgb[$0] }.sorted()
            difference += abs(Int(frame.rgb[first + channel]) - Int(values[values.count / 2]))
        }
        return difference >= 15
    }

    static func stable(_ first: Frame, _ second: Frame) -> Bool {
        first.length == second.length && first.lanes == second.lanes && first.rgb.count == second.rgb.count
            && second.difference(to: first, shift: 0, start: 0, end: second.length, stride: 1) < 0.8
    }
}
