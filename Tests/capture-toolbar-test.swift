import AppKit
import SwiftUI

@main
struct CaptureToolbarTests {
    @MainActor private final class Measurement {
        var glyph = CGRect.zero
    }

    @MainActor static func main() {
        NSApplication.shared.setActivationPolicy(.prohibited)
        for size in InterfaceSize.allCases {
            let metrics = size.metrics, side = metrics.scaled(Theme.Size.captureTool)
            for symbol in ["camera", "textformat", "rectangle", "square.and.arrow.down", "ellipsis", "arrow.up.right", "xmark"] {
                for kind in 0..<3 {
                    let measured = Measurement()
                    let glyph = CaptureToolbarGlyph(symbol: symbol)
                        .onGeometryChange(for: CGRect.self) { $0.frame(in: .named("cell")) } action: {
                            measured.glyph = $0
                        }
                    let content: AnyView
                    switch kind {
                    case 0:
                        content = AnyView(Button {} label: { glyph }.buttonStyle(CaptureToolbarButtonStyle()))
                    case 1:
                        content = AnyView(Menu { Button("Action") {} } label: { glyph }
                            .menuStyle(CaptureToolbarMenuStyle()))
                    default:
                        content = AnyView(Menu { Button("Alternative") {} } label: { glyph } primaryAction: {}
                            .menuStyle(CaptureToolbarMenuStyle()))
                    }
                    let host = NSHostingView(rootView: content.coordinateSpace(name: "cell").environment(\.metrics, metrics))
                    let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: side, height: side),
                        styleMask: [], backing: .buffered, defer: false)
                    window.contentView = host
                    host.layoutSubtreeIfNeeded()
                    RunLoop.main.run(until: Date().addingTimeInterval(0.03))
                    let fitting = host.fittingSize
                    precondition(abs(fitting.width - side) < 0.1 && abs(fitting.height - side) < 0.1,
                        "\(size) \(symbol) kind \(kind): unequal control cell \(fitting)")
                    precondition(abs(measured.glyph.midX - side / 2) < 0.1
                        && abs(measured.glyph.midY - side / 2) < 0.1,
                        "\(size) \(symbol) kind \(kind): off-center glyph \(measured.glyph)")
                    window.contentView = nil
                }
            }
        }
        print("Capture toolbar: equal cells and centered glyphs for buttons, menus and primary actions at all sizes")
    }
}
