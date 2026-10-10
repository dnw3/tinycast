import AppKit
import Observation

@MainActor
@Observable
final class CaptureWorkspaceState {
    let target: CaptureScreenService.Target
    let source: CaptureSource
    let document: CaptureDocument
    let preview: CGImage
    var request: CaptureRequest
    var axis: CaptureDocument.Axis
    var busy = false
    var choosingWindow = false
    var choosingElement = false
    var selectingTarget: Bool { choosingWindow || choosingElement }
    var requiresScrollRegion = false
    var selectionOptions = false
    var aspect = CaptureSelectionConstraint.Aspect.free
    var snaps = true
    var lastRegion: CGRect?
    var recordingOptions = CaptureRecordingOptions()
    var displays: CaptureDisplaySelection?
    @ObservationIgnored var sourceFrames: [String: (CGRect, CGFloat)]
    @ObservationIgnored var sourceWindows: [String: CGWindowID] = [:]

    init(
        target: CaptureScreenService.Target, source: CaptureSource, document: CaptureDocument,
        preview: CGImage, request: CaptureRequest, axis: CaptureDocument.Axis
    ) {
        self.target = target
        self.source = source
        self.document = document
        self.preview = preview
        self.request = request
        self.axis = axis
        choosingWindow = request.scope == .window
        sourceFrames = [
            document.pieces[0].raster: (CGRect(origin: .zero, size: target.screenFrame.size), target.scale)
        ]
    }

    func scale(for document: CaptureDocument) -> CGFloat {
        document.pieces.first.flatMap { sourceFrames[$0.raster]?.1 } ?? target.scale
    }

    func frame(for document: CaptureDocument, cropped: Bool = true) -> CGRect? {
        guard document.pieces.count == 1, let piece = document.pieces.first,
            let (frame, scale) = sourceFrames[piece.raster]
        else { return nil }
        let visible = cropped ? document.outputBounds : document.bounds
        let crop = piece.reflection?.rect(visible, in: document.bounds) ?? visible
        return CaptureSelectionGeometry.frame(
            pixels: crop.offsetBy(dx: piece.source.minX, dy: piece.source.minY), in: frame, scale: scale)
    }
}
