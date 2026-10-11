import SwiftUI

struct CaptureToolbarButtonStyle: ButtonStyle {
    var selected = false
    @Environment(\.metrics) private var metrics

    func makeBody(configuration: Configuration) -> some View {
        Surface(label: configuration.label, pressed: configuration.isPressed,
            selected: selected, metrics: metrics)
    }

    private struct Surface: View {
        let label: Configuration.Label
        let pressed: Bool
        let selected: Bool
        let metrics: InterfaceMetrics
        @State private var hovered = false

        var body: some View {
            label.frame(width: metrics.scaled(Theme.Size.captureTool), height: metrics.scaled(Theme.Size.captureTool))
                .background(selected || pressed ? Theme.Colors.selection : hovered ? Theme.Colors.rowHover : .clear)
                .clipShape(RoundedRectangle(cornerRadius: metrics.radius.barControl))
                .contentShape(.rect)
                .onHover { hovered = $0 }
        }
    }
}
