import Foundation

/// Holds back the newest frame that lines up, so a fast scroll never outruns the overlap.
struct ScrollTracker<Payload: Sendable>: Sendable {
    typealias Frame = ScrollStitchPolicy.Frame
    typealias Match = (Frame, Frame) -> ScrollStitchPolicy.Decision

    struct Strip: Sendable {
        let frame: Frame
        let payload: Payload
        /// Lines past the result's end; nil for the first, which is the whole frame.
        let offset: Int?
        let trailing: Int
        /// Taken while scrolling back: the strip goes before the result, and `frame` is upside down.
        var reversed = false
    }

    enum Step: Sendable {
        case commit(Strip)
        /// Scrolled back above the result's end; nothing is added until it moves forward again.
        case backward
        /// The latest frames no longer line up with what was captured.
        case lost
        /// Lined up again after being lost.
        case found
        /// Scrolled back from the very start, so the result now grows before its first strip.
        case reversing
    }

    /// A single miss can be a frame caught mid-change; a run of them is worth telling the reader.
    static var missesBeforeLost: Int { 2 }
    /// Strips matched again once the frame matched from no longer lines up.
    static var historyLimit: Int { 4 }

    /// The frame matched from: it follows the reader back and forth, while the result's end stays put.
    private(set) var accepted: Frame?
    private(set) var pending: Strip?
    /// The latest frame matched the one before it: nothing on screen is moving.
    private(set) var resting = false
    /// Frames now arrive upside down to matching, since the reader scrolls back from where it started.
    private(set) var reversed = false
    private var last: Frame?
    private var misses = 0
    /// The result's last lines that may be a footer or fade; every later strip retakes at least these.
    private var unreliable = 0
    /// Lines added past the first strip; past half a frame, scrolling back is only scrolling back.
    private var grown = 0
    private var backwardRun = 0
    /// Where the frame matched from and the result's last strip begin, along the scroll.
    private var position = 0
    private var end = 0
    private var history: [(frame: Frame, position: Int)] = []

    /// Lines the frame matched from lies behind the result's end; the reader passes them before adding.
    private var lead: Int { end - position }

    private var turnable: Bool { !reversed && grown * 2 < (accepted?.length ?? 0) }

    mutating func observe(_ frame: Frame, payload: Payload, match: Match) -> [Step] {
        let frame = reversed ? frame.reversed() : frame
        resting = last.map { ScrollStitchPolicy.stable($0, frame) } ?? false
        last = frame
        guard let accepted else {
            // Only content at rest starts a capture, so nothing half-drawn becomes its first strip.
            guard resting else { return [] }
            self.accepted = frame
            history = [(frame, 0)]
            return [.commit(Strip(frame: frame, payload: payload, offset: nil, trailing: 0))]
        }
        var steps: [Step] = []
        var decision = match(accepted, frame)
        if let pending, !decision.appends {
            steps.append(.commit(commit(pending)))
            self.pending = nil
            decision = match(pending.frame, frame)
        }
        if decision == .uncertain, pending == nil {
            // Nothing scrolled, yet the picture changed, as a window turning key does: match from the newest.
            if resting, let travel = frame.travel, travel == self.accepted?.travel {
                self.accepted = frame
                misses = 0
                return steps
            }
            // Scrolled out of reach of the frame matched from, perhaps not of an earlier strip.
            if misses > 0, let found = locate(frame, match: match) {
                self.accepted = frame
                position = found
                if misses >= Self.missesBeforeLost { steps.append(.found) }
                misses = 0
                return steps
            }
        }
        if case .reverse = decision, turnable, pending == nil {
            backwardRun += 1
            // Twice above the first strip, little added yet: turn the frames over and grow the other way.
            if backwardRun >= 2 { return steps + turn(frame, payload: payload, match: match) }
        } else {
            backwardRun = 0
        }
        return steps + resolve(decision, frame: frame, payload: payload)
    }

    /// Frames that arrived together: the newest, or every one in order once it misses after lining up.
    mutating func observe(batch: [(frame: Frame, payload: Payload)], match: Match) -> [(index: Int, steps: [Step])] {
        guard let newest = batch.last else { return [] }
        var trial = self
        let steps = trial.observe(newest.frame, payload: newest.payload, match: match)
        guard batch.count > 1, misses == 0, trial.misses > 0 else {
            self = trial
            return [(batch.count - 1, steps)]
        }
        return batch.indices.map { index in
            (index, observe(batch[index].frame, payload: batch[index].payload, match: match))
        }
    }

    private mutating func resolve(_ decision: ScrollStitchPolicy.Decision, frame: Frame, payload: Payload) -> [Step] {
        var steps: [Step] = []
        switch decision {
        case .append(let shift, _, let trailing):
            let beyond = shift - lead
            guard beyond > 0 else {
                // Still behind the result's end: follow the reader, so matching keeps up as it comes back.
                if pending == nil {
                    accepted = frame
                    position += shift
                }
                break
            }
            var strip = Strip(frame: frame, payload: payload, offset: beyond, trailing: trailing, reversed: reversed)
            // Scrolling back a little keeps the furthest frame, so nothing already seen is dropped.
            if let pending, let ahead = pending.offset, ahead > beyond { strip = pending }
            if resting {
                steps.append(.commit(commit(strip)))
                pending = nil
            } else {
                pending = strip
            }
        case .reverse(let shift):
            // While the capture may still turn, scrolling back may be where the reader means to go.
            guard !turnable else { break }
            steps.append(.backward)
            if pending == nil {
                accepted = frame
                position -= shift
            }
        case .duplicate, .uncertain:
            break
        }
        if decision == .uncertain {
            misses += 1
            if misses == Self.missesBeforeLost { steps.append(.lost) }
        } else {
            if misses >= Self.missesBeforeLost { steps.append(.found) }
            misses = 0
        }
        return steps
    }

    /// Where an earlier strip places the frame, newest first.
    private func locate(_ frame: Frame, match: Match) -> Int? {
        for entry in history.reversed() where entry.position != position {
            switch match(entry.frame, frame) {
            case .append(let shift, _, _): return entry.position + shift
            case .reverse(let shift): return entry.position - shift
            case .duplicate: return entry.position
            case .uncertain: continue
            }
        }
        return nil
    }

    /// Upside down from here on: the first strip is the end, and what was added since is climbed over.
    private mutating func turn(_ frame: Frame, payload: Payload, match: Match) -> [Step] {
        guard let accepted else { return [] }
        reversed = true
        history = history.map { ($0.frame.reversed(), -$0.position) }
        position = -position
        end = 0
        unreliable = 0
        misses = 0
        let turned = frame.reversed()
        self.accepted = accepted.reversed()
        last = turned
        return [.reversing] + resolve(match(accepted.reversed(), turned), frame: turned, payload: payload)
    }

    /// Retaking fewer lines than the last strip would leave its footer or fade inside the result.
    private mutating func commit(_ strip: Strip) -> Strip {
        guard let offset = strip.offset else { return strip }
        if !strip.reversed { grown += offset }
        unreliable = min(strip.frame.length - offset, max(unreliable, strip.trailing))
        end += offset
        position = end
        accepted = strip.frame
        history.append((strip.frame, end))
        if history.count > Self.historyLimit { history.removeFirst() }
        return Strip(
            frame: strip.frame, payload: strip.payload, offset: offset, trailing: unreliable, reversed: strip.reversed)
    }

    /// The pending frame, written when the capture finishes rather than lost with it.
    mutating func flush() -> Strip? {
        defer { pending = nil }
        guard let pending else { return nil }
        return commit(pending)
    }

    /// The reader chose to go on past a gap: the frame is added whole after the result's end.
    mutating func bridge(_ frame: Frame, payload: Payload) -> Strip? {
        guard accepted != nil else { return nil }
        let frame = reversed ? frame.reversed() : frame
        pending = nil
        misses = 0
        last = frame
        guard frame.length > unreliable else { return nil }
        return commit(Strip(
            frame: frame, payload: payload, offset: frame.length - unreliable, trailing: unreliable, reversed: reversed))
    }
}

extension ScrollStitchPolicy.Decision {
    fileprivate var appends: Bool {
        if case .append = self { return true }
        return false
    }
}
