import ScreenCaptureKit

@MainActor
final class CaptureRecordingSegment: NSObject, SCStreamDelegate {
    let url: URL
    private var stream: SCStream?
    private let buffers: CaptureRecordingBuffers
    private var writer: Task<Void, Error>?
    private var monitor: Task<Void, Never>?
    private var pump: Task<Void, Never>?
    private var stopping = false
    private let interrupted: @MainActor (String) -> Void
    var screenStatus: SCFrameStatus? { buffers.screenStatus }
    var bytes: Int {
        let files = (try? FileManager.default.contentsOfDirectory(at: url.deletingLastPathComponent(),
            includingPropertiesForKeys: [.fileSizeKey])) ?? []
        let prefix = url.deletingPathExtension().lastPathComponent
        return files.filter { $0.lastPathComponent.hasPrefix(prefix) }.reduce(0) {
            $0 + ((try? $1.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        }
    }

    init(url: URL, overlayFrames: Bool = false, interrupted: @escaping @MainActor (String) -> Void) {
        buffers = CaptureRecordingBuffers(overlayFrames: overlayFrames)
        self.url = url; self.interrupted = interrupted
    }

    deinit { writer?.cancel(); monitor?.cancel(); pump?.cancel() }

    func start(
        filter: SCContentFilter, configuration: SCStreamConfiguration, options: CaptureRecordingOptions,
        overlays: CaptureRecordingOverlays? = nil
    ) async throws {
        let stream = SCStream(filter: filter, configuration: configuration, delegate: self)
        try stream.addStreamOutput(buffers, type: .screen, sampleHandlerQueue: nil)
        if options.systemAudio { try stream.addStreamOutput(buffers, type: .audio, sampleHandlerQueue: nil) }
        if options.microphone { try stream.addStreamOutput(buffers, type: .microphone, sampleHandlerQueue: nil) }
        let size = try CapturePixelSize(width: configuration.width, height: configuration.height)
        let buffers = buffers, url = url
        let writer = Task.detached(priority: .userInitiated) {
            do {
                try await CaptureRecordingWriter.write(buffers, to: url, size: size, options: options, overlays: overlays)
            } catch {
                buffers.fail(error)
                throw error
            }
        }
        self.writer = writer
        self.stream = stream
        monitor = Task { [weak self] in
            if case .failure(let error) = await writer.result, let self, !self.stopping {
                self.interrupted(error.localizedDescription)
            }
        }
        do {
            for try await _ in buffers.ready { break }
            try Task.checkCancellation()
            try await stream.startCapture()
            let deadline = ContinuousClock.now.advanced(by: .seconds(5))
            while !buffers.hasScreenFrame {
                try Task.checkCancellation()
                guard buffers.screenStatus != .blank, buffers.screenStatus != .suspended,
                    buffers.screenStatus != .stopped, ContinuousClock.now < deadline
                else { throw CaptureRecordingSession.Failure.sourceUnavailable }
                try await Task.sleep(for: .milliseconds(20))
            }
            if overlays != nil { pump = buffers.pump(framesPerSecond: options.framesPerSecond) }
        } catch {
            stopping = true
            try? await stream.stopCapture()
            buffers.fail(error); writer.cancel()
            _ = await writer.result
            self.stream = nil
            throw error
        }
    }

    func finish(afterCapture: @MainActor () async -> Void = {}) async throws {
        stopping = true
        let stop = CMClockGetTime(CMClockGetHostTimeClock())
        pump?.cancel(); pump = nil
        if let stream {
            do { try await stream.stopCapture() } catch { buffers.fail(error) }
        }
        buffers.finish(at: stop)
        await afterCapture()
        defer { stream = nil; writer = nil; monitor?.cancel(); monitor = nil }
        guard let writer else { throw CaptureVideoError.invalidMedia }
        try await withTaskCancellationHandler { try await writer.value } onCancel: { writer.cancel() }
    }

    nonisolated func stream(_ stream: SCStream, didStopWithError error: Error) {
        Task { @MainActor [weak self] in
            if self?.stopping == false { self?.interrupted(error.localizedDescription) }
        }
    }
}
