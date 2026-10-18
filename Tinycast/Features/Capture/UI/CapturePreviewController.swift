import AppKit
import AVKit
import QuickLookUI
import SwiftUI

@MainActor
final class CapturePreviewController: NSObject, NSWindowDelegate {
    private let activation: ActivationPolicy
    private var window: NSWindow?
    private var preview: QLPreviewView?
    private var source: CaptureSource?
    private var animationTask: Task<Void, Never>?
    private var imageView: NSImageView?
    private var player: AVPlayer?

    init(activation: ActivationPolicy) { self.activation = activation }

    func show(_ entry: CaptureHistoryEntry, source: CaptureSource, metrics: InterfaceMetrics) {
        close()
        self.source = source
        let size = CGSize(
            width: metrics.scaled(Theme.Size.captureEditor.width),
            height: metrics.scaled(Theme.Size.captureEditor.height))
        let window = Window(
            contentRect: CGRect(origin: .zero, size: size),
            styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.title = String(localized: "Capture Preview · \(entry.displaySubtitle)")
        window.isReleasedWhenClosed = false
        window.isRestorable = false
        window.contentMinSize = Theme.Size.captureEditorMinimum
        CaptureChrome.adopt(window)
        window.delegate = self
        if entry.animationDuration != nil {
            showAnimation(entry, source: source, in: window, metrics: metrics)
        } else if entry.videoDuration != nil {
            let player = AVPlayer(url: source.directory.appendingPathComponent(entry.filename))
            let view = AVPlayerView(frame: CGRect(origin: .zero, size: size))
            view.player = player
            view.controlsStyle = .floating
            window.contentView = Self.surface(view, metrics: metrics)
            self.player = player
            player.play()
        } else {
            let preview =
                QLPreviewView(frame: CGRect(origin: .zero, size: size), style: .normal) ?? QLPreviewView()
            preview.autostarts = true
            preview.shouldCloseWithWindow = false
            preview.previewItem = source.directory.appendingPathComponent(entry.filename) as NSURL
            window.contentView = Self.surface(preview, metrics: metrics)
            self.preview = preview
        }
        self.window = window
        window.center()
        activation.windowDidOpen(window)
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    func close() {
        guard let window else { return }
        animationTask?.cancel()
        animationTask = nil
        imageView?.image = nil
        imageView = nil
        player?.pause()
        player?.replaceCurrentItem(with: nil)
        player = nil
        preview?.close()
        window.delegate = nil
        window.close()
        window.contentView = nil
        activation.windowDidClose(window)
        self.window = nil
        preview = nil
        source = nil
    }

    func focusExisting() -> Bool {
        guard let window else { return false }
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        return true
    }

    func windowWillClose(_ notification: Notification) { close() }

    private func showAnimation(
        _ entry: CaptureHistoryEntry, source: CaptureSource, in window: NSWindow, metrics: InterfaceMetrics
    ) {
        let imageView = NSImageView(frame: window.contentLayoutRect)
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.setAccessibilityLabel(String(localized: "Animated GIF Preview"))
        window.contentView = Self.surface(imageView, metrics: metrics)
        self.imageView = imageView
        playAnimation(entry, source: source, in: window, metrics: metrics)
    }

    private func playAnimation(
        _ entry: CaptureHistoryEntry, source: CaptureSource, in window: NSWindow, metrics: InterfaceMetrics
    ) {
        animationTask?.cancel()
        animationTask = Task { [weak self, weak window] in
            do {
                while !Task.isCancelled {
                    for try await frame in CaptureGIFService.frames(
                        source.directory.appendingPathComponent(entry.filename))
                    {
                        try Task.checkCancellation()
                        self?.imageView?.image = NSImage(
                            cgImage: frame, size: NSSize(width: frame.width, height: frame.height))
                    }
                }
            } catch is CancellationError {} catch {
                guard let self, let window, self.window === window else { return }
                self.imageView = nil
                let failure = AnimationFailure(
                    message: Bundle.main.localizedString(
                        forKey: error.localizedDescription, value: nil, table: nil)
                ) { [weak self, weak window] in
                    guard let self, let window, self.window === window else { return }
                    self.showAnimation(entry, source: source, in: window, metrics: metrics)
                }
                window.contentView = Self.surface(
                    NSHostingView(rootView: failure.environment(\.metrics, metrics)), metrics: metrics)
            }
        }
    }

    isolated deinit { animationTask?.cancel() }

    private static func surface(_ content: NSView, metrics: InterfaceMetrics) -> NSView {
        let hosting = NSHostingView(
            rootView: Hosted(view: content)
                .clipShape(RoundedRectangle(cornerRadius: metrics.radius.row, style: .continuous))
                .padding(metrics.spacing.md)
                .captureWindowSurface())
        hosting.sizingOptions = []
        return hosting
    }

    private struct AnimationFailure: View {
        let message: String
        let retry: () -> Void
        @Environment(\.metrics) private var metrics

        var body: some View {
            VStack(spacing: metrics.spacing.md) {
                Text("Preview could not load")
                Text(message).foregroundStyle(Theme.Colors.textSecondary)
                Button("Retry Preview", action: retry)
                    .buttonStyle(.modalAction(.standard, fillsWidth: false))
            }
            .multilineTextAlignment(.center)
            .padding(metrics.spacing.lg).captureGlass(metrics)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private struct Hosted: NSViewRepresentable {
        let view: NSView
        func makeNSView(context: Context) -> NSView { view }
        func updateNSView(_ nsView: NSView, context: Context) {}
    }

    private final class Window: NSWindow {
        override func cancelOperation(_ sender: Any?) { performClose(sender) }
    }
}
