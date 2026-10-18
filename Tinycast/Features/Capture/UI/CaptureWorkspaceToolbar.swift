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
            .captureBar(metrics)
            if workspace.selectionOptions {
                CaptureSelectionControls(workspace: workspace)
                    .captureBar(metrics)
            }
            if let prompt {
                prompt.captureNotice(metrics)
            } else if let notice = coordinator.editor?.notice {
                Text(notice).captureNotice(metrics)
            } else if workspace.requiresScrollRegion {
                Text("Select the scrolling content inside the window").captureNotice(metrics)
            } else if workspace.request.mode != .screenshot,
                coordinator.editor?.document.edit.isEmpty == false
            {
                Text("Use this region · annotations stay in the screenshot").captureNotice(metrics)
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
                    title: String(localized: "Capture All Displays"), symbol: "display.2", shortcut: "↵"
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

    /// Instructions sit under the bar, so the bar keeps its icons and width while they change.
    private var prompt: Text? {
        if !workspace.preparation.ready, workspace.preparation.pending != nil {
            return Text("Preparing image…")
        } else if workspace.displays != nil {
            return Text("Drag across displays")
        } else if let pending = coordinator.pendingCapture {
            let key = KeyCapChip.inlineText(["↵"])
            return pending.axis == .vertical ? Text("Add below  \(key)") : Text("Add to the right  \(key)")
        } else if coordinator.editor == nil || workspace.selectingTarget,
            workspace.choosingElement || workspace.choosingWindow
        {
            return workspace.choosingElement ? Text("Click an element or drag") : Text("Click a window")
        }
        return nil
    }

    @ViewBuilder private var tools: some View {
        if !workspace.preparation.ready, workspace.preparation.pending != nil {
            EmptyView()
        } else if workspace.displays != nil || coordinator.pendingCapture != nil {
            EmptyView()
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
                title: String(localized: "Window"), symbol: "macwindow", shortcut: "␣",
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
                symbol: "scroll",
                selected: workspace.request.mode == .scrolling
            ) {
                coordinator.setCaptureMode(.scrolling)
            }
            CaptureIconButton(
                title: String(localized: "Record Screen"), symbol: "record.circle",
                selected: workspace.request.mode == .recording
            ) {
                coordinator.setCaptureMode(.recording)
            }
        }
    }

    private var scrolling: some View {
        HStack(spacing: metrics.spacing.xxs) {
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
            CaptureIconButton(title: String(localized: "Start Scrolling"), symbol: "play.fill", shortcut: "↵") {
                coordinator.startSelectedScroll()
            }
            .disabled(workspace.requiresScrollRegion)
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
                            title: String(localized: "Add Capture"), symbol: "plus", shortcut: "↵",
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
        .captureBar(metrics)
        .foregroundStyle(Theme.Colors.textPrimary)
        .frame(maxWidth: .infinity)
        .fixedSize(horizontal: false, vertical: true)
    }
}

private struct CaptureWorkspaceDismiss: View {
    @Environment(CaptureCoordinator.self) private var coordinator

    var body: some View {
        if coordinator.editor?.busy == true || coordinator.workspace?.busy == true {
            CaptureIconButton(title: String(localized: "Cancel"), symbol: "stop") {
                coordinator.cancelWork()
            }
        } else {
            CaptureIconButton(
                title: String(localized: "Close Capture"), symbol: "xmark", shortcut: "⎋ · ⌘W"
            ) {
                coordinator.requestClose()
            }
        }
    }
}
