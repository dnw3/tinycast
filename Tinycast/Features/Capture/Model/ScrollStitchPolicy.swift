import Foundation

enum ScrollStitchPolicy {
    struct Frame: Sendable {
        let length: Int
        let lanes: Int
        let rgb: [UInt8]
        var originalRGB: [UInt8]?
        /// Where the pointer was along the scroll axis, when it was over the region.
        var pointer: Int?
        /// Lines the scroll events had moved the content by when this frame was taken, when they all told.
        var travel: Int?

        /// Upside down along the axis, so scrolling back reads as scrolling on to the same matching.
        func reversed() -> Frame {
            func flip(_ values: [UInt8]) -> [UInt8] {
                (0..<length).reversed().flatMap { line in values[(line * lanes * 3)..<((line + 1) * lanes * 3)] }
            }
            var frame = Frame(length: length, lanes: lanes, rgb: flip(rgb), originalRGB: originalRGB.map(flip))
            frame.pointer = pointer.map { length - 1 - $0 }
            frame.travel = travel.map { -$0 }
            return frame
        }

        /// Lines a hover may have changed: whatever is under the pointer lights as content passes.
        func nearPointer(_ start: Int, _ end: Int) -> Bool {
            guard let pointer else { return false }
            return start < pointer + ScrollStitchPolicy.hoverReach && end > pointer - ScrollStitchPolicy.hoverReach
        }

        func difference(
            to other: Frame, shift: Int, start: Int, end: Int, stride step: Int, textured: Bool = false,
            selectedLanes: [Int]? = nil
        ) -> Double {
            let edges = textured ? (edges(), other.edges()) : nil
            return difference(
                to: other, shift: shift, start: start, end: end, stride: step, edges: edges,
                lanes: selectedLanes ?? Array(0..<lanes))
        }

        /// Each lane's contrast with the lane before it, summed over channels, worked out once a frame.
        func edges() -> [Int32] {
            var edges = [Int32](repeating: 0, count: length * lanes)
            rgb.withUnsafeBufferPointer { rgb in
                for line in 0..<length {
                    for lane in 1..<max(1, lanes) {
                        let here = (line * lanes + lane) * 3
                        var contrast: Int32 = 0
                        for channel in 0..<3 { contrast += Int32(abs(Int(rgb[here + channel]) - Int(rgb[here + channel - 3]))) }
                        edges[line * lanes + lane] = contrast
                    }
                }
            }
            return edges
        }

        /// Every search's hot loop: lanes with no edge in either frame match at any shift, so are skipped.
        func difference(
            to other: Frame, shift: Int, start: Int, end: Int, stride step: Int,
            edges: ([Int32], [Int32])?, lanes selected: [Int]
        ) -> Double {
            var sum = 0, count = 0
            let lanes = lanes
            // The lines a plain stride from `start` visits, less those the shift takes outside the other frame.
            let lower = max(start, -shift), upper = min(end, length - shift)
            guard lower < upper else { return 255 }
            let first = start + (lower - start + step - 1) / step * step
            rgb.withUnsafeBufferPointer { rgb in
                other.rgb.withUnsafeBufferPointer { otherRGB in
                    for line in Swift.stride(from: first, to: upper, by: step) {
                        let previous = line + shift
                        for lane in selected {
                            if let edges, lane > 0,
                                edges.0[line * lanes + lane] + edges.1[previous * lanes + lane] < 48
                            {
                                continue
                            }
                            let index = (line * lanes + lane) * 3, previousIndex = (previous * lanes + lane) * 3
                            sum += abs(Int(rgb[index]) - Int(otherRGB[previousIndex]))
                                + abs(Int(rgb[index + 1]) - Int(otherRGB[previousIndex + 1]))
                                + abs(Int(rgb[index + 2]) - Int(otherRGB[previousIndex + 2]))
                            count += 3
                        }
                    }
                }
            }
            return count == 0 ? 255 : Double(sum) / Double(count)
        }

        /// A bar's line: glass may tint it, but no lane shows the moved edge sparse text in one lane would.
        func fixed(line: Int, in other: Frame) -> Bool {
            var sum = 0
            for lane in 0..<lanes {
                let here = (line * lanes + lane) * 3, there = (line * other.lanes + lane) * 3
                for channel in 0..<3 {
                    let difference = abs(Int(rgb[here + channel]) - Int(other.rgb[there + channel]))
                    if difference > 24 { return false }
                    sum += difference
                }
            }
            return Double(sum) / Double(lanes * 3) < ScrollStitchPolicy.barTolerance
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

    /// About 32pt at 2×: deeper than the fades a page draws at its scrolling edge.
    static let edgeClearance = 64

    /// A glass bar tints with the page scrolling beneath it, about 1.5 a channel on average.
    static let barTolerance = 3.0

    /// Windows that moved with the page, below which a shift has too little picture to vouch for it.
    static let minimumEvidence = 12

    enum Decision: Equatable, Sendable {
        case duplicate
        case append(offset: Int, fixedLeading: Int, fixedTrailing: Int)
        /// Lines above the frame it was matched from.
        case reverse(offset: Int)
        case uncertain
    }

    /// The give around what the scroll events said: an app renders behind them, a capture lands after.
    static func slack(_ expected: Int) -> Int { max(24, abs(expected) / 4) }

    static func agrees(_ shift: Int, expected: Int) -> Bool { abs(shift - expected) <= slack(expected) }

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
        // Too deep a leading band narrows the search; too deep a trailing one only retakes lines.
        while leading < limit, originalCurrent.fixed(line: leading, in: originalPrevious) { leading += 1 }
        while trailing < limit,
            originalCurrent.difference(to: originalPrevious,
                shift: 0, start: length - trailing - 1, end: length - trailing, stride: 1) < barTolerance
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
        let expected = previous.travel.flatMap { from in current.travel.map { $0 - from } }
        let edges = (current.edges(), previous.edges())
        for shift in -maximum...maximum where abs(shift) >= 2 {
            let lower = max(start, start - shift), upper = min(end, end - shift)
            let score = current.difference(
                to: previous, shift: shift, start: lower, end: upper,
                stride: max(1, (upper - lower) / 40), edges: edges, lanes: moving)
            candidates.append((shift, score))
        }
        candidates.sort { $0.1 < $1.1 }
        var refined = Set(candidates.prefix(32).map(\.0))
        // A coarse pass can miss a large shift between sparse lines while bars still match a tiny one.
        if let expected { refined.formUnion(candidates.lazy.filter { agrees($0.0, expected: expected) }.prefix(16).map(\.0)) }
        candidates = refined.map { shift in
            let lower = max(start, start - shift), upper = min(end, end - shift)
            return (shift, current.difference(
                to: previous, shift: shift, start: lower, end: upper, stride: 1, edges: edges, lanes: moving))
        }.sorted { $0.1 < $1.1 }
        // Near the range's end the true shift may lie beyond it; a sliver lining up there proves nothing.
        guard let best = candidates.first, abs(best.0) < maximum - 16 else { return .uncertain }
        // The events' size runs anywhere from one to six times the move, but never the wrong way round.
        if let expected, abs(expected) >= 200, (expected > 0) != (best.0 > 0) { return .uncertain }
        // Events said to pass the range confirm nothing in it: an app may scroll slower than they tell.
        let confirmed = expected.map { abs($0) < maximum && agrees(best.0, expected: $0) } ?? false
        let fit = fit(previous: previous, current: current, shift: best.0, start: start, end: end, hover: confirmed)
        guard fit.consistent, fit.error < (confirmed ? 12 : 8) else { return .uncertain }
        let alternatives = candidates.prefix(32).filter { abs($0.0 - best.0) > 3 }
        guard !alternatives.isEmpty, alternatives.allSatisfy({ candidate in
            patchExceeds(
                previous: previous, current: current, shift: candidate.0, start: start, end: end,
                bar: fit.error * 1.8 + 1.5)
        }) else { return .uncertain }
        guard best.0 > 0 else { return .reverse(offset: -best.0) }
        // A fade over a short line can slip between lanes, so lines by the edge come from the newer frame.
        let retaken = min(length - best.0, max(trailing, fit.unsettled) + edgeClearance)
        return .append(offset: best.0, fixedLeading: leading, fixedTrailing: retaken)
    }

    private enum Window {
        case moved(Double)
        /// Lines up only where it sits still on screen: a sidebar, floating button or edge fade.
        case held
        case edge(Double)
        /// Under the pointer: evidence only for a confirmed shift, and only where it lines up.
        case hovered(Double)
    }

    /// Strict wherever the page moved, except under the pointer, where a hover lights content in place.
    private static func fit(
        previous: Frame, current: Frame, shift: Int, start: Int, end: Int, hover: Bool
    ) -> (error: Double, consistent: Bool, unsettled: Int) {
        let lower = max(start, start - shift), upper = min(end, end - shift)
        let lines = Array(stride(from: lower, to: upper, by: 16))
        var windows = [[Window?]](repeating: [Window?](repeating: nil, count: current.lanes), count: lines.count)
        for (row, line) in lines.enumerated() {
            let window = min(upper, line + 32)
            let hovered = current.nearPointer(line, window) || previous.nearPointer(line + shift, window + shift)
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
                if hovered {
                    windows[row][lane] = .hovered(error)
                    continue
                }
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
            // A sidebar sits still beside the page; only what moved, or tried to, can show a fade.
            let judged = windows[row].compactMap { window -> Window? in
                if case .held = window { return nil }
                return window
            }
            guard !judged.isEmpty else { return nil }
            // Off by the fit's own bar, so a faint fade is either left out or passes, never half of each.
            let off = judged.filter {
                switch $0 {
                case .moved(let error), .hovered(let error): error >= 8
                case .held, .edge: true
                }
            }
            // A fade lies against a bar and may cross one lane of sparse text there; elsewhere, a third.
            let line = lines[row]
            let barred = (start > 4 && line < start + edgeClearance)
                || (end < current.length - 4 && line + 32 + shift > end - edgeClearance)
            return barred ? off.isEmpty : off.count * 3 < judged.count
        }
        // An edge fade settles in neither frame, its deepest lines may pass: a band runs to its last miss.
        let reach = min(lines.count / 3, current.length / 6 / 16)
        let top = ((0..<reach).last { settled($0) == false } ?? -1) + 1
        let bottom = (max(top, lines.count - reach)..<lines.count).first { settled($0) == false } ?? lines.count
        let kept = windows[top..<bottom]
        var errors: [Double] = []
        var held = 0
        var agreeing = true
        for lane in 0..<current.lanes {
            var changed = 0
            for window in kept.compactMap({ $0[lane] }) {
                switch window {
                // A hover lights whatever passes beneath the pointer, so only a confirmed line-up counts.
                case .hovered(let error): if hover, error < 8 { errors.append(error) }
                case .moved(let error):
                    errors.append(error)
                    if error > 12 { changed += 1 }
                case .held: held += 1
                case .edge: break
                }
            }
            // One window is a caret blinking; a lane changed in more never moved with the rest.
            if changed > 1 { agreeing = false }
        }
        // A wide sidebar holds about seven in ten still; past four in five, what moved is a lucky sliver.
        let consistent = agreeing && errors.count >= minimumEvidence && held * 5 <= (held + errors.count) * 4
        errors.sort()
        // A window's stride short of the band, where the faintest fade still passed as settled.
        let unsettled =
            bottom < lines.count ? min(current.length - shift, current.length - lines[bottom] - shift + 16) : 0
        return (errors.dropLast(errors.count / 20).last ?? 255, consistent, unsettled)
    }

    /// Whether some window misses by more than `bar` at this shift: the first one found settles it.
    private static func patchExceeds(
        previous: Frame, current: Frame, shift: Int, start: Int, end: Int, bar: Double
    ) -> Bool {
        let lower = max(start, start - shift), upper = min(end, end - shift)
        for line in stride(from: lower, to: upper, by: 16) {
            for lane in 0..<current.lanes where current.difference(
                to: previous, shift: shift, start: line, end: min(upper, line + 32), stride: 1, edges: nil,
                lanes: [lane]) > bar
            {
                return true
            }
        }
        return false
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
