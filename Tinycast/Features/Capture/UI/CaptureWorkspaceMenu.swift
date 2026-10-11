import SwiftUI

struct CaptureWorkspaceMenu: View {
    @Environment(CaptureCoordinator.self) private var coordinator
    let workspace: CaptureWorkspaceState

    private var symbol: String {
        switch workspace.request.mode {
        case .screenshot: "camera"
        case .scrolling: "arrow.down.right.and.arrow.up.left"
        case .recording: "record.circle"
        }
    }

    var body: some View {
        Menu {
            Section("Capture Area") {
                scopeButton(String(localized: "Region"), scope: .region)
                scopeButton(String(localized: "Window"), scope: .window)
                scopeButton(String(localized: "Screen"), scope: .screen)
            }
            Section("Capture Mode") {
                modeButton(String(localized: "Screenshot"), mode: .screenshot)
                modeButton(String(localized: "Scrolling Screenshot"), mode: .scrolling)
                modeButton(String(localized: "Record Screen"), mode: .recording)
            }
            Divider()
            Button(
                workspace.selectionOptions
                    ? String(localized: "Hide Selection Options") : String(localized: "Selection Options")
            ) {
                workspace.selectionOptions.toggle()
            }
        } label: {
            CaptureToolbarGlyph(symbol: symbol)
        }
        .menuStyle(CaptureToolbarMenuStyle()).fixedSize().accessibilityLabel(
            String(localized: "Capture Area and Mode")
        )
        .tooltip(String(localized: "Capture Area and Mode"))
    }

    private func scopeButton(_ title: String, scope: CaptureRequest.Scope) -> some View {
        Button {
            coordinator.setCaptureScope(scope)
        } label: {
            if workspace.request.scope == scope {
                Label(title, systemImage: "checkmark")
            } else {
                Text(title)
            }
        }
    }

    private func modeButton(_ title: String, mode: CaptureRequest.Mode) -> some View {
        Button {
            coordinator.setCaptureMode(mode)
        } label: {
            if workspace.request.mode == mode { Label(title, systemImage: "checkmark") } else { Text(title) }
        }
    }

}
