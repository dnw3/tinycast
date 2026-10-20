import SwiftUI

struct CaptureEditorView: View {
    @Environment(CaptureCoordinator.self) private var coordinator

    @State private var availableWidth = Theme.Size.captureEditorMinimum.width
    @State private var accessoryWidth: CGFloat = 0
    /// The compact toolbar's band on macOS 26 until measured, so the header never starts at zero.
    @State private var titleBand: CGFloat = 40

    private var metrics: InterfaceMetrics { coordinator.metrics }

    var body: some View {
        if let state = coordinator.editor {
            ZStack {
                // Measured where the safe area still applies; the editor runs up into the band.
                Color.clear.onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).minY } action: {
                    titleBand = $0
                }
                editor(state).ignoresSafeArea(.container, edges: .top)
            }
            .font(metrics.typography.rowTitle)
            .foregroundStyle(Theme.Colors.textPrimary)
            .captureWindowSurface()
            .environment(\.metrics, metrics)
        }
    }

    private func editor(_ state: CaptureEditorState) -> some View {
        VStack(spacing: metrics.spacing.md) {
            HStack(spacing: metrics.spacing.md) {
                title(state)
                if coordinator.video != nil {
                    CaptureIconButton(
                        title: String(localized: "Recording Result"), symbol: "record.circle"
                    ) {
                        coordinator.showRecordingResult()
                    }.disabled(state.busy)
                }
                Spacer()
                CaptureOutputTools().disabled(state.busy)
                Menu {
                    Button("Add Image…") { coordinator.addImage() }
                    Button("Paste Image") { coordinator.addImage(clipboard: true) }
                    Button(
                        state.backgroundImage?.backgroundMask?.enabled == true
                            ? String(localized: "Restore Background")
                            : String(localized: "Remove Background")
                    ) {
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
                    CaptureToolbarGlyph(symbol: "ellipsis")
                }
                .menuStyle(CaptureToolbarMenuStyle()).fixedSize()
                .accessibilityLabel(String(localized: "More Actions")).tooltip(String(localized: "More Actions"))
                .disabled(state.busy)
            }
            // Level with the traffic lights, in the band the window keeps for them.
            .padding(.leading, Theme.Size.captureEditorTitleInset - metrics.spacing.xl)
            .frame(height: titleBand)
            .background(WindowDragBackground())
            CaptureCanvas(state: state).id(state.document.id)
                .background(Theme.Colors.captureCanvas, in: well)
                .clipShape(well)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            HStack(spacing: metrics.spacing.md) {
                CaptureAnnotationTools(
                    state: state,
                    maximumItems: CaptureToolbarConfiguration.capacity(
                        length: availableWidth - accessoryWidth - 3 * metrics.spacing.xl,
                        cell: metrics.scaled(Theme.Size.captureTool), spacing: metrics.spacing.xxs,
                        reserved: 3))
                Spacer()
                HStack(spacing: metrics.spacing.md) {
                    Text(
                        "\(Int(state.document.outputBounds.width)) × \(Int(state.document.outputBounds.height))"
                    )
                    .foregroundStyle(Theme.Colors.textSecondary).monospacedDigit()
                    CaptureValueMenu(
                        title: String(localized: "Zoom"), value: "\(Int(state.zoom * 100))%"
                    ) {
                        Button("Default Fit") { state.fit() }
                        Button("Entire Image") { state.fit(.window) }
                        ForEach([0.25, 0.5, 1, 2, 4], id: \.self) { zoom in
                            Button("\(Int(zoom * 100))%") { state.setZoom(zoom) }
                        }
                    }
                    if state.busy {
                        ProgressView().controlSize(.small)
                        CaptureIconButton(title: String(localized: "Cancel"), symbol: "xmark") {
                            coordinator.cancelWork()
                        }
                    }
                }
                .fixedSize()
                .onGeometryChange(for: CGFloat.self) {
                    $0.size.width
                } action: {
                    accessoryWidth = $0
                }
            }
            CaptureToolProperties(state: state)
            CaptureImageAdjustmentControls(state: state)
            CapturePresentationControls(state: state)
            if let review = state.translationReview {
                CaptureTranslationReview(state: state, review: review)
            }
            CaptureCodeResults(state: state)
            CaptureRedactionReview(state: state)
            if let notice = state.notice {
                Text(notice).font(metrics.typography.bar).foregroundStyle(Theme.Colors.textSecondary)
                    .textSelection(.enabled)
            }
        }
        .onGeometryChange(for: CGFloat.self) {
            $0.size.width
        } action: {
            availableWidth = $0
        }
        .padding([.horizontal, .bottom], metrics.spacing.xl)
    }

    private var well: RoundedRectangle {
        RoundedRectangle(cornerRadius: metrics.radius.card, style: .continuous)
    }

    /// Both results of a scrolling capture are one switch, in the same order whichever is shown.
    @ViewBuilder private func title(_ state: CaptureEditorState) -> some View {
        if let other = coordinator.otherResult {
            let screenshot = state.document.axis == nil ? state.document : other.document
            let scrolling = state.document.axis == nil ? other.document : state.document
            Picker(
                String(localized: "Capture Result"),
                selection: Binding(
                    get: { state.document.axis != nil },
                    set: { if $0 != (state.document.axis != nil) { coordinator.swapCaptureResult() } })
            ) {
                Text(Self.name(of: screenshot)).tag(false)
                Text(Self.name(of: scrolling)).tag(true)
            }
            .pickerStyle(.segmented).labelsHidden().fixedSize()
            .disabled(state.busy)
        } else {
            Text(Self.name(of: state.document)).font(metrics.typography.panelTitle)
        }
    }

    private static func name(of document: CaptureDocument) -> String {
        if document.pieces.isEmpty, document.imageLayers.count > 1 { return String(localized: "Combined Image") }
        return document.axis == nil ? String(localized: "Screenshot") : String(localized: "Scrolling Screenshot")
    }
}
