import Foundation

struct CaptureRecordingOptions: Equatable, Sendable {
    enum Completion: String, CaseIterable, Sendable { case preview, saveFile, copyFile }
    enum Keys: String, CaseIterable, Sendable { case off, shortcuts, all }
    enum CameraPosition: String, CaseIterable, Sendable { case topLeft, topRight, bottomLeft, bottomRight }
    var systemAudio = false
    var microphone = false
    var cursor = true
    var mouseClicks = false
    var framesPerSecond = 30
    var delay = 0
    var completion = Completion.preview
    var camera = false
    var cameraPosition = CameraPosition.bottomRight
    var cameraFraction = 0.25
    var mirrorCamera = true
    var keys = Keys.off

    func validated() throws -> Self {
        guard [15, 30, 60].contains(framesPerSecond), [0, 3, 5, 10].contains(delay),
            cameraFraction.isFinite, (0.15...0.35).contains(cameraFraction) else {
            throw CaptureVideoError.invalidConfiguration
        }
        return self
    }

    func outputSize(_ source: CGSize) throws -> CapturePixelSize {
        guard source.width.isFinite, source.height.isFinite, source.width >= 2, source.height >= 2 else {
            throw CaptureVideoError.invalidConfiguration
        }
        let scale = min(1, 3840 / max(source.width, source.height))
        return try CapturePixelSize(
            width: max(2, Int(source.width * scale) / 2 * 2),
            height: max(2, Int(source.height * scale) / 2 * 2))
    }
}
