import SwiftUI

struct CaptureToolbarGlyph: View {
    let symbol: String
    @Environment(\.metrics) private var metrics
    @Environment(\.locale) private var locale

    private var opticalSize: CGFloat {
        switch symbol {
        case "xmark", "arrow.up.right", "arrow.up.left.and.arrow.down.right": Theme.Size.captureCompactGlyph
        default: Theme.Size.captureGlyph
        }
    }

    var body: some View {
        SymbolImage(name: symbol, size: metrics.scaled(opticalSize), monochrome: true)
            .environment(\.locale, symbol == "textformat" ? Locale(identifier: "en") : locale)
            .frame(width: metrics.scaled(Theme.Size.captureGlyph), height: metrics.scaled(Theme.Size.captureGlyph))
    }
}
