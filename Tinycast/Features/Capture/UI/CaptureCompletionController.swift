import AppKit
import SwiftUI

@MainActor
final class CaptureCompletionController {
    private var panel: NSPanel?
    private var dismissal: Task<Void, Never>?
    private var hovering = false

    func show(_ entry: CaptureHistoryEntry, coordinator: CaptureCoordinator) {
        close()
        let metrics = coordinator.metrics
        guard coordinator.settings.showsCompletionThumbnail, let screen = NSScreen.underCursor ?? NSScreen.main else { return }
        let size = CGSize(width: metrics.scaled(Theme.Size.captureCompletionThumbnail.width),
            height: metrics.scaled(Theme.Size.captureCompletionThumbnail.height))
        let frame = screen.visibleFrame
        let panel = Panel(contentRect: CGRect(x: frame.maxX - size.width - metrics.spacing.xxl,
            y: frame.minY + metrics.spacing.xxl, width: size.width, height: size.height),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .floating
        panel.title = "Capture Complete"
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        panel.onDismiss = { [weak self] in self?.close() }
        let hosting = NSHostingView(rootView: Preview(entry: entry, coordinator: coordinator,
            onHover: { [weak self] in self?.hovering = $0 }, onClose: { [weak self] in self?.close() })
            .environment(\.metrics, metrics))
        hosting.sizingOptions = []
        panel.contentView = hosting
        panel.setContentSize(size)
        panel.orderFrontRegardless()
        self.panel = panel
        dismissal = Task { [weak self] in
            var remaining = 8
            while remaining > 0 {
                do { try await Task.sleep(for: .seconds(1)) } catch { return }
                guard let self else { return }
                remaining = self.hovering ? 8 : remaining - 1
            }
            self?.close()
        }
    }

    func close() {
        dismissal?.cancel(); dismissal = nil
        panel?.orderOut(nil); panel?.contentView = nil; panel = nil
        hovering = false
    }

    isolated deinit { dismissal?.cancel() }

    private final class Panel: NSPanel {
        var onDismiss: () -> Void = {}
        override var canBecomeKey: Bool { true }
        override var canBecomeMain: Bool { false }
        override func cancelOperation(_ sender: Any?) { onDismiss() }
    }

    private struct Preview: View {
        let entry: CaptureHistoryEntry
        let coordinator: CaptureCoordinator
        let onHover: (Bool) -> Void
        let onClose: () -> Void
        @State private var image: NSImage?
        @Environment(\.metrics) private var metrics

        var body: some View {
            Button {
                onClose()
                coordinator.openHistory(entry)
            } label: {
                Group {
                    if let image { Image(nsImage: image).resizable().scaledToFit() } else { ProgressView().controlSize(.small) }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(metrics.spacing.md)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Reopen capture, \(entry.title), \(entry.subtitle)")
            .help("Click to reopen · Drag to copy the final file")
            .onDrag { CaptureFileProvider.make(entry, repository: coordinator.repository) }
            .overlay(alignment: .topTrailing) {
                CaptureIconButton(title: "Dismiss Capture Thumbnail", symbol: "xmark", action: onClose)
                    .padding(metrics.spacing.xxs)
            }
            .background(Theme.Colors.panelScrim).background(GlassEffectView())
            .clipShape(RoundedRectangle(cornerRadius: metrics.radius.row))
            .onHover(perform: onHover)
            .task {
                let url = coordinator.repository.history.appendingPathComponent("\(entry.id)/thumbnail.png")
                image = await ImageThumbnail.loadAsync(url, maxPixel: 256)
            }
        }
    }
}
