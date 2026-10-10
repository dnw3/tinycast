import AppKit
import Observation

@MainActor
@Observable
final class CaptureDisplaySelection {
    struct Snapshot {
        let display: CaptureDisplayComposition.Display
        let raster: String
        let preview: CGImage
    }

    let snapshots: [Snapshot]
    let bounds: CGRect
    var region: CGRect?

    init(snapshots: [Snapshot]) {
        self.snapshots = snapshots
        bounds = snapshots.reduce(CGRect.null) { $0.union($1.display.frame) }
    }

    func snapshot(for frame: CGRect) -> Snapshot? { snapshots.first { $0.display.frame == frame } }

    func document(region: CGRect, id: UUID, createdAt: Date) throws -> CaptureDocument {
        let layout = try CaptureDisplayComposition.layout(region: region, displays: snapshots.map(\.display))
        var document = CaptureDocument(id: id, createdAt: createdAt, size: layout.size,
            pieces: [], captureScale: Double(layout.scale))
        document.edit.imageLayers = try layout.slices.map { slice in
            guard let snapshot = snapshots.first(where: { $0.display.id == slice.displayID }) else {
                throw CaptureRasterError.invalidTile
            }
            return CaptureImageLayer(id: UUID(), raster: snapshot.raster, source: slice.source, frame: slice.frame)
        }
        return try document.validated()
    }
}
