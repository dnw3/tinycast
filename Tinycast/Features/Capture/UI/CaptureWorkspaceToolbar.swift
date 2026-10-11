import SwiftUI

struct CaptureWorkspaceToolbar: View {
    @Environment(CaptureCoordinator.self) private var coordinator
    @Environment(\.metrics) private var metrics
    let workspace: CaptureWorkspaceState
    var availableWidth: CGFloat = Theme.Size.captureWorkspaceBar.width

    var body: some View {
        VStack(spacing: metrics.spacing.sm) {
            HStack(spacing: metrics.spacing.xxs) {
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
                .disabled(workspace.busy || coordinator.editor?.busy == true)
                if coordinator.editor == nil || workspace.selectingTarget || workspace.displays != nil
                    || workspace.request.mode != .screenshot
                {
                    Divider().frame(height: metrics.size.rowIcon)
                    CaptureWorkspaceDismiss()
                }
            }
            .padding(metrics.spacing.xs)
            .background {
                RoundedRectangle(cornerRadius: metrics.radius.row).fill(.clear)
                    .frosted(in: RoundedRectangle(cornerRadius: metrics.radius.row))
            }
            if workspace.selectionOptions {
                CaptureSelectionControls(workspace: workspace)
                    .padding(metrics.spacing.xs)
                    .background { Capsule().fill(.clear).frosted(in: Capsule()) }
            }
            if let notice = coordinator.editor?.notice {
                Text(notice).font(metrics.typography.bar).padding(metrics.spacing.sm)
                    .background(
                        Theme.Colors.panelScrim, in: RoundedRectangle(cornerRadius: metrics.radius.row))
            } else if workspace.requiresScrollRegion {
                Text("Select the scrolling content inside the window")
                    .font(metrics.typography.bar).padding(metrics.spacing.sm)
                    .background(
                        Theme.Colors.panelScrim, in: RoundedRectangle(cornerRadius: metrics.radius.row))
            } else if workspace.request.mode != .screenshot,
                coordinator.editor?.document.edit.isEmpty == false
            {
                Text("Use this region · annotations stay in the screenshot")
                    .font(metrics.typography.bar).padding(metrics.spacing.sm)
                    .background(
                        Theme.Colors.panelScrim, in: RoundedRectangle(cornerRadius: metrics.radius.row))
            }
            if coordinator.pendingCapture == nil, let state = coordinator.editor,
                workspace.request.mode == .screenshot, !workspace.selectingTarget
            {
                CaptureCodeResults(state: state)
                CaptureRedactionReview(state: state)
            }
        }
        .foregroundStyle(Theme.Colors.textPrimary)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var captureKinds: some View {
        HStack(spacing: metrics.spacing.xxs) {
            if let selection = workspace.displays {
                CaptureIconButton(title: String(localized: "Single Display"), symbol: "arrow.left") {
                    if let screen = NSScreen.screens.first(where: { $0.frame == workspace.target.screenFrame }
                    ) {
                        coordinator.switchCaptureScreen(screen)
                    }
                }
                CaptureIconButton(
                    title: String(localized: "Capture All Displays"), symbol: "display.2", shortcut: "Return"
                ) {
                    coordinator.selectDisplaysRegion(selection.bounds)
                }
            } else {
                if coordinator.editor != nil, !workspace.selectingTarget, coordinator.pendingCapture == nil {
                    CaptureWorkspaceMenu(workspace: workspace)
                } else {
                    scopes
                    Divider().frame(height: metrics.size.rowIcon)
                    if coordinator.pendingCapture == nil { modes }
                    CaptureIconButton(
                        title: String(localized: "Selection Options"), symbol: "slider.horizontal.3",
                        selected: workspace.selectionOptions
                    ) { workspace.selectionOptions.toggle() }
                }
            }
        }
        .fixedSize()
    }

    @ViewBuilder private var tools: some View {
        if !workspace.preparation.ready, workspace.preparation.pending != nil {
            Text("Preparing image…").font(metrics.typography.bar).padding(.horizontal, metrics.spacing.md)
        } else if workspace.displays != nil {
            Text("Drag across displays").font(metrics.typography.bar).padding(.horizontal, metrics.spacing.md)
        } else if let pending = coordinator.pendingCapture {
            Text(
                pending.axis == .vertical
                    ? String(localized: "Add below · Return") : String(localized: "Add to right · Return")
            )
            .font(metrics.typography.bar).padding(.horizontal, metrics.spacing.md)
        } else if let state = coordinator.editor, !workspace.selectingTarget {
            if workspace.request.mode == .screenshot {
                HStack(spacing: metrics.spacing.xxs) {
                    CaptureAnnotationTools(
                        state: state,
                        maximumItems: CaptureToolbarConfiguration.capacity(
                            length: availableWidth - 2 * metrics.spacing.xs - metrics.spacing.md
                                + metrics.spacing.xxs,
                            cell: metrics.scaled(Theme.Size.captureTool), spacing: metrics.spacing.xxs,
                            reserved: 5))
                    CaptureCompactStyle(state: state)
                }
            } else if workspace.request.mode == .scrolling {
                scrolling
            } else {
                CaptureRecordingPreparation(workspace: workspace)
            }
        } else if workspace.choosingElement || workspace.choosingWindow {
            Text(
                workspace.choosingElement
                    ? String(localized: "Click an element or drag") : String(localized: "Click a window")
            )
            .font(metrics.typography.bar).padding(.horizontal, metrics.spacing.md)
        }
    }

    private var scopes: some View {
        HStack(spacing: metrics.spacing.xxs) {
            CaptureIconButton(
                title: String(localized: "Region"), symbol: "viewfinder",
                selected: workspace.request.scope == .region
            ) {
                coordinator.setCaptureScope(.region)
            }
            CaptureIconButton(
                title: String(localized: "Window"), symbol: "macwindow", shortcut: "Space",
                selected: workspace.request.scope == .window
            ) {
                coordinator.setCaptureScope(.window)
            }
            CaptureIconButton(
                title: String(localized: "Screen"), symbol: "display",
                selected: workspace.request.scope == .screen
            ) {
                coordinator.setCaptureScope(.screen)
            }
        }
    }

    private var modes: some View {
        HStack(spacing: metrics.spacing.xxs) {
            CaptureIconButton(
                title: String(localized: "Screenshot"), symbol: "camera",
                selected: workspace.request.mode == .screenshot
            ) {
                coordinator.setCaptureMode(.screenshot)
            }
            CaptureIconButton(
                title: String(localized: "Scrolling Screenshot"),
                symbol: "arrow.down.right.and.arrow.up.left",
                selected: workspace.request.mode == .scrolling
            ) {
                coordinator.setCaptureMode(.scrolling)
            }
            CaptureIconButton(
                title: String(localized: "Record"), symbol: "record.circle",
                selected: workspace.request.mode == .recording
            ) {
                coordinator.setCaptureMode(.recording)
            }
        }
    }

    private var scrolling: some View {
        HStack(spacing: metrics.spacing.sm) {
            CaptureIconButton(
                title: String(localized: "Vertical"), symbol: "arrow.up.and.down",
                selected: workspace.axis == .vertical
            ) {
                workspace.axis = .vertical
            }
            CaptureIconButton(
                title: String(localized: "Horizontal"), symbol: "arrow.left.and.right",
                selected: workspace.axis == .horizontal
            ) {
                workspace.axis = .horizontal
            }
            Button("Start Scrolling") { coordinator.startSelectedScroll() }
                .buttonStyle(.borderedProminent).fixedSize().disabled(workspace.requiresScrollRegion)
        }
    }
}

struct CaptureWorkspaceOutputs: View {
    var availableHeight: CGFloat = Theme.Size.captureWorkspaceOutputs.height
    @Environment(CaptureCoordinator.self) private var coordinator
    @Environment(\.metrics) private var metrics

    var body: some View {
        VStack(spacing: metrics.spacing.xxs) {
            if coordinator.editor != nil, coordinator.workspace?.request.mode == .screenshot,
                coordinator.workspace?.selectingTarget == false
            {
                Group {
                    if coordinator.pendingCapture != nil {
                        CaptureIconButton(
                            title: String(localized: "Add Capture"), symbol: "plus", shortcut: "Return",
                            selected: true
                        ) {
                            coordinator.finishAppendCapture()
                        }
                    } else {
                        CaptureOutputTools(
                            inline: true,
                            maximumItems: CaptureToolbarConfiguration.capacity(
                                length: availableHeight - 2 * metrics.spacing.xs - metrics.spacing.md,
                                cell: metrics.scaled(Theme.Size.captureTool), spacing: metrics.spacing.xxs,
                                reserved: 3))
                    }
                }
                .disabled(coordinator.editor?.busy == true || coordinator.workspace?.busy == true)
                Divider().frame(width: metrics.size.rowIcon)
            }
            CaptureWorkspaceDismiss()
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

private struct CaptureWorkspaceDismiss: View {
    @Environment(CaptureCoordinator.self) private var coordinator

    var body: some View {
        if coordinator.editor?.busy == true || coordinator.workspace?.busy == true {
            CaptureIconButton(title: String(localized: "Cancel Operation"), symbol: "stop") {
                coordinator.cancelWork()
            }
        } else {
            CaptureIconButton(
                title: String(localized: "Close Capture"), symbol: "xmark", shortcut: "Esc · ⌘W"
            ) {
                coordinator.requestClose()
            }
        }
    }
}
