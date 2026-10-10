import SwiftUI

struct CaptureRecordingPreparation: View {
    @Environment(CaptureCoordinator.self) private var coordinator
    @Environment(\.metrics) private var metrics
    @Bindable var workspace: CaptureWorkspaceState

    var body: some View {
        HStack(spacing: metrics.spacing.xxs) {
            CaptureIconButton(title: workspace.recordingOptions.systemAudio ? "System Audio On" : "System Audio Off",
                symbol: workspace.recordingOptions.systemAudio ? "speaker.wave.2" : "speaker.slash",
                selected: workspace.recordingOptions.systemAudio) {
                workspace.recordingOptions.systemAudio.toggle()
            }
            CaptureIconButton(title: workspace.recordingOptions.microphone ? "Microphone On" : "Microphone Off",
                symbol: workspace.recordingOptions.microphone ? "mic" : "mic.slash",
                selected: workspace.recordingOptions.microphone) {
                workspace.recordingOptions.microphone.toggle()
            }
            CaptureIconButton(title: workspace.recordingOptions.camera ? "Camera On" : "Camera Off",
                symbol: workspace.recordingOptions.camera ? "video" : "video.slash",
                selected: workspace.recordingOptions.camera) { workspace.recordingOptions.camera.toggle() }
            CaptureIconButton(title: workspace.recordingOptions.keys == .off ? "Keyboard Display Off" : "Keyboard Display On",
                symbol: "keyboard", selected: workspace.recordingOptions.keys != .off) {
                workspace.recordingOptions.keys = workspace.recordingOptions.keys == .off ? .shortcuts : .off
            }
            Menu {
                Toggle("Show Cursor", isOn: $workspace.recordingOptions.cursor)
                Toggle("Show Mouse Clicks", isOn: $workspace.recordingOptions.mouseClicks)
                Picker("Keyboard Display", selection: $workspace.recordingOptions.keys) {
                    Text("Off").tag(CaptureRecordingOptions.Keys.off)
                    Text("Shortcuts Only").tag(CaptureRecordingOptions.Keys.shortcuts)
                    Text("All Keys").tag(CaptureRecordingOptions.Keys.all)
                }
                if workspace.recordingOptions.camera {
                    Picker("Camera Position", selection: $workspace.recordingOptions.cameraPosition) {
                        Text("Top Left").tag(CaptureRecordingOptions.CameraPosition.topLeft)
                        Text("Top Right").tag(CaptureRecordingOptions.CameraPosition.topRight)
                        Text("Bottom Left").tag(CaptureRecordingOptions.CameraPosition.bottomLeft)
                        Text("Bottom Right").tag(CaptureRecordingOptions.CameraPosition.bottomRight)
                    }
                    Picker("Camera Size", selection: $workspace.recordingOptions.cameraFraction) {
                        Text("Small").tag(0.15); Text("Medium").tag(0.25); Text("Large").tag(0.35)
                    }
                    Toggle("Mirror Camera", isOn: $workspace.recordingOptions.mirrorCamera)
                }
                Picker("Frame Rate", selection: $workspace.recordingOptions.framesPerSecond) {
                    ForEach([15, 30, 60], id: \.self) { Text("\($0) fps").tag($0) }
                }
                Picker("Start Delay", selection: $workspace.recordingOptions.delay) {
                    Text("None").tag(0)
                    ForEach([3, 5, 10], id: \.self) { Text("\($0) seconds").tag($0) }
                }
                Picker("When Recording Stops", selection: $workspace.recordingOptions.completion) {
                    Text("Open Preview").tag(CaptureRecordingOptions.Completion.preview)
                    Text("Save File…").tag(CaptureRecordingOptions.Completion.saveFile)
                    Text("Copy File").tag(CaptureRecordingOptions.Completion.copyFile)
                }
            } label: {
                SymbolImage(name: "slider.horizontal.3", size: metrics.scaled(Theme.Size.captureGlyph))
                    .frame(width: metrics.scaled(Theme.Size.captureTool), height: metrics.scaled(Theme.Size.captureTool))
            }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
            .help("Recording Options").accessibilityLabel("Recording Options")
            Button(workspace.recordingOptions.delay == 0 ? "Start Recording" : "Start in \(workspace.recordingOptions.delay)s") {
                coordinator.startSelectedRecording()
            }
            .buttonStyle(.borderedProminent).fixedSize()
        }
    }
}
