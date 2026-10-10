import AppKit
import AVKit
import QuickLookUI

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
        let size = CGSize(width: metrics.scaled(Theme.Size.captureEditor.width),
            height: metrics.scaled(Theme.Size.captureEditor.height))
        let window = Window(contentRect: CGRect(origin: .zero, size: size),
            styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.title = "Capture Preview · \(entry.subtitle)"
        window.isReleasedWhenClosed = false
        window.isRestorable = false
        window.contentMinSize = Theme.Size.captureEditorMinimum
        window.delegate = self
        if entry.animationDuration != nil {
            let imageView = NSImageView(frame: CGRect(origin: .zero, size: size))
            imageView.imageScaling = .scaleProportionallyUpOrDown
            imageView.setAccessibilityLabel("Animated GIF Preview")
            window.contentView = imageView
            self.imageView = imageView
            playAnimation(entry, source: source)
        } else if entry.videoDuration != nil {
            let player = AVPlayer(url: source.directory.appendingPathComponent(entry.filename))
            let view = AVPlayerView(frame: CGRect(origin: .zero, size: size))
            view.player = player
            view.controlsStyle = .floating
            window.contentView = view
            self.player = player
            player.play()
        } else {
            let preview = QLPreviewView(frame: CGRect(origin: .zero, size: size), style: .normal) ?? QLPreviewView()
            preview.autostarts = true
            preview.shouldCloseWithWindow = false
            preview.previewItem = source.directory.appendingPathComponent(entry.filename) as NSURL
            window.contentView = preview
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

    private func playAnimation(_ entry: CaptureHistoryEntry, source: CaptureSource) {
        animationTask = Task { [weak self] in
            do {
                while !Task.isCancelled {
                    for try await frame in CaptureGIFService.frames(source.directory.appendingPathComponent(entry.filename)) {
                        try Task.checkCancellation()
                        self?.imageView?.image = NSImage(cgImage: frame, size: NSSize(width: frame.width, height: frame.height))
                    }
                }
            } catch is CancellationError {} catch {
                self?.window?.contentView = NSTextField(wrappingLabelWithString:
                    "GIF preview could not load. \(error.localizedDescription)")
            }
        }
    }

    isolated deinit { animationTask?.cancel() }

    private final class Window: NSWindow {
        override func cancelOperation(_ sender: Any?) { performClose(sender) }
    }
}
