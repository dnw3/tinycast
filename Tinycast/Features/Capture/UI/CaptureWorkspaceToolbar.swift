import SwiftUI

struct CaptureWorkspaceToolbar: View {
    @Environment(CaptureCoordinator.self) private var coordinator
    @Environment(\.metrics) private var metrics
    let workspace: CaptureWorkspaceState

    var body: some View {
        VStack(spacing: metrics.spacing.sm) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: metrics.spacing.md) {
                    captureKinds
                    tools.fixedSize()
                }
                VStack(spacing: metrics.spacing.sm) {
                    captureKinds
                    tools
                }
            }
            .padding(metrics.spacing.xs)
            .background {
                RoundedRectangle(cornerRadius: metrics.radius.row).fill(.clear)
                    .frosted(in: RoundedRectangle(cornerRadius: metrics.radius.row))
            }
            .disabled(workspace.busy || coordinator.editor?.busy == true)
            if workspace.selectionOptions {
                CaptureSelectionControls(workspace: workspace)
                    .padding(metrics.spacing.xs)
                    .background { Capsule().fill(.clear).frosted(in: Capsule()) }
            }
            if coordinator.pendingCapture == nil, let state = coordinator.editor,
                workspace.request.mode == .screenshot, !workspace.selectingTarget {
                CaptureToolProperties(state: state)
                    .padding(metrics.spacing.xs)
                    .background { Capsule().fill(.clear).frosted(in: Capsule()) }
                CaptureImageAdjustmentControls(state: state)
                    .padding(metrics.spacing.xs)
                    .background {
                        RoundedRectangle(cornerRadius: metrics.radius.row).fill(.clear)
                            .frosted(in: RoundedRectangle(cornerRadius: metrics.radius.row))
                    }
            }
            if let notice = coordinator.editor?.notice {
                Text(notice).font(metrics.typography.bar).padding(metrics.spacing.sm)
                    .background(Theme.Colors.panelScrim, in: RoundedRectangle(cornerRadius: metrics.radius.row))
            } else if workspace.requiresScrollRegion {
                Text("Select the scrolling content inside the window")
                    .font(metrics.typography.bar).padding(metrics.spacing.sm)
                    .background(Theme.Colors.panelScrim, in: RoundedRectangle(cornerRadius: metrics.radius.row))
            } else if workspace.request.mode != .screenshot, coordinator.editor?.document.edit.isEmpty == false {
                Text("Use this region · annotations stay in the screenshot")
                    .font(metrics.typography.bar).padding(metrics.spacing.sm)
                    .background(Theme.Colors.panelScrim, in: RoundedRectangle(cornerRadius: metrics.radius.row))
            }
            if coordinator.pendingCapture == nil, let state = coordinator.editor,
                workspace.request.mode == .screenshot, !workspace.selectingTarget {
                CaptureCodeResults(state: state)
                CaptureRedactionReview(state: state)
            }
        }
        .foregroundStyle(Theme.Colors.textPrimary)
        .frame(maxWidth: .infinity)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var captureKinds: some View {
        HStack(spacing: metrics.spacing.xxs) {
            if let selection = workspace.displays {
                CaptureIconButton(title: "Single Display", symbol: "arrow.left") {
                    if let screen = NSScreen.screens.first(where: { $0.frame == workspace.target.screenFrame }) {
                        coordinator.switchCaptureScreen(screen)
                    }
                }
                CaptureIconButton(title: "Capture All Displays", symbol: "display.2", shortcut: "Return") {
                    coordinator.selectDisplaysRegion(selection.bounds)
                }
            } else {
                scopes
                Divider().frame(height: metrics.size.rowIcon)
                if coordinator.pendingCapture == nil { modes }
                CaptureIconButton(title: "Selection Options", symbol: "slider.horizontal.3",
                    selected: workspace.selectionOptions) { workspace.selectionOptions.toggle() }
            }
        }
        .fixedSize()
    }

    @ViewBuilder private var tools: some View {
        if workspace.displays != nil {
            Text("Drag across displays").font(metrics.typography.bar).padding(.horizontal, metrics.spacing.md)
        } else if let pending = coordinator.pendingCapture {
            Text(pending.axis == .vertical ? "Add below · Return" : "Add to right · Return")
                .font(metrics.typography.bar).padding(.horizontal, metrics.spacing.md)
        } else if let state = coordinator.editor, !workspace.selectingTarget {
            if workspace.request.mode == .screenshot {
                CaptureAnnotationTools(state: state)
            } else if workspace.request.mode == .scrolling {
                scrolling
            } else {
                CaptureRecordingPreparation(workspace: workspace)
            }
        } else {
            Text(workspace.choosingElement ? "Click an element or drag"
                : workspace.choosingWindow ? "Click a window" : "Drag to select")
                .font(metrics.typography.bar).padding(.horizontal, metrics.spacing.md)
        }
    }

    private var scopes: some View {
        HStack(spacing: metrics.spacing.xxs) {
            CaptureIconButton(title: "Region", symbol: "viewfinder", selected: workspace.request.scope == .region) {
                coordinator.setCaptureScope(.region)
            }
            CaptureIconButton(
                title: "Window", symbol: "macwindow", shortcut: "Space",
                selected: workspace.request.scope == .window) {
                coordinator.setCaptureScope(.window)
            }
            CaptureIconButton(title: "Screen", symbol: "display", selected: workspace.request.scope == .screen) {
                coordinator.setCaptureScope(.screen)
            }
        }
    }

    private var modes: some View {
        HStack(spacing: metrics.spacing.xxs) {
            CaptureIconButton(title: "Screenshot", symbol: "camera", selected: workspace.request.mode == .screenshot) {
                coordinator.setCaptureMode(.screenshot)
            }
            CaptureIconButton(
                title: "Scrolling Screenshot", symbol: "arrow.down.right.and.arrow.up.left",
                selected: workspace.request.mode == .scrolling) {
                coordinator.setCaptureMode(.scrolling)
            }
            CaptureIconButton(title: "Record", symbol: "record.circle", selected: workspace.request.mode == .recording) {
                coordinator.setCaptureMode(.recording)
            }
        }
    }

    private var scrolling: some View {
        HStack(spacing: metrics.spacing.sm) {
            CaptureIconButton(title: "Vertical", symbol: "arrow.up.and.down", selected: workspace.axis == .vertical) {
                workspace.axis = .vertical
            }
            CaptureIconButton(title: "Horizontal", symbol: "arrow.left.and.right", selected: workspace.axis == .horizontal) {
                workspace.axis = .horizontal
            }
            Button("Start Scrolling") { coordinator.startSelectedScroll() }
                .buttonStyle(.borderedProminent).fixedSize().disabled(workspace.requiresScrollRegion)
        }
    }
}

struct CaptureWorkspaceOutputs: View {
    @Environment(CaptureCoordinator.self) private var coordinator
    @Environment(\.metrics) private var metrics

    var body: some View {
        VStack(spacing: metrics.spacing.xxs) {
            if coordinator.editor != nil, coordinator.workspace?.request.mode == .screenshot,
                coordinator.workspace?.selectingTarget == false
            {
                Group {
                    if coordinator.pendingCapture != nil {
                        CaptureIconButton(title: "Add Capture", symbol: "plus", shortcut: "Return", selected: true) {
                            coordinator.finishAppendCapture()
                        }
                    } else { CaptureOutputTools(inline: true) }
                }
                    .disabled(coordinator.editor?.busy == true || coordinator.workspace?.busy == true)
                Divider().frame(width: metrics.size.rowIcon)
            }
            if coordinator.editor?.busy == true || coordinator.workspace?.busy == true {
                ProgressView().controlSize(.small)
                CaptureIconButton(title: "Cancel Operation", symbol: "stop") { coordinator.cancelWork() }
            } else {
                CaptureIconButton(title: "Close Capture", symbol: "xmark", shortcut: "Esc") { coordinator.requestClose() }
            }
        }
        .padding(metrics.spacing.xs)
        .background {
                RoundedRectangle(cornerRadius: metrics.radius.row).fill(.clear)
                    .frosted(in: RoundedRectangle(cornerRadius: metrics.radius.row))
            }
        .foregroundStyle(Theme.Colors.textPrimary)
        .frame(maxWidth: .infinity)
        .fixedSize(horizontal: false, vertical: true)
    }
}
