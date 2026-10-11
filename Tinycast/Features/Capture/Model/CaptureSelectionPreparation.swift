import CoreGraphics
import Foundation

struct CaptureSelectionPreparation: Sendable {
    enum Selection: Equatable, Sendable {
        case region(CGRect, CaptureRequest.Scope)
        case window(UInt32)
        case displays(CGRect)
    }

    private(set) var ready: Bool
    private(set) var pending: Selection?
    private var closed = false

    init(ready: Bool = false) { self.ready = ready }

    mutating func deferSelection(_ selection: Selection) -> Bool {
        guard !closed else { return true }
        guard !ready else { return false }
        pending = selection
        return true
    }

    mutating func finish() -> Selection? {
        guard !closed else { return nil }
        ready = true
        defer { pending = nil }
        return pending
    }

    mutating func discardSelection() { pending = nil }

    mutating func cancel() {
        closed = true
        ready = false
        pending = nil
    }
}
