import CoreMedia
import Synchronization

final class CaptureRecordingOverlays: Sendable {
    struct Snapshot: Sendable {
        var camera: CaptureRecordingBuffers.Sample?
        var cameraReceived = CMTime.zero
        var key: String?
        var expires = CMTime.zero
        var keyEvents = 0
        var keyCaptions = 0
    }
    private let current = Mutex(Snapshot())

    func camera(_ sample: CaptureRecordingBuffers.Sample) {
        current.withLock { $0.camera = sample; $0.cameraReceived = CMClockGetTime(CMClockGetHostTimeClock()) }
    }
    var cameraIsFresh: Bool {
        current.withLock { $0.camera != nil && (CMClockGetTime(CMClockGetHostTimeClock()) - $0.cameraReceived).seconds < 2 }
    }
    func key(_ text: String?, at time: CMTime) {
        current.withLock {
            $0.key = text; $0.expires = time + CMTime(value: 6, timescale: 5)
            $0.keyEvents += 1
            if text != nil { $0.keyCaptions += 1 }
        }
    }
    var keyboardCounts: (events: Int, captions: Int) { current.withLock { ($0.keyEvents, $0.keyCaptions) } }
    func snapshot(at time: CMTime) -> Snapshot {
        current.withLock {
            if time >= $0.expires { $0.key = nil }
            return $0
        }
    }
    func clear() { current.withLock { $0 = Snapshot() } }
}
