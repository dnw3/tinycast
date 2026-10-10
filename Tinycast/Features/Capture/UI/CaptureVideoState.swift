import AVFoundation
import Observation

@MainActor
@Observable
final class CaptureVideoState {
    enum Preview: Equatable {
        case loading, ready, failed(String)
    }

    struct PreviewRequest: Equatable {
        let edit: CaptureVideoEdit
        let attempt: Int
    }

    let source: CaptureSource
    let url: URL
    let info: CaptureVideoService.Info
    private(set) var edit: CaptureVideoEdit
    var savedEdit: CaptureVideoEdit?
    var busy = false
    var notice: String?
    var exportOptions = CaptureVideoExportOptions()
    var progress: Double?
    private(set) var preview = Preview.loading
    var previewAttempt = 0
    var selectedEffectID: UUID?
    var playhead = 0.0
    var thumbnails: [CGImage] = []
    var previewRequest: PreviewRequest {
        var snapshot = edit
        if selectedEffect != nil { snapshot.effects = [] }
        return .init(edit: snapshot, attempt: previewAttempt)
    }
    var selectedEffect: CaptureVideoEffect? { edit.effects.first { $0.id == selectedEffectID } }
    private(set) var undo = CaptureVideoUndoHistory()
    @ObservationIgnored let player: AVPlayer
    @ObservationIgnored private var seeking: Task<Void, Never>?

    init(source: CaptureSource, url: URL, info: CaptureVideoService.Info, edit: CaptureVideoEdit? = nil) {
        self.source = source; self.url = url; self.info = info
        self.edit = edit ?? CaptureVideoEdit(end: info.duration)
        player = AVPlayer()
        player.automaticallyWaitsToMinimizeStalling = true
    }

    var needsPreservation: Bool { savedEdit != edit }

    deinit { seeking?.cancel() }

    func change(_ update: (inout CaptureVideoEdit) -> Void) {
        var replacement = edit
        update(&replacement)
        guard (try? replacement.validated(duration: info.duration)) != nil else {
            notice = "Use times within the original recording, avoid overlapping cuts, and keep at least 0.1 seconds."
            return
        }
        undo.commit(replacement, to: &edit)
        notice = nil
    }

    func beginEditing() { undo.begin(edit) }
    func endEditing() { undo.end(edit) }
    func undoEdit() { undo.undo(&edit); notice = nil }
    func redoEdit() { undo.redo(&edit); notice = nil }

    func addEffect(_ kind: CaptureVideoEffect.Kind) {
        player.pause()
        let position = min(max(edit.start, (playhead * 600).rounded() / 600),
            edit.end - min(0.1, edit.end - edit.start))
        let effect = CaptureVideoEffect(kind: kind, start: position, end: min(edit.end, position + 3),
            rect: CGRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5),
            color: kind == .text ? .init(red: 255, green: 255, blue: 255) : .init(red: 0, green: 0, blue: 0))
        change { $0.effects.append(effect) }
        if edit.effects.contains(where: { $0.id == effect.id }) { selectedEffectID = effect.id }
    }

    func changeEffect(_ update: (inout CaptureVideoEffect) -> Void) {
        guard let index = edit.effects.firstIndex(where: { $0.id == selectedEffectID }) else { return }
        change { update(&$0.effects[index]) }
    }

    func seek(to source: Double) {
        player.pause()
        let timeline = CaptureVideoTimeline(edit), output = timeline.outputTime(at: source)
        playhead = timeline.sourceTime(at: output) ?? edit.end
        seeking?.cancel()
        seeking = Task { [weak self] in
            guard let self else { return }
            _ = await self.player.seek(to: CaptureVideoService.time(output), toleranceBefore: .zero, toleranceAfter: .zero)
        }
    }

    func observePlayback() async {
        do {
            while !Task.isCancelled {
                if player.rate != 0, let time = CaptureVideoTimeline(edit).sourceTime(at: player.currentTime().seconds) {
                    playhead = time
                }
                try await Task.sleep(for: .milliseconds(100))
            }
        } catch {}
    }

    func loadThumbnails() async {
        do {
            let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: 160, height: 100)
            var images: [CGImage] = []
            for index in 0..<12 {
                try Task.checkCancellation()
                images.append(try await generator.image(at: CaptureVideoService.time(info.duration * Double(index) / 12)).image)
            }
            try Task.checkCancellation()
            thumbnails = images
        } catch is CancellationError {} catch { notice = "Timeline thumbnails could not load. Video editing is still available." }
    }

    func updatePreview() async {
        let request = previewRequest, position = playhead
        seeking?.cancel(); seeking = nil
        player.pause()
        player.replaceCurrentItem(with: nil)
        preview = .loading
        do {
            try await Task.sleep(for: .milliseconds(120))
            let prepared = try await CaptureVideoService.prepare(url, edit: request.edit)
            try Task.checkCancellation()
            guard previewRequest == request else { return }
            let item = AVPlayerItem(asset: prepared.asset)
            item.audioMix = prepared.mix
            item.videoComposition = prepared.video
            item.audioTimePitchAlgorithm = .timeDomain
            player.defaultRate = 1
            player.volume = 1
            player.replaceCurrentItem(with: item)
            let deadline = ContinuousClock.now.advanced(by: .seconds(10))
            while item.status == .unknown, ContinuousClock.now < deadline {
                try await Task.sleep(for: .milliseconds(50))
            }
            try Task.checkCancellation()
            guard previewRequest == request else { return }
            guard item.status == .readyToPlay else { throw item.error ?? CaptureVideoError.invalidMedia }
            _ = await player.seek(to: CaptureVideoService.time(CaptureVideoTimeline(edit).outputTime(at: position)),
                toleranceBefore: .zero, toleranceAfter: .zero)
            try Task.checkCancellation()
            preview = .ready
        } catch is CancellationError {} catch {
            if previewRequest == request {
                player.replaceCurrentItem(with: nil)
                preview = .failed(error.localizedDescription)
            }
        }
    }
}
