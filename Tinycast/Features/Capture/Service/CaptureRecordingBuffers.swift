import ScreenCaptureKit
import Synchronization

final class CaptureRecordingBuffers: NSObject, SCStreamOutput, Sendable {
    typealias Sample = CMReadySampleBuffer<CMSampleBuffer.DynamicContent>
    enum Track: Int, CaseIterable, Sendable { case screen, system, microphone }
    struct Frame: Sendable { let sample: Sample; let track: Track }
    private struct ScreenState { var status: SCFrameStatus?; var received = false }

    let frames: [Track: AsyncThrowingStream<Sample, Error>]
    let ready: AsyncThrowingStream<Void, Error>
    private let continuations: [Track: AsyncThrowingStream<Sample, Error>.Continuation]
    private let preparation: AsyncThrowingStream<Void, Error>.Continuation
    private let end = Mutex<CMTime?>(nil)
    private let latestScreen = Mutex<Sample?>(nil)
    private let screen = Mutex(ScreenState())
    private let overlayFrames: Bool
    var stopped: CMTime? { end.withLock { $0 } }
    var screenStatus: SCFrameStatus? { screen.withLock { $0.status } }
    var hasScreenFrame: Bool { screen.withLock { $0.received } }

    init(overlayFrames: Bool = false) {
        self.overlayFrames = overlayFrames
        var frames: [Track: AsyncThrowingStream<Sample, Error>] = [:]
        var continuations: [Track: AsyncThrowingStream<Sample, Error>.Continuation] = [:]
        for track in Track.allCases {
            let (stream, continuation) = AsyncThrowingStream<Sample, Error>.makeStream(
                bufferingPolicy: .bufferingOldest(track == .screen ? 3 : 64))
            frames[track] = stream; continuations[track] = continuation
        }
        self.frames = frames; self.continuations = continuations
        (ready, preparation) = AsyncThrowingStream.makeStream(bufferingPolicy: .bufferingOldest(1))
        super.init()
    }

    func stream(
        _ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType
    ) {
        receive(sampleBuffer, type: type)
    }

    func receive(_ sampleBuffer: CMSampleBuffer, type: SCStreamOutputType) {
        guard stopped == nil else { return }
        let track: Track
        switch type {
        case .screen:
            guard
                let attachments = CMSampleBufferGetSampleAttachmentsArray(
                    sampleBuffer, createIfNecessary: false)
                    as? [[SCStreamFrameInfo: Any]],
                let raw = attachments.first?[.status] as? Int,
                let status = SCFrameStatus(rawValue: raw)
            else { return }
            screen.withLock { $0.status = status }
            guard status == .complete, sampleBuffer.imageBuffer != nil else { return }
            track = .screen
        case .audio: track = .system
        case .microphone: track = .microphone
        @unknown default: return
        }
        guard sampleBuffer.isValid, sampleBuffer.dataReadiness == .ready else { return }
        do {
            // ScreenCaptureKit lends immutable pixels; the copy owns separate sample metadata.
            nonisolated(unsafe) let copy = try CMSampleBuffer(copying: sampleBuffer)
            if track == .screen { screen.withLock { $0.received = true } }
            accept(Sample(unsafeBuffer: copy), track: track)
        } catch { fail(error) }
    }

    func accept(_ sample: Sample, track: Track) {
        guard stopped == nil else { return }
        if overlayFrames && track == .screen {
            latestScreen.withLock { $0 = sample }
        } else {
            yield(sample, track: track)
        }
    }

    func yield(_ sample: Sample, track: Track) {
        guard stopped == nil else { return }
        if case .dropped = continuations[track]?.yield(sample) { fail(Failure.overloaded(track)) }
    }

    func finish(at time: CMTime) {
        end.withLock { if $0 == nil { $0 = time } }
        latestScreen.withLock { $0 = nil }
        for continuation in continuations.values { continuation.finish() }
    }

    func started() { preparation.yield(()); preparation.finish() }

    func fail(_ error: Error) {
        end.withLock { if $0 == nil { $0 = CMClockGetTime(CMClockGetHostTimeClock()) } }
        latestScreen.withLock { $0 = nil }
        preparation.finish(throwing: error)
        for continuation in continuations.values { continuation.finish(throwing: error) }
    }

    func pump(framesPerSecond: Int) -> Task<Void, Never> {
        Task.detached { [weak self] in
            let interval = CMTime(value: 1, timescale: Int32(framesPerSecond))
            while !Task.isCancelled {
                guard let self, self.stopped == nil else { return }
                if var sample = self.latestScreen.withLock({ $0 }) {
                    let time = CMClockGetTime(CMClockGetHostTimeClock())
                    sample.sampleProperties.timings = .sequential(
                        presentationTimeOfFirstSample: time, uniformDuration: interval)
                    sample.outputPresentationTimeStamp = time
                    self.yield(sample, track: .screen)
                }
                do { try await Task.sleep(for: .seconds(interval.seconds)) } catch { return }
            }
        }
    }

    enum Failure: LocalizedError {
        case overloaded(Track), encoderStalled
        var errorDescription: String? {
            String(
                localized:
                    "Recording could not keep up. Earlier segments are safe; try a smaller region or lower frame rate."
            )
        }
    }
}
