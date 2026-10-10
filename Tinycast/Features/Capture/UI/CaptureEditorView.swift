import SwiftUI

struct CaptureEditorView: View {
    @Environment(CaptureCoordinator.self) private var coordinator

    private var metrics: InterfaceMetrics { coordinator.metrics }

    var body: some View {
        if let state = coordinator.editor {
            VStack(spacing: metrics.spacing.md) {
                HStack(spacing: metrics.spacing.md) {
                    Text(state.document.pieces.isEmpty && state.document.imageLayers.count > 1 ? "Combined Image"
                        : state.document.axis == nil ? "Screenshot" : "Scrolling Screenshot")
                        .font(metrics.typography.panelTitle)
                    if let other = coordinator.otherResult {
                        Button(other.document.axis == nil ? "Back to Screenshot" : "Scrolling Result") {
                            coordinator.swapCaptureResult()
                        }.disabled(state.busy)
                    }
                    if coordinator.video != nil {
                        CaptureIconButton(title: "Recording Result", symbol: "record.circle") {
                            coordinator.showRecordingResult()
                        }.disabled(state.busy)
                    }
                    Spacer()
                    CaptureOutputTools().disabled(state.busy)
                    Menu {
                        Button("Add Image…") { coordinator.addImage() }
                        Button("Paste Image") { coordinator.addImage(clipboard: true) }
                        Button(state.backgroundImage?.backgroundMask?.enabled == true
                            ? "Restore Background" : "Remove Background") {
                            coordinator.removeBackground()
                        }
                        Menu("Combine with Image") {
                            Button("Add Below…") { coordinator.addImage(axis: .vertical) }
                            Button("Add to Right…") { coordinator.addImage(axis: .horizontal) }
                        }
                        Menu("Append Capture") {
                            Button("Capture Below…") { coordinator.appendCapture(axis: .vertical) }
                            Button("Capture to Right…") { coordinator.appendCapture(axis: .horizontal) }
                        }
                        if state.document.pieces.isEmpty {
                            Button("Fit Canvas to Images") { state.fitCanvasToImages() }
                        }
                        Button("Save Editable Draft") { coordinator.saveDraft() }
                        Button("Copy File") { coordinator.shareImage(delivery: .copy) }
                        CaptureUploadMenu()
                        Button("Capture History") { coordinator.open(.captureHistory) }
                    } label: {
                        SymbolImage(name: "ellipsis", size: metrics.size.rowIcon)
                    }
                    .menuStyle(.borderlessButton).fixedSize()
                    .accessibilityLabel("More").disabled(state.busy)
                }
                CaptureCanvas(state: state).id(state.document.id)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                HStack(spacing: metrics.spacing.md) {
                    CaptureAnnotationTools(state: state)
                    Spacer()
                    Text("\(Int(state.document.outputBounds.width)) × \(Int(state.document.outputBounds.height))")
                        .foregroundStyle(Theme.Colors.textSecondary).monospacedDigit()
                    Menu("\(Int(state.zoom * 100))%") {
                        Button("Default Fit") { state.fit() }
                        Button("Entire Image") { state.fit(.window) }
                        ForEach([0.25, 0.5, 1, 2, 4], id: \.self) { zoom in
                            Button("\(Int(zoom * 100))%") { state.setZoom(zoom) }
                        }
                    }.fixedSize()
                    if state.busy {
                        ProgressView().controlSize(.small)
                        Button("Cancel") { coordinator.cancelWork() }
                    }
                }
                CaptureToolProperties(state: state)
                CaptureImageAdjustmentControls(state: state)
                CapturePresentationControls(state: state)
                if let review = state.translationReview { CaptureTranslationReview(state: state, review: review) }
                CaptureCodeResults(state: state)
                CaptureRedactionReview(state: state)
                if let notice = state.notice {
                    Text(notice).font(metrics.typography.bar).foregroundStyle(Theme.Colors.textSecondary)
                        .textSelection(.enabled)
                }
            }
            .padding(metrics.spacing.xl)
            .font(metrics.typography.rowTitle)
            .foregroundStyle(Theme.Colors.textPrimary)
            .background(Theme.Colors.panelScrim)
            .background(GlassEffectView())
            .environment(\.metrics, metrics)
        }
    }
}
