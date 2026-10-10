import Foundation

enum ScrollStitchPolicy {
    struct Frame: Sendable {
        let length: Int
        let lanes: Int
        let rgb: [UInt8]

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
        var leading = 0, trailing = 0
        while leading < limit,
            current.difference(to: previous, shift: 0, start: leading, end: leading + 1, stride: 1) < 1.2
        {
            leading += 1
        }
        while trailing < limit,
            current.difference(
                to: previous, shift: 0, start: length - trailing - 1, end: length - trailing, stride: 1) < 1.2
        {
            trailing += 1
        }
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
        guard let best = candidates.first, best.1 < 5,
            let alternative = candidates.first(where: { abs($0.0 - best.0) > 3 }),
            alternative.1 > best.1 * 1.8 + 1.5
        else { return .uncertain }
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

    static func stable(_ first: Frame, _ second: Frame) -> Bool {
        first.length == second.length && first.lanes == second.lanes && first.rgb.count == second.rgb.count
            && second.difference(to: first, shift: 0, start: 0, end: second.length, stride: 1) < 0.8
    }
}
