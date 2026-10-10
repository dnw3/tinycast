import AppKit
import Carbon.HIToolbox
import CoreMedia
import OSLog

@MainActor
final class CaptureRecordingLayers {
    let overlays = CaptureRecordingOverlays()
    private(set) var camera: CaptureRecordingCamera?
    private var monitor: Any?

    func start(options: CaptureRecordingOptions) async throws {
        if options.camera { camera = try await CaptureRecordingCamera.start(overlays: overlays) }
        guard options.keys != .off else { return }
        let overlays = overlays, mode = options.keys
        monitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { event in
            guard !IsSecureEventInputEnabled() else {
                overlays.key(nil, at: CMClockGetTime(CMClockGetHostTimeClock()))
                return
            }
            let flags = event.modifierFlags
            let text = CaptureKeystrokePolicy.label(mode: mode, keyCode: event.keyCode,
                characters: event.charactersIgnoringModifiers, command: flags.contains(.command),
                control: flags.contains(.control), option: flags.contains(.option), shift: flags.contains(.shift),
                repeated: event.isARepeat, secure: false)
            overlays.key(text, at: CMClockGetTime(CMClockGetHostTimeClock()))
        }
        guard monitor != nil else {
            await stop()
            throw Failure.keyboardUnavailable
        }
    }

    func stop() async {
        if let monitor {
            NSEvent.removeMonitor(monitor); self.monitor = nil
            let counts = overlays.keyboardCounts
            Logger(subsystem: Bundle.main.bundleIdentifier!, category: "Capture").notice(
                "Recording key display stopped: events=\(counts.events), captions=\(counts.captions)")
        }
        if let camera { await camera.stop(); self.camera = nil }
        overlays.clear()
    }

    isolated deinit { if let monitor { NSEvent.removeMonitor(monitor) } }

    enum Failure: LocalizedError {
        case keyboardUnavailable
        var errorDescription: String? {
            "Keyboard display needs Accessibility permission. Turn Keys off or allow access and retry."
        }
    }
}
