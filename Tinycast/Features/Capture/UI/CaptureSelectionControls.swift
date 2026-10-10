import SwiftUI

struct CaptureSelectionControls: View {
    @Bindable var workspace: CaptureWorkspaceState
    @Environment(CaptureCoordinator.self) private var coordinator
    @Environment(\.metrics) private var metrics
    @State private var width = 0.0
    @State private var height = 0.0

    var body: some View {
        CaptureToolFlow(spacing: metrics.spacing.md) {
            if NSScreen.screens.count > 1 {
                Menu {
                    if workspace.request.mode == .screenshot {
                        Button("Select Across Displays") { coordinator.captureAcrossDisplays(all: false) }
                        Button("Capture All Displays") { coordinator.captureAcrossDisplays(all: true) }
                        Divider()
                    }
                    ForEach(NSScreen.screens, id: \.self) { screen in
                        Button {
                            coordinator.switchCaptureScreen(screen)
                        } label: {
                            if screen.frame == workspace.target.screenFrame {
                                Label(screen.localizedName, systemImage: "checkmark")
                            } else { Text(screen.localizedName) }
                        }
                    }
                } label: {
                    SymbolImage(name: "display.2", size: metrics.scaled(Theme.Size.captureGlyph))
                        .frame(width: metrics.scaled(Theme.Size.captureTool), height: metrics.scaled(Theme.Size.captureTool))
                }
                .menuStyle(.borderlessButton).fixedSize().accessibilityLabel("Display")
                .tooltip("Choose Display")
            }
            Picker("Ratio", selection: $workspace.aspect) {
                ForEach(CaptureSelectionConstraint.Aspect.allCases, id: \.self) { Text($0.title).tag($0) }
            }.fixedSize()
            if coordinator.editor != nil {
                HStack(spacing: metrics.spacing.xxs) {
                    TextField("Width", value: $width, format: .number)
                        .frame(width: metrics.scaled(Theme.Size.capturePropertyField))
                        .onSubmit { resize(widthChanged: true) }.accessibilityLabel("Width in pixels")
                    Text("×")
                    TextField("Height", value: $height, format: .number)
                        .frame(width: metrics.scaled(Theme.Size.capturePropertyField))
                        .onSubmit { resize(widthChanged: false) }.accessibilityLabel("Height in pixels")
                    Text("px")
                }.fixedSize()
            }
            Toggle("Snap", isOn: $workspace.snaps).toggleStyle(.checkbox)
                .tooltip("Snap to screen and window edges · Option disables snapping")
            CaptureIconButton(title: "Select Element", symbol: "scope", selected: workspace.choosingElement) {
                coordinator.chooseCaptureElement()
            }
            CaptureIconButton(title: "Use Last Region", symbol: "arrow.counterclockwise") { coordinator.restoreCaptureRegion() }
                .disabled(workspace.lastRegion == nil)
            Menu {
                ForEach([3, 5, 10], id: \.self) { seconds in
                    Button("Capture in \(seconds) Seconds") { coordinator.captureAfterDelay(seconds) }
                }
            } label: {
                SymbolImage(name: "timer", size: metrics.scaled(Theme.Size.captureGlyph))
                    .frame(width: metrics.scaled(Theme.Size.captureTool), height: metrics.scaled(Theme.Size.captureTool))
            }
            .menuStyle(.borderlessButton).fixedSize().accessibilityLabel("Capture After Delay")
            .tooltip("Capture After Delay · take a new image using this selection")
        }
        .disabled(workspace.busy || coordinator.editor?.busy == true || workspace.choosingWindow)
        .onAppear { syncSize() }
        .onChange(of: coordinator.editor?.document.revision) { syncSize() }
        .onChange(of: coordinator.editor?.document.id) { syncSize() }
        .onChange(of: workspace.aspect) { if width > 0 { resize(widthChanged: true) } }
    }

    private func syncSize() {
        width = Double(coordinator.editor?.document.outputBounds.width ?? 0)
        height = Double(coordinator.editor?.document.outputBounds.height ?? 0)
    }

    private func resize(widthChanged: Bool) {
        if let ratio = workspace.aspect.ratio {
            if widthChanged { height = (width / Double(ratio)).rounded() } else { width = (height * Double(ratio)).rounded() }
        }
        coordinator.sizeCaptureRegion(CGSize(width: width, height: height))
        syncSize()
    }
}
