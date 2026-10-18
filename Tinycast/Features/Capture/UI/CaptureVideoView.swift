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
                                    .buttonStyle(.modalAction(.standard, fillsWidth: false))
                            }
                            .padding(metrics.spacing.lg).captureGlass(metrics)
                        }
                    }
                Controls(state: state).disabled(state.busy)
                HStack(spacing: metrics.spacing.md) {
                    if coordinator.otherResult != nil {
                        CaptureIconButton(title: String(localized: "Back to Screenshot"), symbol: "camera") {
                            coordinator.showScreenshotResult()
                        }.disabled(state.busy)
                    }
                    Text("\(state.info.size.width) × \(state.info.size.height)")
                    Text(Duration.seconds(state.edit.duration).formatted(.time(pattern: .minuteSecond)))
                        .monospacedDigit()
                    Spacer()
                    CaptureIconButton(
                        title: String(localized: "Undo Video Edit"), symbol: "arrow.uturn.backward",
                        shortcut: "⌘Z"
                    ) {
                        state.undoEdit()
                    }.keyboardShortcut("z").disabled(state.busy || !state.undo.canUndo)
                    CaptureIconButton(
                        title: String(localized: "Redo Video Edit"), symbol: "arrow.uturn.forward",
                        shortcut: "⇧⌘Z"
                    ) {
                        state.redoEdit()
                    }.keyboardShortcut("z", modifiers: [.command, .shift]).disabled(
                        state.busy || !state.undo.canRedo)
                    if state.busy {
                        if let progress = state.progress {
                            Text(progress, format: .percent.precision(.fractionLength(0)))
                        }
                        ProgressView().controlSize(.small)
                        CaptureIconButton(title: String(localized: "Cancel Export"), symbol: "xmark") {
                            coordinator.cancelWork()
                        }
                    } else {
                        Menu {
                            Button("Save Editable Draft") { coordinator.saveVideoDraft() }
                            Button("Copy File") { coordinator.shareVideo(delivery: .copy) }
                            Button("Share…") { coordinator.shareVideo() }
                            CaptureUploadMenu(video: true)
                        } label: {
                            CaptureToolbarGlyph(symbol: "ellipsis")
                        }
                        .menuStyle(CaptureToolbarMenuStyle()).fixedSize()
                        .tooltip(String(localized: "Video Actions")).accessibilityLabel(
                            String(localized: "Video Actions"))
                        CaptureIconButton(
                            title: String(localized: "Save Video"), symbol: "square.and.arrow.down",
                            shortcut: "⌘S"
                        ) {
                            coordinator.saveVideo()
                        }.keyboardShortcut("s")
                        CaptureIconButton(
                            title: String(localized: "Close Recording"), symbol: "xmark", shortcut: "⌘W"
                        ) {
                            coordinator.requestClose()
                        }.keyboardShortcut("w")
                    }
                }
                if let notice = state.notice { Text(notice).foregroundStyle(Theme.Colors.textSecondary) }
            }
            .font(metrics.typography.bar).padding(metrics.spacing.lg)
            .captureWindowSurface()
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
        @State private var panel: Panel?

        private enum Panel { case cuts, audio, export }

        var body: some View {
            VStack(spacing: metrics.spacing.sm) {
                CaptureVideoStrip(state: state)
                HStack(spacing: metrics.spacing.xxs) {
                    CaptureValueMenu(title: String(localized: "Speed"), value: "\(state.edit.speed.formatted())×") {
                        Picker("Speed", selection: value(\.speed)) {
                            ForEach([0.25, 0.5, 1, 1.5, 2, 4], id: \.self) { Text("\($0.formatted())×").tag($0) }
                        }.pickerStyle(.inline).labelsHidden()
                    }
                    CaptureIconButton(
                        title: String(localized: "Zoom Video Region"), symbol: "plus.magnifyingglass"
                    ) { state.addEffect(.zoom) }
                    CaptureIconButton(title: String(localized: "Cover Video Region"), symbol: "square.inset.filled") {
                        state.addEffect(.cover)
                    }
                    CaptureIconButton(title: String(localized: "Add Video Text"), symbol: "textformat") {
                        state.addEffect(.text)
                    }
                    if !state.edit.effects.isEmpty {
                        Menu {
                            ForEach(state.edit.effects) { effect in
                                Button(
                                    Bundle.main.localizedString(forKey: effect.kind.title, value: nil, table: nil)
                                        + " · \(effect.start.formatted())–\(effect.end.formatted()) s"
                                ) {
                                    state.player.pause()
                                    state.selectedEffectID = effect.id
                                    state.seek(to: effect.start)
                                }
                            }
                        } label: {
                            CaptureToolbarGlyph(symbol: "square.3.layers.3d")
                        }
                        .menuStyle(CaptureToolbarMenuStyle()).fixedSize()
                        .tooltip(String(localized: "Video Effects")).accessibilityLabel(
                            String(localized: "Video Effects"))
                    }
                    CaptureIconButton(
                        title: String(localized: "Cut and Freeze"), symbol: "timeline.selection",
                        selected: panel == .cuts, hint: String(localized: "Times refer to the original recording.")
                    ) { toggle(.cuts) }
                    if state.info.audioTracks > 0 {
                        CaptureIconButton(
                            title: String(localized: "Audio"), symbol: "speaker.wave.2", selected: panel == .audio
                        ) { toggle(.audio) }
                    }
                    Spacer()
                    CaptureValueMenu(
                        title: String(localized: "Format"), value: state.exportOptions.format.rawValue.uppercased()
                    ) {
                        Picker("Format", selection: $state.exportOptions.format) {
                            ForEach(CaptureVideoExportOptions.Format.allCases, id: \.self) {
                                Text($0.rawValue.uppercased()).tag($0)
                            }
                        }.pickerStyle(.inline).labelsHidden()
                    }
                    CaptureIconButton(
                        title: String(localized: "Export Options"), symbol: "slider.horizontal.3",
                        selected: panel == .export
                    ) { toggle(.export) }
                    CaptureIconButton(title: String(localized: "Reset All Edits"), symbol: "arrow.counterclockwise") {
                        state.change { $0 = CaptureVideoEdit(end: state.info.duration) }
                    }
                }
                CaptureVideoEffectControls(state: state)
                switch panel {
                case .cuts: CaptureVideoTimelineView(state: state)
                case .audio: AudioControls(state: state)
                case .export: exportOptions
                case nil: EmptyView()
                }
            }
        }

        private func toggle(_ next: Panel) { panel = panel == next ? nil : next }

        @ViewBuilder private var exportOptions: some View {
            HStack(spacing: metrics.spacing.xxs) {
                if state.exportOptions.format == .gif {
                    CaptureValueMenu(
                        title: String(localized: "GIF Size"), value: "\(state.exportOptions.maximumDimension) px"
                    ) {
                        Picker("GIF Size", selection: $state.exportOptions.maximumDimension) {
                            ForEach([320, 480, 640, 960], id: \.self) { Text("\($0) px").tag($0) }
                        }.pickerStyle(.inline).labelsHidden()
                    }
                    CaptureValueMenu(
                        title: String(localized: "Frame Rate"), value: "\(state.exportOptions.framesPerSecond) fps"
                    ) {
                        Picker("Frame Rate", selection: $state.exportOptions.framesPerSecond) {
                            ForEach([5, 10, 15], id: \.self) { Text("\($0) fps").tag($0) }
                        }.pickerStyle(.inline).labelsHidden()
                    }
                    Text("No audio · up to 30 seconds").foregroundStyle(Theme.Colors.textSecondary)
                } else {
                    CaptureValueMenu(title: String(localized: "Resolution"), value: resolution) {
                        Picker("Resolution", selection: $state.exportOptions.videoMaximumDimension) {
                            Text("Original").tag(0)
                            ForEach([640, 1280, 1920, 2560, 3840], id: \.self) { Text("\($0) px").tag($0) }
                        }.pickerStyle(.inline).labelsHidden()
                    }
                    CaptureValueMenu(
                        title: String(localized: "Frame Rate"),
                        value: "\(state.exportOptions.videoFramesPerSecond) fps"
                    ) {
                        Picker("Frame Rate", selection: $state.exportOptions.videoFramesPerSecond) {
                            ForEach([15, 30, 60], id: \.self) { Text("\($0) fps").tag($0) }
                        }.pickerStyle(.inline).labelsHidden()
                    }
                    CaptureValueMenu(
                        title: String(localized: "Quality"),
                        value: Bundle.main.localizedString(
                            forKey: state.exportOptions.quality.title, value: nil, table: nil)
                    ) {
                        Picker("Quality", selection: $state.exportOptions.quality) {
                            ForEach(CaptureVideoExportOptions.Quality.allCases, id: \.self) {
                                Text(LocalizedStringKey($0.title)).tag($0)
                            }
                        }.pickerStyle(.inline).labelsHidden()
                    }
                    Text("Longest edge · original aspect ratio").foregroundStyle(Theme.Colors.textSecondary)
                }
                Spacer()
            }
        }

        private var resolution: String {
            let maximum = state.exportOptions.videoMaximumDimension
            return maximum == 0 ? String(localized: "Original") : "\(maximum) px"
        }

        private func value(_ key: WritableKeyPath<CaptureVideoEdit, Double>) -> Binding<Double> {
            Binding(
                get: { state.edit[keyPath: key] }, set: { value in state.change { $0[keyPath: key] = value } }
            )
        }
    }

    private struct AudioControls: View {
        let state: CaptureVideoState
        @Environment(\.metrics) private var metrics

        var body: some View {
            VStack {
                ForEach(0..<state.info.audioTracks, id: \.self) { index in
                    HStack {
                        Text(
                            state.info.audioNames.indices.contains(index)
                                ? state.info.audioNames[index] : String(localized: "Track \(index + 1)"))
                        Slider(
                            value: Binding(
                                get: { state.edit.trackVolumes[index] ?? 1 },
                                set: { value in
                                    state.change { $0.trackVolumes[index] = value }
                                }), in: 0...1,
                            onEditingChanged: {
                                if $0 { state.beginEditing() } else { state.endEditing() }
                            }
                        ).accessibilityLabel(String(localized: "Audio Track \(index + 1) Volume"))
                    }
                }
            }
            .frame(width: metrics.scaled(Theme.Size.captureAdjustmentWidth))
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
