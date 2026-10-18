import SwiftUI

struct CaptureCensorTools: View {
    let state: CaptureEditorState
    @Environment(CaptureCoordinator.self) private var coordinator

    var body: some View {
        ForEach([CaptureAnnotation.Tool.cover, .pixelate, .blur, .erase], id: \.self) { tool in
            Button {
                state.selectTool(tool)
                state.notice =
                    tool == .blur || tool == .pixelate
                    ? String(
                        localized: "Visual effect only. Use Solid or Erase to conceal sensitive information.")
                    : nil
            } label: {
                Label(
                    title(tool) + "  " + tool.key.uppercased(),
                    systemImage: state.tool == tool ? "checkmark" : tool.symbol)
            }
        }
        Divider()
        Button("Text Only…") { coordinator.suggestRedactions(.allText) }
    }

    private func title(_ tool: CaptureAnnotation.Tool) -> String {
        switch tool {
        case .cover: String(localized: "Solid")
        case .pixelate: String(localized: "Pixelate")
        case .blur: String(localized: "Blur")
        case .erase: String(localized: "Erase")
        default: Bundle.main.localizedString(forKey: tool.title, value: nil, table: nil)
        }
    }
}
