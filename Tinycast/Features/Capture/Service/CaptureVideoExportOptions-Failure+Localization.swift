import Foundation

extension CaptureVideoExportOptions.Failure: LocalizedError {
    var errorDescription: String? {
        String(localized: "GIF export is limited to 30 seconds and 64 million frame pixels. Trim the video or choose a smaller GIF size.")
    }
}
