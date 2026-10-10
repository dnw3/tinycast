import AppKit
import Observation
import ScreenCaptureKit

@MainActor
@Observable
final class CaptureRecordingSession {
    enum Phase { case starting, recording, pausing, paused, stopping, finished }

    let source: CaptureSource
    let size: CapturePixelSize
    let frame: CGRect
    let options: CaptureRecordingOptions
    private(set) var phase = Phase.paused
    private(set) var elapsed: Double = 0
    private(set) var segments: [URL] = []
    var notice: String?
    var cameraPreview: CaptureRecordingCamera? { layers?.camera }
    @ObservationIgnored private let filter: SCContentFilter
    @ObservationIgnored private let region: CGRect?
    @ObservationIgnored private let windowID: CGWindowID?
    @ObservationIgnored private let displayID: CGDirectDisplayID
    @ObservationIgnored private let interrupted: @MainActor (String) -> Void
    @ObservationIgnored private var segment: CaptureRecordingSegment?
    @ObservationIgnored private var layers: CaptureRecordingLayers?
    @ObservationIgnored private var clock: Task<Void, Never>?
    @ObservationIgnored private var recorded: Double = 0
    @ObservationIgnored private var completedBytes = 0
    @ObservationIgnored private var finishedURL: URL?

    init(
        source: CaptureSource, size: CapturePixelSize, frame: CGRect, options: CaptureRecordingOptions,
        filter: SCContentFilter, region: CGRect?, windowID: CGWindowID?, displayID: CGDirectDisplayID,
        interrupted: @escaping @MainActor (String) -> Void
    ) {
        self.source = source; self.size = size; self.frame = frame; self.options = options
        self.filter = filter; self.region = region; self.windowID = windowID; self.displayID = displayID
        self.interrupted = interrupted
    }

    deinit { clock?.cancel() }

    func resume() async throws {
        guard phase == .paused else { return }
        try checkTarget()
        elapsed = recorded
        phase = .starting
        notice = nil
        let configuration = SCStreamConfiguration()
        configuration.width = size.width; configuration.height = size.height
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: Int32(options.framesPerSecond))
        configuration.queueDepth = 3
        configuration.showsCursor = options.cursor
        configuration.showMouseClicks = options.mouseClicks
        configuration.capturesAudio = options.systemAudio
        configuration.captureMicrophone = options.microphone
        configuration.excludesCurrentProcessAudio = true
        configuration.sampleRate = 48_000
        configuration.channelCount = 2
        configuration.captureDynamicRange = .SDR
        configuration.ignoreShadowsSingleWindow = true
        configuration.scalesToFit = true
        configuration.preservesAspectRatio = true
        if let region { configuration.sourceRect = region }
        let segment = CaptureRecordingSegment(
            url: source.directory.appendingPathComponent("\(UUID().uuidString).mp4"),
            overlayFrames: options.camera || options.keys != .off, interrupted: interrupted)
        do {
            if options.camera || options.keys != .off {
                let layers = CaptureRecordingLayers()
                self.layers = layers
                try await layers.start(options: options)
            }
            try Task.checkCancellation()
            try await segment.start(filter: filter, configuration: configuration, options: options, overlays: layers?.overlays)
            self.segment = segment
            phase = .recording
            startClock()
        } catch {
            await layers?.stop(); layers = nil
            phase = .paused
            throw error
        }
    }

    func pause(reason: String? = nil) async throws {
        guard phase == .recording else { return }
        phase = .pausing
        clock?.cancel(); clock = nil
        notice = reason
        defer { phase = .paused; segment = nil }
        if let segment {
            do { try await segment.finish { await self.layers?.stop(); self.layers = nil } } catch {
                await layers?.stop(); layers = nil
                throw error
            }
            segments.append(segment.url)
            recorded = elapsed
            completedBytes += segment.bytes
        }
        await layers?.stop(); layers = nil
    }

    func finish() async throws -> URL {
        if let finishedURL { return finishedURL }
        if phase == .recording { try await pause() }
        guard phase == .paused, !segments.isEmpty else { throw Failure.empty }
        phase = .stopping
        defer { if phase != .finished { phase = .paused } }
        let url = source.directory.appendingPathComponent("recording.mp4")
        try await CaptureVideoService.join(segments, to: url)
        finishedURL = url
        phase = .finished
        return url
    }

    private func startClock() {
        let start = ContinuousClock.now
        clock = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .milliseconds(500)) } catch { return }
                guard let self, self.phase == .recording else { return }
                let duration = start.duration(to: .now).components
                self.elapsed = self.recorded + Double(duration.seconds) + Double(duration.attoseconds) / 1e18
                do { try self.checkTarget() } catch {
                    self.interrupted(error.localizedDescription)
                    return
                }
                if self.elapsed >= 7200 || self.completedBytes + (self.segment?.bytes ?? 0) >= 2_000_000_000
                    || self.segments.count >= 64
                {
                    self.interrupted("Recording limit reached. Stop to save this video, then start a new recording.")
                    return
                }
            }
        }
    }

    private func checkTarget() throws {
        if let status = segment?.screenStatus, status == .blank || status == .suspended || status == .stopped {
            throw Failure.sourceUnavailable
        }
        if phase == .recording, options.camera, layers?.overlays.cameraIsFresh != true {
            throw CaptureRecordingCamera.Failure.unavailable
        }
        guard CGPreflightScreenCaptureAccess(), NSScreen.screens.contains(where: {
            $0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID == displayID
        }) else { throw CaptureScreenService.Failure.displayChanged }
        if let windowID {
            let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
                as? [[String: Any]] ?? []
            guard windows.contains(where: {
                $0[kCGWindowNumber as String] as? UInt32 == windowID && $0[kCGWindowIsOnscreen as String] as? Bool == true
            }) else {
                throw Failure.windowUnavailable
            }
        }
    }

    enum Failure: LocalizedError {
        case empty, windowUnavailable, sourceUnavailable
        var errorDescription: String? {
            switch self {
            case .empty: "No completed recording segment is available. Resume recording and try again."
            case .windowUnavailable: "The recorded window is hidden or closed. Restore it to resume recording."
            case .sourceUnavailable: "Capture updates stopped. Restore the source, then resume or save this recording."
            }
        }
    }
}
