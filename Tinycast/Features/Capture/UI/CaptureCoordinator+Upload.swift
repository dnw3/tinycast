import AppKit

extension CaptureCoordinator {
    func connectUpload(_ destination: CaptureUploadDestination, clientSecret: String) {
        guard uploadAuthorization == nil else { return }
        uploadConnecting = true
        uploadNotice = nil
        uploadAuthorization = Task { [weak self] in
            guard let self else { return }
            defer { self.uploadConnecting = false; self.uploadAuthorization = nil }
            do {
                let credential = try await CaptureDriveAuthorization.connect(
                    destination: destination, clientSecret: clientSecret
                ) {
                    NSWorkspace.shared.open($0)
                }
                try Task.checkCancellation()
                try self.settings.saveUpload(destination, credential: credential)
            } catch is CancellationError { self.uploadNotice = "Sign-in cancelled" } catch {
                self.uploadNotice = error.localizedDescription
            }
        }
    }
}
