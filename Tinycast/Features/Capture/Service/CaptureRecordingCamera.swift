import AVFoundation

// Session configuration stays on its worker; the delegate writes only to the locked overlay state.
final class CaptureRecordingCamera: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate,
    @unchecked Sendable
{
    private let session = AVCaptureSession()
    private let overlays: CaptureRecordingOverlays
    private let queue = DispatchQueue(label: "Capture.Camera.Samples")

    private init(overlays: CaptureRecordingOverlays) { self.overlays = overlays }

    nonisolated static func start(overlays: CaptureRecordingOverlays) async throws -> CaptureRecordingCamera {
        let worker = Task.detached(priority: .userInitiated) {
            let camera = CaptureRecordingCamera(overlays: overlays)
            try camera.configure()
            try Task.checkCancellation()
            camera.session.startRunning()
            if Task.isCancelled {
                camera.session.stopRunning()
                throw CancellationError()
            }
            guard camera.session.isRunning else { throw Failure.unavailable }
            return camera
        }
        let camera = try await withTaskCancellationHandler {
            try await worker.value
        } onCancel: {
            worker.cancel()
        }
        do {
            let deadline = ContinuousClock.now.advanced(by: .seconds(5))
            while !overlays.cameraIsFresh {
                guard .now < deadline else { throw Failure.unavailable }
                try await Task.sleep(for: .milliseconds(20))
            }
            try Task.checkCancellation()
            return camera
        } catch {
            await camera.stop()
            throw error
        }
    }

    nonisolated func stop() async {
        await Task.detached { self.session.stopRunning() }.value
        overlays.clear()
    }

    @MainActor func preview(mirrored: Bool) -> AVCaptureVideoPreviewLayer {
        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        if let connection = layer.connection, connection.isVideoMirroringSupported {
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = mirrored
        }
        return layer
    }

    private func configure() throws {
        guard let device = AVCaptureDevice.default(for: .video) else { throw Failure.unavailable }
        let input = try AVCaptureDeviceInput(device: device), output = AVCaptureVideoDataOutput()
        output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        output.alwaysDiscardsLateVideoFrames = true
        session.sessionPreset = .vga640x480
        guard session.canAddInput(input), session.canAddOutput(output) else { throw Failure.unavailable }
        session.addInput(input); session.addOutput(output)
        output.setSampleBufferDelegate(self, queue: queue)
    }

    func captureOutput(
        _ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard sampleBuffer.isValid, sampleBuffer.dataReadiness == .ready, sampleBuffer.imageBuffer != nil
        else { return }
        do {
            // The camera lends immutable pixels; a sample copy separates metadata ownership.
            nonisolated(unsafe) let copy = try CMSampleBuffer(copying: sampleBuffer)
            overlays.camera(.init(unsafeBuffer: copy))
        } catch { overlays.clear() }
    }

    enum Failure: LocalizedError {
        case unavailable
        var errorDescription: String? {
            String(
                localized: "The camera is unavailable. Close other camera apps or turn Camera off and retry.")
        }
    }
}
