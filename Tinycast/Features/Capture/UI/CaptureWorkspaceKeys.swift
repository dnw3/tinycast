import AppKit

@MainActor
enum CaptureWorkspaceKeys {
    static func handleSave(_ event: NSEvent, coordinator: CaptureCoordinator) -> Bool {
        guard event.modifierFlags.intersection([.command, .control, .option]) == .command,
            event.keyCode == 1, coordinator.savePanel == nil, let editor = coordinator.editor,
            !editor.busy, coordinator.workspace?.busy != true,
            coordinator.pendingCapture == nil, coordinator.workspace?.selectingTarget != true,
            coordinator.workspace == nil || coordinator.workspace?.request.mode == .screenshot
        else { return false }
        if event.modifierFlags.contains(.shift) { coordinator.saveAs() } else { coordinator.save() }
        return true
    }

    static func handle(_ event: NSEvent, coordinator: CaptureCoordinator) -> Bool {
        guard coordinator.savePanel == nil, let workspace = coordinator.workspace else { return false }
        if workspace.busy || coordinator.editor?.busy == true {
            if event.keyCode == 53 { coordinator.cancelWork() }
            return true
        }
        if coordinator.pendingCapture != nil {
            switch event.keyCode {
            case 53: coordinator.restoreAppendCapture()
            case 36, 76: coordinator.completeSelection()
            case 49: coordinator.setCaptureScope(workspace.request.scope == .window ? .region : .window)
            default: break
            }
            return true
        }
        if event.modifierFlags.contains(.command) {
            switch event.charactersIgnoringModifiers?.lowercased() {
            case "c":
                if workspace.request.mode == .screenshot, !workspace.selectingTarget { coordinator.copy() }
                return true
            case "s":
                if workspace.request.mode == .screenshot, !workspace.selectingTarget {
                    if event.modifierFlags.contains(.shift) { coordinator.saveAs() } else { coordinator.save() }
                }
                return true
            case "v":
                if workspace.request.mode == .screenshot, !workspace.selectingTarget { coordinator.addImage(clipboard: true) }
                return true
            case "w": coordinator.requestClose(); return true
            case "z":
                coordinator.editor?.finishEditing()
                if event.modifierFlags.contains(.shift) { coordinator.editor?.redoEdit() } else { coordinator.editor?.undoEdit() }
                return true
            default: return false
            }
        }
        guard event.modifierFlags.isDisjoint(with: [.command, .control, .option]) else { return false }
        switch event.keyCode {
        case 53:
            if coordinator.editor?.pickingColor == true {
                coordinator.editor?.cancelPickingColor()
            } else if workspace.choosingElement {
                workspace.choosingElement = false
            } else if coordinator.editor?.redactionCandidates.isEmpty == false {
                coordinator.editor?.redactionCandidates = []
            } else if coordinator.editor?.imageAdjustments == true {
                coordinator.editor?.finishEditing()
                coordinator.editor?.imageAdjustments = false
            } else if workspace.choosingWindow, coordinator.editor != nil {
                coordinator.setCaptureScope(.region)
            } else if coordinator.editor?.selected != nil {
                coordinator.editor?.selected = nil
            } else if coordinator.editor?.tool != nil, coordinator.editor?.tool != .select {
                coordinator.editor?.tool = .select
            } else if workspace.request.mode != .screenshot {
                coordinator.setCaptureMode(.screenshot)
            } else { coordinator.requestClose() }
            return true
        case 36, 76: coordinator.completeSelection(); return true
        case 49:
            coordinator.setCaptureScope(workspace.request.scope == .window ? .region : .window)
            return true
        default: return false
        }
    }
}
