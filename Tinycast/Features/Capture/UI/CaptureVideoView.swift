import AVKit
import SwiftUI

struct CaptureVideoView: View {
    @Environment(CaptureCoordinator.self) private var coordinator
    @Environment(\.metrics) private var metrics

    var body: some View {
        if let state = coordinator.video {
            VStack(spacing: metrics.spacing.md) {
                VideoPlayer(player: state.player).frame(maxWidth: .infinity, maxHeight: .infinity)
                    .disabled(state.preview != .ready)
                    .overlay { CaptureVideoEffectCanvas(state: state) }
                    .overlay {
                        switch state.preview {
                        case .loading: ProgressView().controlSize(.small)
                        case .ready: EmptyView()
                        case .failed(let message):
                            VStack(spacing: metrics.spacing.md) {
                                Text("Preview could not load")
                                Text(message).foregroundStyle(Theme.Colors.textSecondary)
                                Button("Retry Preview") { state.previewAttempt += 1 }
                            }.padding(metrics.spacing.lg).background(Theme.Colors.panelScrim)
                        }
                    }
                Controls(state: state).disabled(state.busy)
                HStack(spacing: metrics.spacing.md) {
                    if coordinator.otherResult != nil {
                        CaptureIconButton(title: "Back to Screenshot", symbol: "camera") {
                            coordinator.showScreenshotResult()
                        }.disabled(state.busy)
                    }
                    Text("\(state.info.size.width) × \(state.info.size.height)")
                    Text(Duration.seconds(state.edit.duration).formatted(.time(pattern: .minuteSecond)))
                        .monospacedDigit()
                    Spacer()
                    CaptureIconButton(title: "Undo Video Edit", symbol: "arrow.uturn.backward", shortcut: "⌘Z") {
                        state.undoEdit()
                    }.keyboardShortcut("z").disabled(state.busy || !state.undo.canUndo)
                    CaptureIconButton(title: "Redo Video Edit", symbol: "arrow.uturn.forward", shortcut: "⇧⌘Z") {
                        state.redoEdit()
                    }.keyboardShortcut("z", modifiers: [.command, .shift]).disabled(state.busy || !state.undo.canRedo)
                    if state.busy {
                        if let progress = state.progress { Text(progress, format: .percent.precision(.fractionLength(0))) }
                        ProgressView().controlSize(.small)
                        Button("Cancel Export") { coordinator.cancelWork() }
                    } else {
                        Menu {
                            Button("Save Editable Draft") { coordinator.saveVideoDraft() }
                            Button("Copy File") { coordinator.shareVideo(delivery: .copy) }
                            Button("Share…") { coordinator.shareVideo() }
                            CaptureUploadMenu(video: true)
                        } label: {
                            SymbolImage(name: "ellipsis", size: metrics.scaled(Theme.Size.captureGlyph))
                                .frame(width: metrics.scaled(Theme.Size.captureTool),
                                    height: metrics.scaled(Theme.Size.captureTool))
                        }
                            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                            .help("Video Actions").accessibilityLabel("Video Actions")
                        CaptureIconButton(title: "Save Video", symbol: "square.and.arrow.down", shortcut: "⌘S") {
                            coordinator.saveVideo()
                        }.keyboardShortcut("s")
                        CaptureIconButton(title: "Close Recording", symbol: "xmark", shortcut: "⌘W") {
                            coordinator.requestClose()
                        }.keyboardShortcut("w")
                    }
                }
                if let notice = state.notice { Text(notice).foregroundStyle(Theme.Colors.textSecondary) }
            }
            .font(metrics.typography.bar).padding(metrics.spacing.lg)
            .background(Theme.Colors.panelScrim)
            .task(id: state.previewRequest) { await state.updatePreview() }
            .onDisappear {
                state.player.pause()
                state.player.replaceCurrentItem(with: nil)
                state.thumbnails = []
            }
        }
    }

    private struct Controls: View {
        @Bindable var state: CaptureVideoState
        @Environment(\.metrics) private var metrics

        var body: some View {
            VStack(spacing: metrics.spacing.sm) {
                CaptureVideoStrip(state: state)
                HStack(spacing: metrics.spacing.md) {
                    Picker("Speed", selection: value(\.speed)) {
                        ForEach([0.25, 0.5, 1, 1.5, 2, 4], id: \.self) { Text("\($0.formatted())×").tag($0) }
                    }.fixedSize()
                    CaptureIconButton(title: "Zoom Video Region", symbol: "plus.magnifyingglass") { state.addEffect(.zoom) }
                    CaptureIconButton(title: "Cover Video Region", symbol: "square.fill") { state.addEffect(.cover) }
                    CaptureIconButton(title: "Add Video Text", symbol: "textformat") { state.addEffect(.text) }
                    if !state.edit.effects.isEmpty {
                        Menu {
                            ForEach(state.edit.effects) { effect in
                                Button("\(effect.kind.rawValue.capitalized) · "
                                    + "\(effect.start.formatted())–\(effect.end.formatted()) s") {
                                    state.player.pause()
                                    state.selectedEffectID = effect.id
                                    state.seek(to: effect.start)
                                }
                            }
                        } label: { Image(systemName: "square.3.layers.3d") }
                            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                            .help("Video Effects").accessibilityLabel("Video Effects")
                    }
                    if state.info.audioTracks > 0 {
                        AudioControls(state: state)
                    }
                    Spacer()
                    Picker("Format", selection: $state.exportOptions.format) {
                        ForEach(CaptureVideoExportOptions.Format.allCases, id: \.self) {
                            Text($0.rawValue.uppercased()).tag($0)
                        }
                    }.fixedSize()
                    Button("Reset") { state.change { $0 = CaptureVideoEdit(end: state.info.duration) } }
                }
                CaptureVideoEffectControls(state: state)
                CaptureVideoTimelineView(state: state)
                if state.exportOptions.format == .gif {
                    HStack(spacing: metrics.spacing.md) {
                        Picker("GIF Size", selection: $state.exportOptions.maximumDimension) {
                            ForEach([320, 480, 640, 960], id: \.self) { Text("\($0) px").tag($0) }
                        }.fixedSize()
                        Picker("Frame Rate", selection: $state.exportOptions.framesPerSecond) {
                            ForEach([5, 10, 15], id: \.self) { Text("\($0) fps").tag($0) }
                        }.fixedSize()
                        Text("No audio · up to 30 seconds").foregroundStyle(Theme.Colors.textSecondary)
                        Spacer()
                    }
                } else {
                    DisclosureGroup("Export Options") {
                        HStack(spacing: metrics.spacing.md) {
                            Picker("Resolution", selection: $state.exportOptions.videoMaximumDimension) {
                                Text("Original").tag(0)
                                ForEach([640, 1280, 1920, 2560, 3840], id: \.self) { Text("\($0) px").tag($0) }
                            }.fixedSize()
                            Picker("Frame Rate", selection: $state.exportOptions.videoFramesPerSecond) {
                                ForEach([15, 30, 60], id: \.self) { Text("\($0) fps").tag($0) }
                            }.fixedSize()
                            Picker("Quality", selection: $state.exportOptions.quality) {
                                ForEach(CaptureVideoExportOptions.Quality.allCases, id: \.self) {
                                    Text($0.rawValue.capitalized).tag($0)
                                }
                            }.fixedSize()
                            Text("Longest edge · original aspect ratio").foregroundStyle(Theme.Colors.textSecondary)
                            Spacer()
                        }.padding(.top, metrics.spacing.sm)
                    }
                }
            }
        }

        private func value(_ key: WritableKeyPath<CaptureVideoEdit, Double>) -> Binding<Double> {
            Binding(get: { state.edit[keyPath: key] }, set: { value in state.change { $0[keyPath: key] = value } })
        }

    }

    private struct AudioControls: View {
        let state: CaptureVideoState
        @Environment(\.metrics) private var metrics

        var body: some View {
            DisclosureGroup("Audio") {
                VStack {
                    ForEach(0..<state.info.audioTracks, id: \.self) { index in
                        HStack {
                            Text(state.info.audioNames.indices.contains(index)
                                ? state.info.audioNames[index] : "Track \(index + 1)")
                            Slider(value: Binding(get: { state.edit.trackVolumes[index] ?? 1 }, set: { value in
                                state.change { $0.trackVolumes[index] = value }
                            }), in: 0...1, onEditingChanged: {
                                if $0 { state.beginEditing() } else { state.endEditing() }
                            }).accessibilityLabel("Audio Track \(index + 1) Volume")
                        }
                    }
                }
            }.frame(width: metrics.scaled(Theme.Size.captureAdjustmentWidth))
        }
    }
}
