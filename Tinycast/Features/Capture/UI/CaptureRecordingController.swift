import AppKit
import SwiftUI

@MainActor
final class CaptureRecordingController {
    private var panel: NSPanel?

    func show(_ session: CaptureRecordingSession, coordinator: CaptureCoordinator) {
        close()
        let metrics = coordinator.metrics
        let size = CGSize(
            width: metrics.scaled(Theme.Size.captureRecordingBar.width),
            height: metrics.scaled(Theme.Size.captureRecordingBar.height))
        let screen = NSScreen.screens.first(where: { $0.frame.intersects(session.frame) }) ?? NSScreen.main
        let visible = screen?.visibleFrame ?? session.frame
        let placement =
            CaptureControlPlacement.frame(
                region: session.frame, size: size,
                screens: [visible], gap: metrics.spacing.md)
            ?? CGRect(
                x: visible.midX - size.width / 2, y: visible.maxY - size.height - metrics.spacing.md,
                width: size.width, height: size.height)
        let panel = Panel(
            contentRect: placement, styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false)
        panel.title = String(localized: "Recording Controls")
        panel.level = .floating
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        let hosting = NSHostingView(
            rootView: Controls(session: session)
                .environment(coordinator).environment(\.metrics, metrics))
        hosting.sizingOptions = []
        panel.contentView = hosting
        panel.setContentSize(size)
        panel.orderFrontRegardless()
        self.panel = panel
    }

    func focusExisting() -> Bool {
        guard let panel else { return false }
        panel.orderFrontRegardless()
        panel.makeKey()
        return true
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

        private var status: String {
            switch session.phase {
            case .starting: String(localized: "Starting…")
            case .recording: String(localized: "Recording")
            case .pausing: String(localized: "Pausing…")
            case .paused: String(localized: "Paused")
            case .stopping: String(localized: "Finishing…")
            case .finished: String(localized: "Recorded")
            }
        }

        var body: some View {
            VStack(alignment: .leading, spacing: metrics.spacing.xs) {
                HStack(spacing: metrics.spacing.md) {
                    if let camera = session.cameraPreview {
                        CameraPreview(camera: camera, mirrored: session.options.mirrorCamera)
                            .frame(
                                width: metrics.scaled(Theme.Size.captureTool),
                                height: metrics.scaled(Theme.Size.captureTool)
                            )
                            .clipShape(Circle()).accessibilityLabel(String(localized: "Live Camera Preview"))
                    }
                    if session.phase == .recording {
                        SymbolImage(name: "circle.fill", size: metrics.scaled(Theme.Size.captureCompactGlyph))
                            .foregroundStyle(Theme.Colors.destructive).accessibilityLabel(status)
                    } else {
                        Text(status)
                    }
                    Text(Duration.seconds(session.elapsed).formatted(.time(pattern: .minuteSecond)))
                        .monospacedDigit()
                    Spacer()
                    if session.phase == .recording || session.phase == .paused {
                        CaptureIconButton(
                            title: session.phase == .paused
                                ? String(localized: "Resume Recording")
                                : String(localized: "Pause Recording"),
                            symbol: session.phase == .paused ? "play.fill" : "pause.fill"
                        ) { coordinator.toggleRecordingPause() }
                        CaptureIconButton(title: String(localized: "Stop Recording"), symbol: "stop.fill") {
                            coordinator.finishRecording()
                        }
                    } else if session.phase == .finished {
                        CaptureIconButton(
                            title: String(localized: "Retry Opening Recording"), symbol: "arrow.clockwise"
                        ) {
                            coordinator.finishRecording()
                        }
                    } else {
                        ProgressView().controlSize(.small)
                    }
                    if session.phase == .recording || session.phase == .paused || session.phase == .finished {
                        Menu {
                            Button("Cancel Recording…") { coordinator.cancelRecording() }
                                .keyboardShortcut(.escape, modifiers: [])
                        } label: {
                            CaptureToolbarGlyph(symbol: "ellipsis")
                        }
                        .menuStyle(CaptureToolbarMenuStyle()).fixedSize()
                        .accessibilityLabel(String(localized: "More Recording Actions")).tooltip(
                            String(localized: "More Recording Actions"))
                    }
                }
                Text(
                    session.notice
                        ?? "\(session.size.width) × \(session.size.height) · \(session.options.framesPerSecond) fps"
                )
                .foregroundStyle(Theme.Colors.textSecondary).lineLimit(2)
            }
            .font(metrics.typography.bar).padding(metrics.spacing.lg)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .captureGlass(metrics)
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
