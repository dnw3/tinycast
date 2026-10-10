import AVFoundation
import Synchronization

final class CaptureEncodingCancellation: @unchecked Sendable {
    private let writer: AVAssetWriter
    private let reader: AVAssetReader?
    private let cancelled = Mutex(false)

    init(writer: AVAssetWriter, reader: AVAssetReader? = nil) {
        self.writer = writer; self.reader = reader
    }

    // Only cancellation crosses threads; configuration and samples remain owned by the encoding task.
    func cancel() {
        guard cancelled.withLock({ value in
            guard !value else { return false }
            value = true
            return true
        }) else { return }
        reader?.cancelReading()
        writer.cancelWriting()
    }

    nonisolated func finish(within duration: Duration = .seconds(15)) async throws {
        let expired = Mutex(false)
        let deadline = Task.detached {
            do { try await Task.sleep(for: duration) } catch { return }
            expired.withLock { $0 = true }
            self.cancel()
        }
        defer { deadline.cancel() }
        await writer.finishWriting()
        try Task.checkCancellation()
        guard !expired.withLock({ $0 }) else { throw CaptureRecordingBuffers.Failure.encoderStalled }
        guard writer.status == .completed else { throw writer.error ?? CaptureVideoError.invalidMedia }
    }
}
