import AppKit
import Observation
import ScreenCaptureKit
import SwiftUI

@MainActor
final class CaptureSelectionView: NSView {
    private weak var coordinator: CaptureCoordinator?
    private let workspace: CaptureWorkspaceState
    private let screen: NSScreen
    private var canvas: NSView?
    private var tools: NSView?
    private var outputs: NSView?
    private var anchor = CGPoint.zero
    private var dragRect: CGRect?
    private var originalRect: CGRect?
    private var handle: CaptureSelectionGeometry.Handle?
    private var hoverWindow: SCWindow?
    private var hoverRect: CGRect?
    private var elementPoint: CGPoint?
    private var pointer: CGPoint?
    private var pendingElementPoint: CGPoint?
    private var elementTask: Task<Void, Never>?
    private var observationGeneration = 0
    private var pointerTracking: NSTrackingArea?
    private var loupeFrame: CGRect?

    init(frame: CGRect, coordinator: CaptureCoordinator, workspace: CaptureWorkspaceState, screen: NSScreen) {
        self.coordinator = coordinator
        self.workspace = workspace
        self.screen = screen
        super.init(frame: frame)
        setAccessibilityLabel(String(localized: "Capture selection"))
        if active {
            let tools = NSHostingView(
                rootView: CaptureWorkspaceToolbar(
                    workspace: workspace,
                    availableWidth: min(
                        frame.width - 2 * coordinator.metrics.spacing.md,
                        coordinator.metrics.scaled(Theme.Size.captureWorkspaceBar.width))
                )
                .environment(coordinator).environment(\.metrics, coordinator.metrics))
            let outputs = NSHostingView(
                rootView: CaptureWorkspaceOutputs(
                    availableHeight: frame.height - 2 * coordinator.metrics.spacing.md
                )
                .environment(coordinator).environment(\.metrics, coordinator.metrics))
            tools.clipsToBounds = false
            outputs.clipsToBounds = false
            tools.sizingOptions = .intrinsicContentSize
            outputs.sizingOptions = .intrinsicContentSize
            addSubview(tools)
            addSubview(outputs)
            self.tools = tools
            self.outputs = outputs
        }
        refresh()
    }

    required init?(coder: NSCoder) { nil }
    deinit { elementTask?.cancel() }
    override var acceptsFirstResponder: Bool { true }
    private var active: Bool { screen.frame == workspace.target.screenFrame }
    private var locked: Bool { workspace.busy || coordinator?.editor?.busy == true }
    private var selectedRect: CGRect? {
        if let selection = workspace.displays {
            if case .displays(let rect) = workspace.preparation.pending {
                return rect.offsetBy(dx: -screen.frame.minX, dy: -screen.frame.minY)
            }
            return selection.region.map { $0.offsetBy(dx: -screen.frame.minX, dy: -screen.frame.minY) }
        }
        if let dragRect { return dragRect }
        if case .region(let rect, _) = workspace.preparation.pending { return rect }
        if workspace.requiresScrollRegion { return nil }
        if workspace.selectingTarget { return hoverRect }
        return coordinator?.editor.flatMap { workspace.frame(for: $0.document) }
    }

    private func refresh() {
        guard let coordinator else { return }
        observationGeneration += 1
        let generation = observationGeneration
        withObservationTracking {
            _ = workspace.displays?.region
            _ = workspace.request
            _ = workspace.choosingWindow
            _ = workspace.choosingElement
            _ = workspace.requiresScrollRegion
            _ = workspace.busy
            _ = workspace.preparation
            _ = workspace.selectionOptions
            _ = coordinator.settings.toolbarConfiguration
            if active, let state = coordinator.editor {
                _ = state.document.revision
                _ = state.busy
                _ = state.tool
                _ = state.selected
                _ = state.imageAdjustments
                _ = state.font
                _ = state.codes
                _ = state.redactionCandidates
                _ = state.notice
                let content = CaptureCanvas(
                    state: state, fixedScale: 1 / workspace.scale(for: state.document),
                    moveSelection: { [weak self] delta, finished in
                        self?.moveSelection(delta, finished: finished)
                    })
                let view = content.inlineView(reusing: canvas)
                if canvas !== view {
                    canvas?.removeFromSuperview()
                    view.wantsLayer = true
                    addSubview(view, positioned: .below, relativeTo: tools)
                    canvas = view
                }
                if let frame = workspace.frame(for: state.document) { canvas?.frame = frame }
            }
            canvas?.isHidden = workspace.selectingTarget || workspace.request.mode != .screenshot
            canvas?.alphaValue = dragRect == nil ? 1 : 0
            if active { positionControls() }
            window?.invalidateCursorRects(for: self)
            updatePointer()
            needsDisplay = true
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, self.observationGeneration == generation else { return }
                self.refresh()
            }
        }
    }

    private func positionControls() {
        guard let coordinator else { return }
        let metrics = coordinator.metrics, gap = metrics.spacing.md
        var size = CGSize(
            width: min(bounds.width - 2 * gap, metrics.scaled(Theme.Size.captureWorkspaceBar.width)),
            height: metrics.scaled(Theme.Size.captureWorkspaceBar.height))
        var outputSize = CGSize(
            width: metrics.scaled(Theme.Size.captureTool) + 2 * metrics.spacing.xs,
            height: bounds.height - 2 * gap)
        if let tools {
            tools.setFrameSize(size)
            tools.layoutSubtreeIfNeeded()
            size.width = min(size.width, max(1, tools.fittingSize.width))
            tools.setFrameSize(size)
            tools.layoutSubtreeIfNeeded()
            size.height = min(size.height, max(1, tools.fittingSize.height))
        }
        if let outputs {
            outputs.setFrameSize(outputSize)
            outputs.layoutSubtreeIfNeeded()
            outputSize.height = min(outputSize.height, max(1, outputs.fittingSize.height))
        }
        let placement = CaptureControlPlacement.workspace(
            region: selectedRect, tools: size, outputs: outputSize, screen: bounds, gap: gap)
        tools?.frame = placement.tools
        outputs?.frame = placement.outputs
        tools?.isHidden = dragRect != nil || workspace.displays?.region != nil
        outputs?.isHidden =
            dragRect != nil || workspace.displays != nil || coordinator.editor == nil
            || workspace.selectingTarget || workspace.request.mode != .screenshot
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext, let coordinator else { return }
        let preview =
            workspace.displays?.snapshot(for: screen.frame)?.preview ?? (active ? workspace.preview : nil)
        defer { drawLoupe(in: context, image: preview) }
        guard active || workspace.displays != nil, preview != nil, let rect = selectedRect else { return }
        let mask = NSBezierPath(rect: bounds)
        mask.appendRect(rect.intersection(bounds))
        mask.windingRule = .evenOdd
        NSColor.black.withAlphaComponent(0.35).setFill()
        mask.fill()
        NSColor.controlAccentColor.setStroke()
        NSBezierPath(rect: rect).stroke()
        if !workspace.selectingTarget, workspace.displays == nil {
            for handle in CaptureSelectionGeometry.Handle.allCases {
                let point = CaptureSelectionGeometry.point(handle, in: rect)
                let side = Theme.Size.captureHandle
                let square = CGRect(x: point.x - side / 2, y: point.y - side / 2, width: side, height: side)
                NSColor.white.setFill()
                square.fill()
                NSBezierPath(rect: square).stroke()
            }
        }
        let scale = workspace.displays?.snapshots.map(\.display.scale).max() ?? workspace.target.scale
        let dimensions = "\(Int(rect.width * scale)) × \(Int(rect.height * scale))"
        let text = NSAttributedString(
            string: dimensions,
            attributes: [
                .font: coordinator.metrics.typography.chipNSFont,
                .foregroundColor: NSColor.white, .backgroundColor: NSColor.black.withAlphaComponent(0.7)
            ])
        text.draw(
            at: CGPoint(
                x: max(0, rect.minX),
                y: min(bounds.maxY - text.size().height, rect.maxY + coordinator.metrics.spacing.sm)))
    }

    private func hitHandle(_ point: CGPoint) -> CaptureSelectionGeometry.Handle? {
        guard workspace.displays == nil, !workspace.selectingTarget, let rect = selectedRect else {
            return nil
        }
        return CaptureSelectionGeometry.Handle.allCases.first {
            let anchor = CaptureSelectionGeometry.point($0, in: rect)
            return hypot(point.x - anchor.x, point.y - anchor.y) <= Theme.Size.captureHandle
        }
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        if !locked, hitHandle(local) != nil { return self }
        return super.hitTest(point)
    }

    override func mouseDown(with event: NSEvent) {
        guard let coordinator, !locked else { return }
        if let selection = workspace.displays {
            anchor = screenPoint(event)
            selection.region = nil
            window?.makeFirstResponder(self)
            return
        }
        if !active { coordinator.switchCaptureScreen(screen); return }
        coordinator.editor?.finishEditing()
        window?.makeFirstResponder(self)
        anchor = convert(event.locationInWindow, from: nil)
        originalRect = selectedRect
        handle = hitHandle(anchor)
        if workspace.choosingWindow { updateWindow(); return }
        if workspace.choosingElement { updateElement(at: screenPoint(event)); return }
        dragRect = handle == nil ? nil : originalRect
    }

    override func mouseDragged(with event: NSEvent) {
        if let selection = workspace.displays, !locked {
            selection.region = CaptureGeometry.selection(
                from: anchor, to: screenPoint(event), in: selection.bounds)
            return
        }
        guard active, !locked, !workspace.choosingWindow else { return }
        let rawPoint = convert(event.locationInWindow, from: nil)
        if workspace.choosingElement {
            guard hypot(rawPoint.x - anchor.x, rawPoint.y - anchor.y) > 4 else { return }
            workspace.choosingElement = false
            pendingElementPoint = nil
            originalRect = nil
        }
        let point =
            workspace.snaps && !event.modifierFlags.contains(.option)
            ? CaptureSelectionConstraint.snapped(
                rawPoint, edges: snapEdges, tolerance: Theme.Size.captureHandle)
            : rawPoint
        let ratio = event.modifierFlags.contains(.shift) ? 1 : workspace.aspect.ratio
        if let handle, let originalRect {
            dragRect = CaptureSelectionConstraint.resized(
                originalRect, handle: handle, to: point, ratio: ratio, in: bounds)
        } else if workspace.request.mode == .scrolling, let originalRect, originalRect.contains(anchor) {
            dragRect = CaptureSelectionGeometry.moved(
                originalRect, by: CGSize(width: point.x - anchor.x, height: point.y - anchor.y), in: bounds)
        } else {
            dragRect = CaptureSelectionConstraint.selection(from: anchor, to: point, ratio: ratio, in: bounds)
        }
        canvas?.alphaValue = 0
        positionControls()
        needsDisplay = true
    }

    private var snapEdges: [CGRect] {
        [bounds]
            + workspace.target.windows.map { window in
                CGRect(
                    x: window.frame.minX - screen.frame.minX,
                    y: (NSScreen.primary?.frame.maxY ?? 0) - window.frame.maxY - screen.frame.minY,
                    width: window.frame.width, height: window.frame.height
                ).intersection(bounds)
            }.filter { !$0.isNull && !$0.isEmpty }
    }

    override func mouseUp(with event: NSEvent) {
        if let selection = workspace.displays, !locked {
            if let region = selection.region { coordinator?.selectDisplaysRegion(region) }
            selection.region = nil
            return
        }
        guard active, !locked else { return }
        if workspace.choosingWindow {
            if let hoverWindow { coordinator?.selectWindow(hoverWindow) }
        } else if workspace.choosingElement {
            let point = screenPoint(event)
            if elementPoint == point, let hoverRect {
                coordinator?.selectRegion(hoverRect)
            } else {
                pendingElementPoint = point
                updateElement(at: point)
            }
        } else if let dragRect {
            coordinator?.selectRegion(dragRect)
        }
        dragRect = nil
        originalRect = nil
        handle = nil
        refresh()
    }

    private func moveSelection(_ delta: CGSize, finished: Bool) {
        guard active, !locked else { return }
        if originalRect == nil { originalRect = selectedRect }
        guard let originalRect else { return }
        dragRect = CaptureSelectionGeometry.moved(originalRect, by: delta, in: bounds)
        if finished {
            if let dragRect { coordinator?.selectRegion(dragRect) }
            self.originalRect = nil
            dragRect = nil
        }
        canvas?.alphaValue = finished ? 1 : 0
        positionControls()
        needsDisplay = true
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let pointerTracking { removeTrackingArea(pointerTracking) }
        let area = NSTrackingArea(
            rect: .zero,
            options: [.activeInKeyWindow, .inVisibleRect, .mouseMoved, .mouseEnteredAndExited, .cursorUpdate],
            owner: self)
        addTrackingArea(area)
        pointerTracking = area
    }

    override func mouseEntered(with event: NSEvent) { updatePointer() }
    override func mouseExited(with event: NSEvent) { needsDisplay = true }
    override func cursorUpdate(with event: NSEvent) { updatePointer() }

    func updatePointer() {
        guard let window, window.isVisible, window.isKeyWindow else { return }
        let point = convert(window.convertPoint(fromScreen: NSEvent.mouseLocation), from: nil)
        guard bounds.contains(point) else { return }
        let overControls = [tools, outputs].contains { view in
            view.map { !$0.isHidden && $0.frame.contains(point) } ?? false
        }
        let cursor: NSCursor
        if locked || overControls {
            cursor = .arrow
        } else if workspace.selectingTarget {
            cursor = .pointingHand
        } else if let handle = hitHandle(point) {
            cursor = resizeCursor(for: handle)
        } else if let rect = selectedRect {
            if rect.contains(point), workspace.request.mode == .scrolling {
                cursor = .openHand
            } else if rect.contains(point), let state = coordinator?.editor {
                cursor =
                    state.pickingColor
                    ? .crosshair
                    : state.tool == .text ? .iBeam : state.tool == .select ? .arrow : .crosshair
            } else {
                cursor = .arrow
            }
        } else {
            cursor = .crosshair
        }
        cursor.set()
        if let loupeFrame { setNeedsDisplay(loupeFrame) }
        if coordinator?.editor == nil, let metrics = coordinator?.metrics {
            let frame = CaptureSelectionLoupe.frame(at: point, bounds: bounds, metrics: metrics)
            setNeedsDisplay(frame)
            loupeFrame = frame
        } else {
            loupeFrame = nil
        }
    }

    private func drawLoupe(in context: CGContext, image: CGImage?) {
        guard !locked, coordinator?.editor == nil, !workspace.selectingTarget,
            workspace.displays == nil, let image, let window
        else { return }
        let point = convert(window.convertPoint(fromScreen: NSEvent.mouseLocation), from: nil)
        guard bounds.contains(point),
            ![tools, outputs].contains(where: { view in
                view.map { !$0.isHidden && $0.frame.contains(point) } ?? false
            })
        else { return }
        CaptureSelectionLoupe.draw(
            image: image, at: point, bounds: bounds,
            context: context, metrics: coordinator?.metrics ?? .standard)
    }

    private func resizeCursor(for handle: CaptureSelectionGeometry.Handle) -> NSCursor {
        let position: NSCursor.FrameResizePosition =
            switch handle {
            case .bottomLeft: .bottomLeft
            case .bottom: .bottom
            case .bottomRight: .bottomRight
            case .right: .right
            case .topRight: .topRight
            case .top: .top
            case .topLeft: .topLeft
            case .left: .left
            }
        return .frameResize(position: position, directions: [.inward, .outward])
    }

    override func mouseMoved(with event: NSEvent) {
        updatePointer()
        if workspace.choosingWindow { updateWindow() }
        if workspace.choosingElement { updateElement(at: screenPoint(event)) }
    }

    override func resetCursorRects() {
        guard !locked else { return }
        addCursorRect(
            bounds,
            cursor: workspace.selectingTarget
                ? .pointingHand
                : selectedRect == nil ? .crosshair : .arrow)
        for view in [tools, outputs].compactMap({ $0 }) where !view.isHidden {
            addCursorRect(view.frame, cursor: .arrow)
        }
        guard workspace.displays == nil else { return }
        guard !workspace.selectingTarget, let rect = selectedRect else { return }
        if workspace.request.mode == .scrolling { addCursorRect(rect, cursor: .openHand) }
        for handle in CaptureSelectionGeometry.Handle.allCases {
            let point = CaptureSelectionGeometry.point(handle, in: rect)
            let side = Theme.Size.captureHandle
            addCursorRect(
                CGRect(x: point.x - side, y: point.y - side, width: side * 2, height: side * 2),
                cursor: resizeCursor(for: handle))
        }
    }

    private func updateWindow() {
        guard active, !locked else { return }
        hoverWindow = CaptureScreenService.window(at: NSEvent.mouseLocation, target: workspace.target)
        hoverRect = hoverWindow.map {
            CGRect(
                x: $0.frame.minX - workspace.target.screenFrame.minX,
                y: (NSScreen.primary?.frame.maxY ?? 0) - $0.frame.maxY - workspace.target.screenFrame.minY,
                width: $0.frame.width, height: $0.frame.height
            ).intersection(bounds)
        }
        positionControls()
        needsDisplay = true
    }

    private func screenPoint(_ event: NSEvent) -> CGPoint {
        let point = convert(event.locationInWindow, from: nil)
        return CGPoint(x: screen.frame.minX + point.x, y: screen.frame.minY + point.y)
    }

    private func updateElement(at point: CGPoint) {
        guard active, !locked, workspace.choosingElement else { return }
        pointer = point
        if point != elementPoint { hoverRect = nil; needsDisplay = true }
        guard elementTask == nil else { return }
        guard let window = CaptureScreenService.window(at: point, target: workspace.target),
            let pid = window.owningApplication?.processID
        else { return }
        let top = NSScreen.primary?.frame.maxY ?? 0
        let quartz = CGPoint(x: point.x, y: top - point.y), windowFrame = window.frame
        elementTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .milliseconds(60))
                let rect = try await CaptureWork.run { try CaptureElementAccess.frame(pid: pid, at: quartz) }
                try Task.checkCancellation()
                guard let self else { return }
                self.elementTask = nil
                guard self.workspace.choosingElement else { return }
                guard point == self.pointer else {
                    self.pendingElementPoint = nil
                    if let latest = self.pointer { self.updateElement(at: latest) }
                    return
                }
                self.elementPoint = point
                self.hoverRect = rect.map { rect in
                    let clipped = rect.intersection(windowFrame)
                    return CGRect(
                        x: clipped.minX - self.screen.frame.minX,
                        y: top - clipped.maxY - self.screen.frame.minY,
                        width: clipped.width, height: clipped.height
                    ).intersection(self.bounds)
                }.flatMap { CaptureGeometry.valid($0) ? $0 : nil }
                if self.pendingElementPoint == point {
                    self.pendingElementPoint = nil
                    if let rect = self.hoverRect {
                        self.coordinator?.selectRegion(rect)
                    } else {
                        self.coordinator?.core.showMessage(
                            String(localized: "This element is unavailable. Drag to select a region."),
                            tone: .neutral)
                    }
                }
                self.positionControls()
                self.needsDisplay = true
            } catch { self?.elementTask = nil }
        }
    }

    override func keyDown(with event: NSEvent) {
        guard let coordinator else { return }
        if CaptureWorkspaceKeys.handle(event, coordinator: coordinator) { return }
        if !workspace.selectingTarget, event.modifierFlags.isDisjoint(with: [.command, .control, .option]),
            let tool = CaptureAnnotation.Tool.shortcut(event.charactersIgnoringModifiers)
        {
            coordinator.editor?.tool = tool; return
        }
        super.keyDown(with: event)
    }
}
