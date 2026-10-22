import Foundation

/// Holds back the newest frame that lines up, so a fast scroll never outruns the overlap.
struct ScrollTracker<Payload: Sendable>: Sendable {
    struct Strip: Sendable {
        let frame: ScrollStitchPolicy.Frame
        let payload: Payload
        /// Lines past the last strip; nil for the first, which is the whole frame.
        let offset: Int?
        let trailing: Int
        /// Taken while scrolling back: the strip goes before the result, and `frame` is upside down.
        var reversed = false
    }

    enum Step: Sendable {
        case commit(Strip)
        /// Scrolled back above the last strip; nothing is added until it moves forward again.
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

    private(set) var accepted: ScrollStitchPolicy.Frame?
    private(set) var pending: Strip?
    /// The latest frame matched the one before it: nothing on screen is moving.
    private(set) var resting = false
    private var last: ScrollStitchPolicy.Frame?
    private var misses = 0
    /// The result's last lines that may be a footer or fade; every later strip retakes at least these.
    private var unreliable = 0
    /// Frames now arrive upside down to matching, since the reader scrolls back from where it started.
    private(set) var reversed = false
    /// Lines added past the first strip; past half a frame, scrolling back is only scrolling back.
    private var grown = 0
    /// Lines a turned capture must climb before anything lies above the result's first line.
    private var headroom = 0
    private var backwardRun = 0

    mutating func observe(
        _ frame: ScrollStitchPolicy.Frame, payload: Payload,
        match: (ScrollStitchPolicy.Frame, ScrollStitchPolicy.Frame) -> ScrollStitchPolicy.Decision
    ) -> [Step] {
        let frame = reversed ? frame.reversed() : frame
        resting = last.map { ScrollStitchPolicy.stable($0, frame) } ?? false
        last = frame
        guard let accepted else {
            // Only content at rest starts a capture, so nothing half-drawn becomes its first strip.
            guard resting else { return [] }
            self.accepted = frame
            return [.commit(Strip(frame: frame, payload: payload, offset: nil, trailing: 0))]
        }
        var steps: [Step] = []
        var decision = match(accepted, frame)
        if let pending, !decision.appends {
            if let settled = settle(pending) { steps.append(.commit(settled)) }
            self.accepted = pending.frame
            self.pending = nil
            decision = match(pending.frame, frame)
        }
        // Nothing scrolled, yet the picture changed, as a window turning key does: match from the newest.
        if decision == .uncertain, resting, pending == nil, let travel = frame.travel,
            travel == self.accepted?.travel
        {
            self.accepted = frame
            misses = 0
            return steps
        }
        // Twice above the first strip, little added yet: turn the frames over and grow the other way.
        if decision == .reverse, turnable, self.pending == nil {
            backwardRun += 1
            if backwardRun >= 2, let accepted = self.accepted {
                reversed = true
                headroom = grown
                unreliable = 0
                self.accepted = accepted.reversed()
                let turned = frame.reversed()
                last = turned
                steps.append(.reversing)
                return steps + observeTurned(turned, payload: payload, match: match)
            }
        } else {
            backwardRun = 0
        }
        return steps + resolve(decision, frame: frame, payload: payload)
    }

    private mutating func observeTurned(
        _ frame: ScrollStitchPolicy.Frame, payload: Payload,
        match: (ScrollStitchPolicy.Frame, ScrollStitchPolicy.Frame) -> ScrollStitchPolicy.Decision
    ) -> [Step] {
        guard let accepted else { return [] }
        misses = 0
        return resolve(match(accepted, frame), frame: frame, payload: payload)
    }

    private mutating func resolve(
        _ decision: ScrollStitchPolicy.Decision, frame: ScrollStitchPolicy.Frame, payload: Payload
    ) -> [Step] {
        var steps: [Step] = []
        switch decision {
        case .append(let offset, _, let trailing):
            var strip = Strip(frame: frame, payload: payload, offset: offset, trailing: trailing, reversed: reversed)
            // Scrolling back a little keeps the furthest frame, so nothing already seen is dropped.
            if let pending, let ahead = pending.offset, ahead > offset { strip = pending }
            if resting {
                if let settled = settle(strip) { steps.append(.commit(settled)) }
                self.accepted = strip.frame
                pending = nil
            } else {
                pending = strip
            }
        case .reverse:
            // While the capture may still turn, scrolling back may be where the reader means to go.
            if !turnable { steps.append(.backward) }
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

    private var turnable: Bool {
        !reversed && grown * 2 < (accepted?.length ?? 0)
    }

    /// The pending frame, written when the capture finishes rather than lost with it.
    mutating func flush() -> Strip? {
        defer { pending = nil }
        guard let pending else { return nil }
        accepted = pending.frame
        return settle(pending)
    }

    /// Retakes at least the last strip's lines; nil while a turned capture climbs over its own start.
    private mutating func settle(_ strip: Strip) -> Strip? {
        guard var offset = strip.offset else { return strip }
        if strip.reversed, headroom > 0 {
            guard offset > headroom else { headroom -= offset; return nil }
            offset -= headroom
            headroom = 0
        }
        if !strip.reversed { grown += offset }
        unreliable = min(strip.frame.length - offset, max(unreliable, strip.trailing))
        return Strip(
            frame: strip.frame, payload: strip.payload, offset: offset, trailing: unreliable, reversed: strip.reversed)
    }

    /// After a pause or an unwritten strip, matching starts over from the last strip on disk.
    mutating func restart(from committed: ScrollStitchPolicy.Frame?) {
        accepted = committed
        pending = nil
        resting = false
        last = nil
        misses = 0
    }
}

extension ScrollStitchPolicy.Decision {
    fileprivate var appends: Bool {
        if case .append = self { return true }
        return false
    }
}
