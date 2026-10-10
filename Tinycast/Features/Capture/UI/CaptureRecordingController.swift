import AppKit
import SwiftUI

@MainActor
final class CaptureRecordingController {
    private var panel: NSPanel?

    func show(_ session: CaptureRecordingSession, coordinator: CaptureCoordinator) {
        close()
        let metrics = coordinator.metrics
        let size = CGSize(width: metrics.scaled(Theme.Size.captureRecordingBar.width),
            height: metrics.scaled(Theme.Size.captureRecordingBar.height))
        let screen = NSScreen.screens.first(where: { $0.frame.intersects(session.frame) }) ?? NSScreen.main
        let visible = screen?.visibleFrame ?? session.frame
        let placement = CaptureControlPlacement.frame(region: session.frame, size: size,
            screens: [visible], gap: metrics.spacing.md)
            ?? CGRect(x: visible.midX - size.width / 2, y: visible.maxY - size.height - metrics.spacing.md,
                width: size.width, height: size.height)
        let panel = Panel(contentRect: placement, styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false)
        panel.level = .floating
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        let hosting = NSHostingView(rootView: Controls(session: session)
            .environment(coordinator).environment(\.metrics, metrics))
        hosting.sizingOptions = []
        panel.contentView = hosting
        panel.setContentSize(size)
        panel.orderFrontRegardless()
        self.panel = panel
    }

    func close() {
        panel?.orderOut(nil)
        panel?.contentView = nil
        panel = nil
    }

    private final class Panel: NSPanel {
        override var canBecomeKey: Bool { true }
        override var canBecomeMain: Bool { false }
    }

    private struct Controls: View {
        let session: CaptureRecordingSession
        @Environment(CaptureCoordinator.self) private var coordinator
        @Environment(\.metrics) private var metrics

        var body: some View {
            VStack(alignment: .leading, spacing: metrics.spacing.xs) {
                HStack(spacing: metrics.spacing.md) {
                    if let camera = session.cameraPreview {
                        CameraPreview(camera: camera, mirrored: session.options.mirrorCamera)
                            .frame(width: metrics.scaled(Theme.Size.captureTool), height: metrics.scaled(Theme.Size.captureTool))
                            .clipShape(Circle()).accessibilityLabel("Live Camera Preview")
                    }
                    Text(session.phase == .paused ? "Paused" : "Recording")
                    Text(Duration.seconds(session.elapsed).formatted(.time(pattern: .minuteSecond))).monospacedDigit()
                    Spacer()
                    if session.phase == .recording || session.phase == .paused {
                        CaptureIconButton(title: session.phase == .paused ? "Resume Recording" : "Pause Recording",
                            symbol: session.phase == .paused ? "play.fill" : "pause.fill") { coordinator.toggleRecordingPause() }
                        CaptureIconButton(title: "Stop Recording", symbol: "stop.fill") { coordinator.finishRecording() }
                    } else { ProgressView().controlSize(.small) }
                }
                Text(session.notice ?? "\(session.size.width) × \(session.size.height) · \(session.options.framesPerSecond) fps")
                    .foregroundStyle(Theme.Colors.textSecondary).lineLimit(2)
            }
            .font(metrics.typography.bar).padding(metrics.spacing.lg)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.Colors.panelScrim).background(GlassEffectView())
            .clipShape(RoundedRectangle(cornerRadius: metrics.radius.row))
        }
    }

    private struct CameraPreview: NSViewRepresentable {
        let camera: CaptureRecordingCamera
        let mirrored: Bool
        func makeNSView(context: Context) -> NSView {
            let view = NSView()
            view.wantsLayer = true
            view.layer = camera.preview(mirrored: mirrored)
            return view
        }
        func updateNSView(_ view: NSView, context: Context) {}
    }
}
