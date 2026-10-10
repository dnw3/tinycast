import Foundation

struct CaptureVideoUndoHistory: Sendable {
    private var past: [CaptureVideoEdit] = []
    private var future: [CaptureVideoEdit] = []
    private var group: CaptureVideoEdit?
    var canUndo: Bool { !past.isEmpty }
    var canRedo: Bool { !future.isEmpty }

    mutating func begin(_ edit: CaptureVideoEdit) { if group == nil { group = edit } }

    mutating func end(_ edit: CaptureVideoEdit) {
        defer { group = nil }
        if let group, group != edit { record(group) }
    }

    mutating func commit(_ replacement: CaptureVideoEdit, to edit: inout CaptureVideoEdit) {
        guard replacement != edit else { return }
        if group == nil { record(edit) }
        edit = replacement
    }

    mutating func undo(_ edit: inout CaptureVideoEdit) {
        end(edit)
        guard let previous = past.popLast() else { return }
        future.append(edit)
        edit = previous
    }

    mutating func redo(_ edit: inout CaptureVideoEdit) {
        end(edit)
        guard let next = future.popLast() else { return }
        past.append(edit)
        edit = next
    }

    private mutating func record(_ edit: CaptureVideoEdit) {
        past.append(edit)
        if past.count > 100 { past.removeFirst() }
        future.removeAll()
    }
}
