import Foundation

/// Holds back the newest frame that lines up, so a fast scroll never outruns the overlap.
struct ScrollTracker<Payload: Sendable>: Sendable {
    struct Strip: Sendable {
        let frame: ScrollStitchPolicy.Frame
        let payload: Payload
        /// Lines past the last strip; nil for the first, which is the whole frame.
        let offset: Int?
        let trailing: Int
    }

    enum Step: Sendable {
        case commit(Strip)
        /// Scrolled back above the last strip; nothing is added until it moves forward again.
        case backward
        /// The latest frames no longer line up with what was captured.
        case lost
        /// Lined up again after being lost.
        case found
    }

    /// A single miss can be a frame caught mid-change; a run of them is worth telling the reader.
    static var missesBeforeLost: Int { 2 }

    private(set) var accepted: ScrollStitchPolicy.Frame?
    private(set) var pending: Strip?
    /// The latest frame matched the one before it: nothing on screen is moving.
    private(set) var resting = false
    private var last: ScrollStitchPolicy.Frame?
    private var misses = 0

    mutating func observe(
        _ frame: ScrollStitchPolicy.Frame, payload: Payload,
        match: (ScrollStitchPolicy.Frame, ScrollStitchPolicy.Frame) -> ScrollStitchPolicy.Decision
    ) -> [Step] {
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
            steps.append(.commit(pending))
            self.accepted = pending.frame
            self.pending = nil
            decision = match(pending.frame, frame)
        }
        switch decision {
        case .append(let offset, _, let trailing):
            var strip = Strip(frame: frame, payload: payload, offset: offset, trailing: trailing)
            // Scrolling back a little keeps the furthest frame, so nothing already seen is dropped.
            if let pending, let ahead = pending.offset, ahead > offset { strip = pending }
            if resting {
                steps.append(.commit(strip))
                self.accepted = strip.frame
                pending = nil
            } else {
                pending = strip
            }
        case .reverse:
            steps.append(.backward)
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

    /// The pending frame, written when the capture finishes rather than lost with it.
    mutating func flush() -> Strip? {
        defer { pending = nil }
        guard let pending else { return nil }
        accepted = pending.frame
        return pending
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
