import AppKit
import SwiftUI

struct CaptureCodeResults: View {
    @Bindable var state: CaptureEditorState
    @Environment(\.metrics) private var metrics

    var body: some View {
        if state.codes.indices.contains(state.codeIndex) {
            let code = state.codes[state.codeIndex]
            HStack(spacing: metrics.spacing.sm) {
                Text(code).textSelection(.enabled).lineLimit(2)
                    .font(metrics.typography.bar).frame(maxWidth: .infinity, alignment: .leading)
                if state.codes.count > 1 {
                    Text("\(state.codeIndex + 1)/\(state.codes.count)").font(metrics.typography.bar)
                    CaptureIconButton(title: "Next Code", symbol: "chevron.right") {
                        state.codeIndex = (state.codeIndex + 1) % state.codes.count
                    }
                }
                CaptureIconButton(title: "Copy Code", symbol: "doc.on.doc") { Paster.copyPlainText(code) }
                if let url = URL(string: code), ["https", "http"].contains(url.scheme?.lowercased() ?? "") {
                    CaptureIconButton(title: "Open Link", symbol: "arrow.up.right.square") {
                        NSWorkspace.shared.open(url)
                    }
                }
                CaptureIconButton(title: "Dismiss Codes", symbol: "xmark") { state.codes = [] }
            }
            .padding(metrics.spacing.sm)
            .background(Theme.Colors.panelScrim, in: RoundedRectangle(cornerRadius: metrics.radius.row, style: .continuous))
        }
    }
}
