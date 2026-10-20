import AppKit
import SwiftUI

/// Every capture bar is a `row` surface padded by `xs`, so the tools inside nest concentrically.
@MainActor
enum CaptureChrome {
    /// The app-window recipe `AppWindowController` uses: one surface, the title kept off the bar.
    static func adopt(_ window: NSWindow) {
        window.styleMask.insert(.fullSizeContentView)
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
    }

    /// An empty compact toolbar, only for its 40pt band: a header row fits beside the lights.
    static func reserveTitleBand(_ window: NSWindow) {
        let toolbar = NSToolbar(identifier: "CaptureTitleBand")
        toolbar.allowsUserCustomization = false
        toolbar.allowsDisplayModeCustomization = false
        window.toolbar = toolbar
        window.toolbarStyle = .unifiedCompact
    }

    static func barShape(_ metrics: InterfaceMetrics) -> RoundedRectangle {
        RoundedRectangle(cornerRadius: metrics.radius.row, style: .continuous)
    }

    static func toolShape(_ metrics: InterfaceMetrics) -> RoundedRectangle {
        RoundedRectangle(cornerRadius: metrics.radius.row - metrics.spacing.xs, style: .continuous)
    }
}

struct CaptureToolbarButtonStyle: ButtonStyle {
    var selected = false
    /// A value such as `1×` or `100%` keeps the tool's height and grows to its text.
    var fitsContent = false
    @Environment(\.metrics) private var metrics

    func makeBody(configuration: Configuration) -> some View {
        Surface(label: configuration.label, pressed: configuration.isPressed,
            selected: selected, fitsContent: fitsContent, metrics: metrics)
    }

    private struct Surface: View {
        let label: Configuration.Label
        let pressed: Bool
        let selected: Bool
        let fitsContent: Bool
        let metrics: InterfaceMetrics
        @State private var hovered = false

        var body: some View {
            sized
                .background(selected || pressed ? Theme.Colors.selection : hovered ? Theme.Colors.rowHover : .clear)
                .clipShape(CaptureChrome.toolShape(metrics))
                .contentShape(.rect)
                .onHover { hovered = $0 }
        }

        @ViewBuilder private var sized: some View {
            let tool = metrics.scaled(Theme.Size.captureTool)
            if fitsContent {
                label.padding(.horizontal, metrics.spacing.sm).frame(minWidth: tool, minHeight: tool, maxHeight: tool)
            } else {
                label.frame(width: tool, height: tool)
            }
        }
    }
}
