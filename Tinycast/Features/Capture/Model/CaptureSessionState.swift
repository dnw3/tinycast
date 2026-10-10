import Foundation

struct CaptureSessionState: Equatable, Sendable {
    enum Phase: Equatable, Sendable {
        case preparing, selecting, scrolling, paused, editing, outputting, closed
    }
    let id: UUID
    private(set) var revision = 0
    private(set) var phase: Phase = .preparing

    mutating func advance(to phase: Phase) {
        guard self.phase != .closed else { return }
        revision += 1
        self.phase = phase
    }

    func accepts(id: UUID, revision: Int) -> Bool {
        self.id == id && self.revision == revision && phase != .closed
    }
}
