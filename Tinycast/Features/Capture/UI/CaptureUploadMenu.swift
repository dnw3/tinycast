import SwiftUI

struct CaptureUploadMenu: View {
    @Environment(CaptureCoordinator.self) private var coordinator
    var video = false

    var body: some View {
        if let destination = coordinator.settings.uploadDestination {
            Button("Upload to \(destination.title) and Copy Link") { coordinator.uploadCapture(video: video) }
                .disabled(video && destination.kind == .imgbb && coordinator.video?.exportOptions.format != .gif)
        }
        Button("Upload Settings…") { coordinator.showUploadSettings() }
    }
}
