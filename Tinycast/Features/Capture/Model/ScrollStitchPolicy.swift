import Foundation

enum ScrollStitchPolicy {
    struct Frame: Sendable {
        let length: Int
        let lanes: Int
        let rgb: [UInt8]
        var originalRGB: [UInt8]?
        /// Where the pointer was along the scroll axis, when it was over the region.
        var pointer: Int?

        /// Lines a hover may have changed: whatever is under the pointer lights as content passes.
        func nearPointer(_ start: Int, _ end: Int) -> Bool {
            guard let pointer else { return false }
            return start < pointer + ScrollStitchPolicy.hoverReach && end > pointer - ScrollStitchPolicy.hoverReach
        }

        func difference(
            to other: Frame, shift: Int, start: Int, end: Int, stride step: Int, textured: Bool = false,
            selectedLanes: [Int]? = nil
        ) -> Double {
            var sum = 0, count = 0
            for line in Swift.stride(from: start, to: end, by: step) {
                let previous = line + shift
                guard (0..<length).contains(previous) else { continue }
                for lane in selectedLanes ?? Array(0..<lanes) {
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

        /// Summed channel difference of one lane between a line here and a line in another frame.
        func distance(to other: Frame, lane: Int, line: Int, previous: Int) -> Int {
            let here = (line * lanes + lane) * 3, there = (previous * other.lanes + lane) * 3
            return (0..<3).reduce(0) { $0 + abs(Int(rgb[here + $1]) - Int(other.rgb[there + $1])) }
        }

        /// The widest swing of any channel along one lane, so a blank stretch can be told apart.
        func activity(lane: Int, start: Int, end: Int) -> Int {
            let lower = max(0, start), upper = min(length, end)
            guard lower < upper else { return 0 }
            var minimum = [255, 255, 255], maximum = [0, 0, 0]
            for line in lower..<upper {
                for channel in 0..<3 {
                    let value = Int(rgb[(line * lanes + lane) * 3 + channel])
                    minimum[channel] = min(minimum[channel], value)
                    maximum[channel] = max(maximum[channel], value)
                }
            }
            return (0..<3).map { maximum[$0] - minimum[$0] }.max() ?? 0
        }
    }

    /// About 48pt either side at 2×: a hovered row's highlight, and controls beside the pointer.
    static let hoverReach = 96

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
        // A sidebar matches best at no shift at all, so it would pull the search toward a tiny one.
        let moving = (0..<current.lanes).filter {
            current.difference(to: previous, shift: 0, start: start, end: end, stride: 2, selectedLanes: [$0]) >= 0.8
        }
        var candidates: [(Int, Double)] = []
        let maximum = (end - start) * 2 / 3
        for shift in -maximum...maximum where abs(shift) >= 2 {
            let lower = max(start, start - shift), upper = min(end, end - shift)
            let score = current.difference(
                to: previous, shift: shift, start: lower, end: upper,
                stride: max(1, (upper - lower) / 40), textured: true, selectedLanes: moving)
            candidates.append((shift, score))
        }
        candidates.sort { $0.1 < $1.1 }
        candidates = candidates.prefix(32).map { candidate in
            let lower = max(start, start - candidate.0), upper = min(end, end - candidate.0)
            return (candidate.0, current.difference(to: previous, shift: candidate.0,
                start: lower, end: upper, stride: 1, textured: true, selectedLanes: moving))
        }.sorted { $0.1 < $1.1 }
        // At the end of the search range the true shift may lie just beyond it, one line off.
        guard let best = candidates.first, abs(best.0) < maximum else { return .uncertain }
        let fit = fit(previous: previous, current: current, shift: best.0, start: start, end: end)
        guard fit.consistent, fit.error < 8 else { return .uncertain }
        let alternatives = candidates.prefix(32).filter { abs($0.0 - best.0) > 3 }
        guard !alternatives.isEmpty, alternatives.allSatisfy({ candidate in
            patchError(previous: previous, current: current, shift: candidate.0, start: start, end: end)
                > fit.error * 1.8 + 1.5
        }) else { return .uncertain }
        return best.0 > 0
            ? .append(offset: best.0, fixedLeading: leading, fixedTrailing: max(trailing, fit.unsettled))
            : .reverse
    }

    private enum Window {
        case moved(Double)
        /// Lines up only where it sits still on screen: a sidebar, floating button or edge fade.
        case held
        case edge(Double)
    }

    /// Strict wherever the page moved, except under the pointer, where a hover changes content in place.
    private static func fit(
        previous: Frame, current: Frame, shift: Int, start: Int, end: Int
    ) -> (error: Double, consistent: Bool, unsettled: Int) {
        let lower = max(start, start - shift), upper = min(end, end - shift)
        let lines = Array(stride(from: lower, to: upper, by: 16))
        var windows = [[Window?]](repeating: [Window?](repeating: nil, count: current.lanes), count: lines.count)
        for (row, line) in lines.enumerated() {
            let window = min(upper, line + 32)
            guard !current.nearPointer(line, window), !previous.nearPointer(line + shift, window + shift)
            else { continue }
            for lane in 0..<current.lanes {
                // Blank windows match at any shift; on a sparse page they would hide a line's slip.
                guard current.activity(lane: lane, start: line, end: window) >= 16
                    || previous.activity(lane: lane, start: line + shift, end: window + shift) >= 16
                else { continue }
                var moved = 0, stillHere = 0, stillThere = 0, best = 0
                for line in line..<window {
                    let along = current.distance(to: previous, lane: lane, line: line, previous: line + shift)
                    // Something still on screen shows at the same line in both frames, on either side.
                    let here = current.distance(to: previous, lane: lane, line: line, previous: line)
                    let there = current.distance(to: previous, lane: lane, line: line + shift, previous: line + shift)
                    moved += along
                    stillHere += here
                    stillThere += there
                    best += min(along, here, there)
                }
                let count = Double((window - line) * 3)
                let error = Double(moved) / count, still = Double(min(stillHere, stillThere)) / count
                // Sparse text on a sidebar misses by little, so still has only to explain it better.
                windows[row][lane] =
                    error <= 4 ? .moved(error)
                    : still <= 12 && still < error ? .held
                    : error <= 12 ? .moved(error)
                    : Double(best) / count <= 12 ? .edge(error) : .moved(error)
            }
        }
        // A window part still, part moving is only the rim of something that sits still beside it.
        let solid = windows
        for row in windows.indices {
            for lane in 0..<current.lanes {
                guard case .edge(let error) = windows[row][lane] else { continue }
                let rim = (max(0, row - 2)...min(windows.count - 1, row + 2)).contains {
                    if case .held = solid[$0][lane] { true } else { false }
                }
                windows[row][lane] = rim ? .held : .moved(error)
            }
        }
        func settled(_ row: Int) -> Bool? {
            let judged = windows[row].compactMap { $0 }
            guard judged.count >= 2 else { return nil }
            let off = judged.filter { if case .moved(let error) = $0 { error > 12 } else { true } }
            return off.count * 2 < judged.count
        }
        // An edge fade or dimming sits over moving content, so its lines settle in neither frame.
        let reach = min(lines.count / 3, current.length / 6 / 16)
        var top = 0
        for row in 0..<reach {
            guard let settled = settled(row) else { continue }
            if settled { break }
            top = row + 1
        }
        var bottom = lines.count
        for row in stride(from: lines.count - 1, through: max(top, lines.count - reach), by: -1) {
            guard let settled = settled(row) else { continue }
            if settled { break }
            bottom = row
        }
        let kept = windows[top..<bottom]
        var errors: [Double] = []
        var held = 0, judged = 0
        var consistent = true
        for lane in 0..<current.lanes {
            var changed = 0
            for window in kept.compactMap({ $0[lane] }) {
                judged += 1
                guard case .moved(let error) = window else { held += 1; continue }
                errors.append(error)
                if error > 12 { changed += 1 }
            }
            // One window is a caret blinking; a lane changed in more never moved with the rest.
            if changed > 1 { consistent = false }
        }
        // A sidebar may fill much of a window; a region mostly still has too little moving to trust.
        if held * 3 > judged * 2 { consistent = false }
        errors.sort()
        // A window's stride short of the band, where the faintest fade still passed as settled.
        let unsettled =
            bottom < lines.count ? min(current.length - shift, current.length - lines[bottom] - shift + 16) : 0
        return (errors.dropLast(errors.count / 20).last ?? 255, consistent, unsettled)
    }

    private static func patchError(previous: Frame, current: Frame, shift: Int, start: Int, end: Int) -> Double {
        let lower = max(start, start - shift), upper = min(end, end - shift)
        var maximum = 0.0
        for line in stride(from: lower, to: upper, by: 16) {
            for lane in 0..<current.lanes {
                maximum = max(maximum, current.difference(to: previous, shift: shift,
                    start: line, end: min(upper, line + 32), stride: 1, selectedLanes: [lane]))
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
