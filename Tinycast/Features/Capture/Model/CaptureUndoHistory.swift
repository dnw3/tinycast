import Foundation

struct CaptureUndoHistory: Sendable {
    private struct Snapshot: Equatable, Sendable {
        let size: CapturePixelSize
        let pieces: [CaptureDocument.Piece]
        let edit: CaptureDocument.Edit
        let captureScale: Double?
        let axis: CaptureDocument.Axis?

        init(_ document: CaptureDocument) {
            size = document.size
            pieces = document.pieces
            edit = document.edit
            captureScale = document.captureScale
            axis = document.axis
        }

        func apply(to document: inout CaptureDocument) {
            document.size = size
            document.pieces = pieces
            document.edit = edit
            document.captureScale = captureScale
            document.axis = axis
            document.revision += 1
        }
    }

    private var past: [Snapshot] = []
    private var future: [Snapshot] = []
    private var group: Snapshot?
    var canUndo: Bool { !past.isEmpty }
    var canRedo: Bool { !future.isEmpty }

    mutating func begin(_ document: CaptureDocument) {
        if group == nil { group = Snapshot(document) }
    }

    mutating func end(_ document: CaptureDocument) {
        defer { group = nil }
        guard let group, group != Snapshot(document) else { return }
        record(group)
    }

    mutating func commit(_ edit: CaptureDocument.Edit, to document: inout CaptureDocument) {
        var replacement = document
        replacement.edit = edit
        commit(replacement, to: &document)
    }

    mutating func commit(_ replacement: CaptureDocument, to document: inout CaptureDocument) {
        let next = Snapshot(replacement)
        guard next != Snapshot(document) else { return }
        if group == nil { record(Snapshot(document)) }
        next.apply(to: &document)
    }

    private mutating func record(_ snapshot: Snapshot) {
        past.append(snapshot)
        if past.count > 100 { past.removeFirst() }
        future.removeAll()
    }

    mutating func undo(_ document: inout CaptureDocument) {
        end(document)
        guard let edit = past.popLast() else { return }
        future.append(Snapshot(document))
        edit.apply(to: &document)
    }

    mutating func redo(_ document: inout CaptureDocument) {
        end(document)
        guard let edit = future.popLast() else { return }
        past.append(Snapshot(document))
        edit.apply(to: &document)
    }
}
