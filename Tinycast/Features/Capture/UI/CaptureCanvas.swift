import AppKit
import SwiftUI

struct CaptureCanvas: NSViewRepresentable {
    let state: CaptureEditorState
    var fixedScale: CGFloat?
    var moveSelection: ((CGSize, Bool) -> Void)?

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.autohidesScrollers = true
        scroll.hasVerticalScroller = fixedScale == nil
        scroll.hasHorizontalScroller = fixedScale == nil
        if fixedScale == nil {
            let clip = ClipView()
            clip.drawsBackground = false
            scroll.contentView = clip
            scroll.automaticallyAdjustsContentInsets = false
        }
        let canvas = Canvas(state: state)
        canvas.fixedScale = fixedScale
        canvas.moveSelection = moveSelection
        scroll.documentView = canvas
        return scroll
    }

    /// The backdrop around the image in the editor, so the image never touches the well's edge.
    private func margin(_ scroll: NSScrollView, context: Context) {
        guard fixedScale == nil else { return }
        let margin = context.environment.metrics.scaled(Theme.Size.captureCanvasMargin)
        let insets = NSEdgeInsets(top: margin, left: margin, bottom: margin, right: margin)
        guard scroll.contentInsets.top != margin else { return }
        scroll.contentInsets = insets
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        margin(scroll, context: context)
        _ = state.document.revision
        _ = state.selected
        _ = state.tool
        _ = state.pickingColor
        _ = state.redactionCandidates
        _ = state.redactionIndex
        _ = state.translationReview?.index
        let canvas: Canvas
        if let current = scroll.documentView as? Canvas, current.state === state {
            canvas = current
        } else {
            canvas = Canvas(state: state)
            scroll.documentView = canvas
        }
        canvas.fixedScale = fixedScale
        canvas.moveSelection = moveSelection
        canvas.framesImage = fixedScale == nil
        canvas.refresh()
    }

    func inlineView(reusing view: NSView?) -> NSView {
        let canvas = (view as? Canvas).flatMap { $0.state === state ? $0 : nil } ?? Canvas(state: state)
        canvas.fixedScale = fixedScale
        canvas.moveSelection = moveSelection
        canvas.refresh()
        return canvas
    }

    private final class ClipView: NSClipView {
        override func constrainBoundsRect(_ proposedBounds: NSRect) -> NSRect {
            var result = super.constrainBoundsRect(proposedBounds)
            guard let documentView else { return result }
            if result.width > documentView.frame.width {
                result.origin.x = (documentView.frame.width - result.width) / 2
            }
            if result.height > documentView.frame.height {
                result.origin.y = (documentView.frame.height - result.height) / 2
            }
            return result
        }
    }

    private final class Canvas: NSView {
        let state: CaptureEditorState
        var fixedScale: CGFloat?
        /// In the editor window the image floats on the well; on the desktop it is the desktop.
        var framesImage = false {
            didSet {
                guard framesImage != oldValue else { return }
                wantsLayer = framesImage
                layer?.masksToBounds = !framesImage
                updateShadowColor()
                layer?.shadowOpacity = framesImage ? 1 : 0
                layer?.shadowRadius = Theme.Spacing.md
                layer?.shadowOffset = CGSize(width: 0, height: -Theme.Spacing.xxs)
                updateShadowPath()
                needsDisplay = true
            }
        }
        var moveSelection: ((CGSize, Bool) -> Void)?
        private var zoom: CGFloat { fixedScale ?? state.zoom }
        private var movingSelection = false
        private var selectionAnchor = CGPoint.zero
        private var previewPieces: [CaptureDocument.Piece] = []
        private var previewAdjustments: CaptureImageAdjustments?
        private var previewAnnotations: [CaptureAnnotation] = []
        private var previewLayers: [CaptureImageLayer] = []
        private var previewPresentation: CapturePresentation?
        private var previewTranslation: CaptureTranslation?
        private var previewBounds = CGRect.zero
        private var tiles: [String: CGImage] = [:]
        private var preview: CGImage?
        private var loading: Task<Void, Never>?
        private var loadingPreview: Task<Void, Never>?
        private var fitting: Task<Void, Never>?
        private var sampling: Task<Void, Never>?
        private var currentZoom = 1.0
        private var renderedRevision = -1
        private var generation = 0
        private var fitID: UUID?
        private var lastViewport = CGSize.zero
        private var reviewedRect: CGRect?
        private var anchor = CGPoint.zero
        private var draft: CaptureAnnotation?
        private var beforeDrag: CaptureAnnotation?
        private var beforeImage: CaptureImageLayer?
        private var crop: CGRect?
        private var textEditor: CaptureTextEditor?
        private var editingAnnotation: CaptureAnnotation?
        private var resizing = false
        private var movingControl = false
        private var movingEndpoint: Int?
        private var alignment: CaptureAnnotationPlacement.Result?

        init(state: CaptureEditorState) {
            self.state = state
            super.init(frame: .zero)
            setAccessibilityLabel(String(localized: "Screenshot canvas"))
            setAccessibilityRole(.image)
            state.finishText = { [weak self] in self?.finishText() }
            state.cancelEditingWork = { [weak self] in self?.sampling?.cancel() }
        }

        private func loadPreview() {
            previewPieces = state.document.pieces
            previewAdjustments = state.document.edit.adjustments
            previewAnnotations = rasterAnnotations
            previewLayers = state.document.imageLayers
            previewPresentation = state.document.edit.presentation
            previewTranslation = state.document.edit.translation
            previewBounds = state.document.outputBounds
            preview = nil
            loadingPreview?.cancel()
            let snapshot = state.document, source = state.source
            loadingPreview = Task { [weak self] in
                do {
                    let image = try await CaptureWork.run {
                        try CaptureRenderer.preview(
                            document: snapshot, directory: source.directory, maximum: 1000,
                            includingVectorAnnotations: false)
                    }
                    try Task.checkCancellation()
                    self?.preview = image
                    self?.needsDisplay = true
                } catch is CancellationError {
                    return
                } catch {
                    self?.state.notice = Bundle.main.localizedString(
                        forKey: error.localizedDescription, value: nil, table: nil)
                }
            }
        }

        private var rasterAnnotations: [CaptureAnnotation] {
            let annotations = state.document.edit.annotations
            if annotations.contains(where: { $0.tool == .magnifier }) { return annotations }
            return annotations.filter { [.pixelate, .blur, .cover, .erase].contains($0.tool) }
        }

        required init?(coder: NSCoder) { nil }
        isolated deinit { loading?.cancel(); loadingPreview?.cancel(); fitting?.cancel(); sampling?.cancel() }
        override var isFlipped: Bool { true }

        override func setFrameSize(_ newSize: NSSize) {
            super.setFrameSize(newSize)
            updateShadowPath()
        }

        /// A path, so the shadow of a canvas many screens tall costs no offscreen pass.
        private func updateShadowPath() {
            layer?.shadowPath = framesImage ? CGPath(rect: bounds, transform: nil) : nil
        }

        override func viewDidChangeEffectiveAppearance() {
            super.viewDidChangeEffectiveAppearance()
            updateShadowColor()
        }

        /// A layer keeps a fixed colour, so the shadow resolves against this view's appearance.
        private func updateShadowColor() {
            effectiveAppearance.performAsCurrentDrawingAppearance {
                layer?.shadowColor = NSColor(Theme.Colors.captureImageShadow).cgColor
            }
        }
        override var acceptsFirstResponder: Bool { true }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if window == nil {
                loading?.cancel(); loadingPreview?.cancel(); fitting?.cancel(); sampling?.cancel()
            }
        }

        override func layout() {
            super.layout()
            guard let scroll = enclosingScrollView, scroll.contentSize != lastViewport else { return }
            lastViewport = scroll.contentSize
            if state.followsViewport { fitID = nil }
            refresh()
        }

        func refresh() {
            if previewBounds != state.document.outputBounds, state.followsViewport { fitID = nil }
            if previewPieces != state.document.pieces || previewAdjustments != state.document.edit.adjustments
                || previewAnnotations != rasterAnnotations || previewBounds != state.document.outputBounds
                || previewLayers != state.document.imageLayers
                || previewPresentation != state.document.edit.presentation
                || previewTranslation != state.document.edit.translation
            {
                loadPreview()
            }
            if renderedRevision != state.document.revision {
                renderedRevision = state.document.revision
                generation += 1
                loading?.cancel()
                loading = nil
                tiles.removeAll()
            }
            if let fixedScale {
                let bounds = state.document.outputBounds
                setFrameSize(CGSize(width: bounds.width * fixedScale, height: bounds.height * fixedScale))
                currentZoom = fixedScale
                needsDisplay = true
                window?.invalidateCursorRects(for: self)
                return
            }
            guard let scroll = enclosingScrollView else { return }
            if fixedScale == nil, state.followsViewport, fitID != state.fitRequest,
                scroll.contentSize.width > 0
            {
                fitID = state.fitRequest
                let fit: CaptureViewportPolicy.Fit =
                    state.fitMode
                    ?? (state.document.axis == .vertical
                        ? .width
                        : state.document.axis == .horizontal
                            ? .height
                            : CaptureViewportPolicy.preferredFit(image: state.document.outputBounds.size))
                let insets = scroll.contentInsets
                let zoom = CaptureViewportPolicy.scale(
                    image: state.document.outputBounds.size,
                    viewport: CGSize(
                        width: max(1, scroll.contentSize.width - insets.left - insets.right),
                        height: max(1, scroll.contentSize.height - insets.top - insets.bottom)),
                    fit: fit)
                fitting?.cancel()
                fitting = Task { [weak self] in
                    await Task.yield()
                    guard !Task.isCancelled, let self else { return }
                    self.state.zoom = zoom
                    self.refresh()
                    let proposed = CGRect(
                        origin: CGPoint(x: -insets.left, y: -insets.top), size: scroll.contentSize)
                    scroll.contentView.scroll(to: scroll.contentView.constrainBoundsRect(proposed).origin)
                    scroll.reflectScrolledClipView(scroll.contentView)
                }
            }
            let bounds = state.document.outputBounds
            let center = CGPoint(x: visibleRect.midX / currentZoom, y: visibleRect.midY / currentZoom)
            setFrameSize(CGSize(width: bounds.width * zoom, height: bounds.height * zoom))
            if currentZoom != zoom {
                let origin = CGPoint(
                    x: max(
                        0,
                        min(
                            frame.width - scroll.contentSize.width,
                            center.x * zoom - scroll.contentSize.width / 2)),
                    y: max(
                        0,
                        min(
                            frame.height - scroll.contentSize.height,
                            center.y * zoom - scroll.contentSize.height / 2)))
                scroll.contentView.scroll(to: origin)
                scroll.reflectScrolledClipView(scroll.contentView)
                currentZoom = zoom
            }
            let translation = state.translationReview
            let paragraph = translation.flatMap {
                $0.translation.blocks.indices.contains($0.index)
                    ? $0.translation.blocks[$0.index].rect : nil
            }
            let review =
                paragraph
                ?? (state.redactionCandidates.indices.contains(state.redactionIndex)
                    ? state.redactionCandidates[state.redactionIndex].rect : nil)
            if review != reviewedRect {
                reviewedRect = review
                if let review, fixedScale == nil {
                    let origin = CGPoint(
                        x: max(
                            0,
                            min(
                                frame.width - scroll.contentSize.width,
                                (review.midX - bounds.minX) * zoom - scroll.contentSize.width / 2)),
                        y: max(
                            0,
                            min(
                                frame.height - scroll.contentSize.height,
                                (review.midY - bounds.minY) * zoom - scroll.contentSize.height / 2)))
                    scroll.contentView.scroll(to: origin)
                    scroll.reflectScrolledClipView(scroll.contentView)
                }
            }
            needsDisplay = true
            scroll.contentView.scroll(
                to: scroll.contentView.constrainBoundsRect(scroll.contentView.bounds).origin)
            window?.invalidateCursorRects(for: self)
        }

        override func resetCursorRects() {
            guard !state.busy else { return }
            let cursor: NSCursor =
                state.pickingColor
                ? .crosshair
                : state.tool == .text ? .iBeam : state.tool == .select ? .arrow : .crosshair
            addCursorRect(visibleRect, cursor: cursor)
        }

        override func draw(_ dirtyRect: NSRect) {
            guard let context = NSGraphicsContext.current?.cgContext else { return }
            let origin = state.document.outputBounds.origin
            context.saveGState()
            context.scaleBy(x: zoom, y: zoom)
            context.translateBy(x: -origin.x, y: -origin.y)
            if let preview { drawImage(preview, rect: previewBounds, context: context) }
            let visible = CGRect(
                x: visibleRect.minX / zoom + origin.x,
                y: visibleRect.minY / zoom + origin.y,
                width: visibleRect.width / zoom, height: visibleRect.height / zoom)
            var requested: [(String, CGRect)] = []
            let output = state.document.outputBounds
            for y in stride(
                from: Int(output.minY) + max(0, Int(visible.minY - output.minY) / 1024 * 1024),
                to: Int(min(visible.maxY, output.maxY)), by: 1024)
            {
                for x in stride(
                    from: Int(output.minX) + max(0, Int(visible.minX - output.minX) / 1024 * 1024),
                    to: Int(min(visible.maxX, output.maxX)), by: 1024)
                {
                    let rect = CGRect(
                        x: x, y: y, width: min(1024, Int(output.maxX) - x),
                        height: min(1024, Int(output.maxY) - y))
                    requested.append(("\(x)-\(y)", rect))
                }
            }
            if preview == nil {
                CaptureAnnotationRenderer.draw(
                    state.document.edit.annotations.filter {
                        [.pixelate, .blur, .magnifier].contains($0.tool)
                    }, in: context)
            }
            let selected = Array(requested.prefix(4))
            for (key, rect) in selected {
                if let tile = tiles[key] {
                    context.saveGState()
                    context.setShouldAntialias(false)
                    context.clip(to: rect)
                    context.setBlendMode(.copy)
                    drawImage(tile, rect: rect, context: context)
                    context.restoreGState()
                }
            }
            load(selected)
            var annotations = state.document.edit.annotations.filter {
                ![.pixelate, .blur, .magnifier].contains($0.tool) && $0.id != editingAnnotation?.id
            }
            if let draft {
                if let index = annotations.firstIndex(where: { $0.id == draft.id }) {
                    annotations[index] = draft
                } else {
                    annotations += state.snappedHighlights(draft) ?? [draft]
                }
            }
            context.saveGState()
            context.clip(to: state.document.contentBounds)
            context.addPath(CapturePresentationRenderer.path(state.document))
            context.clip()
            for lens in state.document.edit.annotations where lens.tool == .magnifier {
                context.addRect(state.document.outputBounds)
                context.addEllipse(in: lens.bounds)
                context.clip(using: .evenOdd)
            }
            CaptureAnnotationRenderer.draw(annotations, in: context)
            context.restoreGState()
            context.saveGState()
            context.clip(to: state.document.contentBounds)
            context.addPath(CapturePresentationRenderer.path(state.document))
            context.clip()
            CaptureAnnotationRenderer.draw(
                annotations.filter { $0.tool == .cover || $0.tool == .erase }, in: context)
            context.restoreGState()
            for (index, candidate) in state.redactionCandidates.enumerated() {
                context.saveGState()
                context.setStrokeColor(
                    NSColor.controlAccentColor.withAlphaComponent(candidate.included ? 1 : 0.3).cgColor)
                context.setLineWidth((index == state.redactionIndex ? 3 : 1) / zoom)
                context.setLineDash(phase: 0, lengths: [4 / zoom, 3 / zoom])
                context.stroke(candidate.rect)
                context.restoreGState()
            }
            if let selected = draft
                ?? state.document.edit.annotations.first(where: { $0.id == state.selected }),
                state.tool == .select, draft == nil || beforeDrag != nil
            {
                context.setStrokeColor(NSColor.controlAccentColor.cgColor)
                context.setLineWidth(1 / zoom)
                let side = Theme.Size.captureHandle / zoom
                if !selected.displayedEndpoints.isEmpty {
                    for point in selected.displayedEndpoints {
                        let rect = CGRect(x: point.x - side / 2, y: point.y - side / 2, width: side, height: side)
                        context.setFillColor(NSColor.controlAccentColor.cgColor)
                        context.fillEllipse(in: rect)
                        context.setStrokeColor(NSColor.white.cgColor)
                        context.strokeEllipse(in: rect)
                    }
                } else {
                    context.stroke(selected.bounds.insetBy(dx: -4 / zoom, dy: -4 / zoom))
                    context.stroke(CGRect(x: selected.bounds.maxX - side / 2, y: selected.bounds.maxY - side / 2,
                        width: side, height: side))
                }
            }
            if let selected =
                (draft ?? state.document.edit.annotations.first(where: { $0.id == state.selected })),
                let point = selected.displayedControl, state.tool == .select, draft == nil || beforeDrag != nil
            {
                let side = Theme.Size.captureHandle / zoom
                context.setStrokeColor(NSColor.controlAccentColor.cgColor)
                context.setLineWidth(1 / zoom)
                context.strokeEllipse(
                    in: CGRect(
                        x: point.x - side / 2, y: point.y - side / 2,
                        width: side, height: side))
            }
            if let image = state.selectedImage {
                context.setStrokeColor(NSColor.controlAccentColor.cgColor)
                context.setLineWidth(1 / zoom)
                context.stroke(image.bounds.insetBy(dx: -4 / zoom, dy: -4 / zoom))
                let side = Theme.Size.captureHandle / zoom
                context.stroke(
                    CGRect(
                        x: image.bounds.maxX - side / 2, y: image.bounds.maxY - side / 2,
                        width: side, height: side))
            }
            if let review = state.translationReview, review.translation.blocks.indices.contains(review.index)
            {
                context.setStrokeColor(NSColor.controlAccentColor.cgColor)
                context.setLineWidth(1 / zoom)
                context.stroke(
                    review.translation.blocks[review.index].rect.insetBy(dx: -2 / zoom, dy: -2 / zoom))
            }
            if let crop {
                context.setStrokeColor(NSColor.controlAccentColor.cgColor)
                context.setLineWidth(1 / zoom)
                context.stroke(crop)
            }
            if let alignment {
                context.setStrokeColor(NSColor.controlAccentColor.cgColor)
                context.setLineWidth(1 / zoom)
                context.setLineDash(phase: 0, lengths: [3 / zoom, 3 / zoom])
                if let x = alignment.verticalGuide {
                    context.move(to: CGPoint(x: x, y: visible.minY))
                    context.addLine(to: CGPoint(x: x, y: visible.maxY))
                }
                if let y = alignment.horizontalGuide {
                    context.move(to: CGPoint(x: visible.minX, y: y))
                    context.addLine(to: CGPoint(x: visible.maxX, y: y))
                }
                context.strokePath()
            }
            context.restoreGState()
            if framesImage {
                NSColor(Theme.Colors.captureImageEdge).setStroke()
                let edge = NSBezierPath(rect: bounds.insetBy(dx: 0.5, dy: 0.5))
                edge.lineWidth = Theme.Size.hairline
                edge.stroke()
            }
        }

        private func drawImage(_ image: CGImage, rect: CGRect, context: CGContext) {
            context.saveGState()
            context.translateBy(x: rect.minX, y: rect.maxY)
            context.scaleBy(x: 1, y: -1)
            context.draw(image, in: CGRect(origin: .zero, size: rect.size))
            context.restoreGState()
        }

        private func load(_ requested: [(String, CGRect)]) {
            guard loading == nil else { return }
            tiles = tiles.filter { key, _ in requested.contains { $0.0 == key } }
            let missing = requested.filter { tiles[$0.0] == nil }
            guard !missing.isEmpty else { return }
            let snapshot = state.document, source = state.source, generation = generation
            loading = Task { [weak self] in
                defer { if self?.generation == generation { self?.loading = nil } }
                for (key, rect) in missing {
                    do {
                        let image = try await CaptureWork.run {
                            try CaptureRenderer.image(
                                document: snapshot, directory: source.directory, rect: rect,
                                includingVectorAnnotations: false)
                        }
                        try Task.checkCancellation()
                        guard self?.generation == generation else { return }
                        self?.tiles[key] = image
                    } catch is CancellationError { return } catch {
                        self?.state.notice = Bundle.main.localizedString(
                            forKey: error.localizedDescription, value: nil, table: nil)
                        return
                    }
                }
                self?.needsDisplay = true
            }
        }

        private func point(_ event: NSEvent) -> CGPoint {
            let local = convert(event.locationInWindow, from: nil), output = state.document.outputBounds
            let bounds = state.pickingColor ? output : state.document.contentBounds
            return CGPoint(
                x: min(bounds.maxX, max(bounds.minX, local.x / zoom + output.minX)),
                y: min(bounds.maxY, max(bounds.minY, local.y / zoom + output.minY)))
        }

        override func mouseDown(with event: NSEvent) {
            guard !state.busy else { return }
            finishText()
            window?.makeFirstResponder(self)
            anchor = point(event)
            if state.pickingColor { sampleColor(at: anchor); return }
            movingSelection = false
            if state.tool == .select {
                if let selected = state.document.edit.annotations.first(where: { $0.id == state.selected }),
                    let endpoint = selected.displayedEndpoints.firstIndex(where: {
                        hypot(anchor.x - $0.x, anchor.y - $0.y) < 12 / zoom
                    })
                {
                    beforeDrag = selected; draft = selected; movingEndpoint = endpoint; return
                }
                if let selected = state.document.edit.annotations.first(where: { $0.id == state.selected }),
                    let control = selected.displayedControl,
                    hypot(anchor.x - control.x, anchor.y - control.y) < 12 / zoom
                {
                    beforeDrag = selected; draft = selected; movingControl = true; return
                }
                if let image = state.selectedImage,
                    hypot(anchor.x - image.bounds.maxX, anchor.y - image.bounds.maxY) < 12 / zoom
                {
                    beforeImage = image; resizing = true; state.undo.begin(state.document); return
                }
                if let selected = state.document.edit.annotations.first(where: { $0.id == state.selected }),
                    selected.displayedEndpoints.isEmpty,
                    hypot(anchor.x - selected.bounds.maxX, anchor.y - selected.bounds.maxY) < 12 / zoom
                {
                    beforeDrag = selected; draft = selected; resizing = true; return
                }
                let selected = state.document.edit.annotations.last {
                    $0.bounds.insetBy(dx: -8 / zoom, dy: -8 / zoom).contains(anchor)
                }
                if selected == nil,
                    let image = state.document.imageLayers.last(where: { $0.bounds.contains(anchor) })
                {
                    state.selected = image.id
                    beforeImage = image
                    resizing = false
                    state.undo.begin(state.document)
                    needsDisplay = true
                    return
                }
                state.selected = selected?.id
                if selected == nil, moveSelection != nil {
                    movingSelection = true
                    selectionAnchor = convert(event.locationInWindow, from: nil)
                }
                if let selected {
                    state.ink = selected.ink; state.color = selected.color; state.strokeWidth = selected.width
                    state.rotation = selected.rotation ?? 0
                    state.font = selected.font ?? .system
                    state.fontSize = selected.fontSize ?? selected.width * 6
                    if selected.tool == .text {
                        state.adoptTextStyle(selected.effectiveTextFormat.style(at: 0))
                    }
                    state.shapeStyle = selected.effectiveShapeStyle
                    state.cornerRadius = selected.cornerRadius ?? 0
                    state.arrowStyle = selected.arrowStyle ?? .open
                    state.reversed = selected.reversed ?? false
                    if selected.tool == .number {
                        state.numberStyle = selected.numberFormat?.style ?? .decimal
                        state.numberLeader = selected.numberLeader ?? false
                    }
                    if selected.tool == .pen { state.smoothPen = selected.smoothed ?? false }
                    if selected.tool == .emoji {
                        state.emoji = selected.text; state.emojiSize = selected.fontSize ?? 64
                    }
                    if selected.tool == .magnifier { state.magnification = selected.magnification ?? 2 }
                }
                if event.clickCount == 2, let selected, selected.tool == .text {
                    editingAnnotation = selected
                    anchor = selected.drawingBounds.origin
                    startText(at: anchor)
                    return
                }
                beforeDrag = selected
                draft = selected
                resizing = false
            } else if state.tool == .crop {
                crop = CGRect(origin: anchor, size: .zero)
            } else if state.tool == .text {
                startText(at: anchor)
            } else if state.tool == .emoji {
                draft = CaptureAnnotation(
                    id: UUID(), tool: .emoji,
                    points: [anchor], text: state.emoji,
                    rotation: state.rotation, fontSize: state.emojiSize)
                draft?.sizeEmoji(state.emojiSize, in: state.document.outputBounds)
            } else {
                guard state.tool != .number || (1...3999).contains(state.nextNumber) else {
                    state.notice = String(localized: "Choose a next number from 1 to 3999.")
                    return
                }
                draft = CaptureAnnotation(
                    id: UUID(), tool: state.tool, points: [anchor, anchor],
                    ink: state.ink, width: state.strokeWidth,
                    text: state.tool == .number ? String(state.nextNumber) : "",
                    rotation: [.cover, .pixelate, .blur, .spotlight, .erase, .magnifier].contains(state.tool)
                        ? nil : state.rotation,
                    color: state.tool == .erase ? nil : state.color,
                    magnification: state.tool == .magnifier ? state.magnification : nil,
                    arrowStyle: [.arrow, .curvedArrow].contains(state.tool) ? state.arrowStyle : nil,
                    reversed: [.arrow, .curvedArrow].contains(state.tool) && state.reversed ? true : nil,
                    shapeStyle: [.rectangle, .ellipse].contains(state.tool) ? state.shapeStyle : nil,
                    cornerRadius: state.tool == .rectangle ? state.cornerRadius : nil,
                    numberFormat: state.tool == .number
                        ? .init(style: state.numberStyle, value: state.nextNumber) : nil,
                    numberLeader: state.tool == .number ? state.numberLeader : nil,
                    smoothed: state.tool == .pen ? state.smoothPen : nil)
            }
            needsDisplay = true
        }

        private func sampleColor(at point: CGPoint) {
            let snapshot = state.document, source = state.source
            state.pickingColor = false
            state.busy = true
            sampling?.cancel()
            sampling = Task { [weak self] in
                defer { self?.state.busy = false }
                do {
                    let color = try await CaptureWork.run {
                        try CaptureRenderer.color(document: snapshot, directory: source.directory, at: point)
                    }
                    try Task.checkCancellation()
                    guard let self, self.state.document.revision == snapshot.revision else { return }
                    self.state.setColor(color)
                    self.state.notice = String(localized: "\(color.hex) — selected for annotations")
                } catch is CancellationError { return } catch {
                    self?.state.notice = Bundle.main.localizedString(
                        forKey: error.localizedDescription, value: nil, table: nil)
                }
            }
        }

        override func mouseDragged(with event: NSEvent) {
            guard !state.busy else { return }
            if movingSelection { moveRegion(with: event, finished: false); return }
            let next = point(event)
            if let original = beforeImage {
                var image = original
                if resizing {
                    let scale = max(
                        0.02,
                        min(
                            (next.x - original.bounds.minX) / original.bounds.width,
                            (next.y - original.bounds.minY) / original.bounds.height))
                    image.frame.size = CGSize(
                        width: max(1, original.frame.width * scale),
                        height: max(1, original.frame.height * scale))
                } else {
                    let targets =
                        event.modifierFlags.contains(.option)
                        ? []
                        : [state.document.outputBounds]
                            + state.document.imageLayers.filter { $0.id != original.id }.map(\.bounds)
                            + state.document.edit.annotations.map(\.bounds)
                    let placement = CaptureAnnotationPlacement.moved(
                        original.bounds,
                        by: CGSize(width: next.x - anchor.x, height: next.y - anchor.y),
                        in: state.document.bounds, aligning: targets, tolerance: 6 / zoom)
                    image.frame = original.frame.offsetBy(
                        dx: placement.offset.width, dy: placement.offset.height)
                    alignment = placement
                }
                state.updateImage(image)
                return
            }
            if let original = beforeDrag {
                draft = original
                if let movingEndpoint {
                    draft?.moveEndpoint(movingEndpoint, to: next)
                } else if movingControl {
                    draft?.controlCenter = original.transformCenter
                    if original.tool == .number {
                        draft?.points[original.points.count - 1] = original.untransformed(next)
                    } else {
                        draft?.controlPoint = original.untransformed(next)
                    }
                } else if resizing {
                    let scaleX =
                        original.bounds.width > 0
                        ? max(0.1, (next.x - original.bounds.minX) / original.bounds.width) : 1
                    let scaleY =
                        original.bounds.height > 0
                        ? max(0.1, (next.y - original.bounds.minY) / original.bounds.height) : 1
                    draft?.points = original.points.map {
                        CGPoint(
                            x: original.bounds.minX + ($0.x - original.bounds.minX) * scaleX,
                            y: original.bounds.minY + ($0.y - original.bounds.minY) * scaleY)
                    }
                    if let control = original.controlPoint {
                        draft?.controlPoint = CGPoint(
                            x: original.bounds.minX + (control.x - original.bounds.minX) * scaleX,
                            y: original.bounds.minY + (control.y - original.bounds.minY) * scaleY)
                    }
                    if let center = original.controlCenter {
                        draft?.controlCenter = CGPoint(
                            x: original.bounds.minX + (center.x - original.bounds.minX) * scaleX,
                            y: original.bounds.minY + (center.y - original.bounds.minY) * scaleY)
                    }
                    if original.points.count > 1 {
                        if original.bounds.width == 0 { draft?.points[original.points.count - 1].x = next.x }
                        if original.bounds.height == 0 { draft?.points[original.points.count - 1].y = next.y }
                    }
                    if [.number, .emoji].contains(original.tool) {
                        draft?.width = min(128, max(1, original.width * min(scaleX, scaleY)))
                        if let size = original.fontSize {
                            draft?.fontSize = min(768, max(6, size * min(scaleX, scaleY)))
                        }
                    }
                } else {
                    let targets =
                        event.modifierFlags.contains(.option)
                        ? []
                        : [state.document.outputBounds]
                            + state.document.edit.annotations.filter { $0.id != original.id }.map(\.bounds)
                    let placement = CaptureAnnotationPlacement.moved(
                        original.bounds,
                        by: CGSize(width: next.x - anchor.x, height: next.y - anchor.y),
                        in: state.document.bounds,
                        aligning: targets, tolerance: 6 / zoom)
                    draft?.move(by: placement.offset)
                    alignment = placement
                }
            } else if state.tool == .crop {
                crop = CaptureGeometry.selection(from: anchor, to: next, in: state.document.outputBounds)
            } else if state.tool == .pen || state.tool == .highlighter {
                if (draft?.points.count ?? 0) < 20_000 { draft?.points.append(next) }
            } else if draft != nil, state.tool != .emoji {
                draft?.points[1] = next
            }
            needsDisplay = true
        }

        override func mouseUp(with event: NSEvent) {
            guard !state.busy else { return }
            alignment = nil
            if beforeImage != nil {
                state.undo.end(state.document)
                beforeImage = nil
                refresh()
                return
            }
            if movingSelection {
                movingSelection = false
                moveRegion(with: event, finished: true)
                return
            }
            if let draft, draft.tool == .erase, beforeDrag == nil {
                erase(draft)
                self.draft = nil
                return
            }
            var edit = state.document.edit
            if let draft, beforeDrag == nil, let highlights = state.snappedHighlights(draft) {
                if highlights.isEmpty {
                    state.notice = String(localized: "Drag across a recognized text line.")
                } else if edit.annotations.count + highlights.count > 1000 {
                    state.notice = String(
                        localized: "Select fewer text lines to keep within the annotation limit.")
                } else {
                    edit.annotations += highlights
                    state.selected = nil
                    state.notice = nil
                }
            } else if let draft, draft.isValid, draft.hasDrawableExtent {
                if let index = edit.annotations.firstIndex(where: { $0.id == draft.id }) {
                    edit.annotations[index] = draft
                } else {
                    edit.annotations.append(draft)
                }
                state.selected = draft.id
                if draft.tool == .number, beforeDrag == nil {
                    state.nextNumber = (draft.numberFormat?.value ?? state.nextNumber) + 1
                }
                if draft.tool == .emoji { state.emojiSize = draft.fontSize ?? 64 }
            }
            if let crop = crop.flatMap({ CaptureGeometry.integralCrop($0, in: state.document.bounds) }) {
                edit.crop = crop
                state.fit()
            }
            state.commit(edit)
            draft = nil; beforeDrag = nil; crop = nil; movingControl = false; movingEndpoint = nil
            refresh()
        }

        private func erase(_ annotation: CaptureAnnotation) {
            guard CaptureGeometry.valid(annotation.bounds) else { return }
            let snapshot = state.document, source = state.source
            state.busy = true
            sampling?.cancel()
            sampling = Task { [weak self] in
                defer { self?.state.busy = false; self?.needsDisplay = true }
                do {
                    let color = try await CaptureWork.run {
                        try CaptureEraseService.color(
                            document: snapshot, directory: source.directory, around: annotation.bounds)
                    }
                    try Task.checkCancellation()
                    guard let self, self.state.document.revision == snapshot.revision else { return }
                    var replacement = annotation, edit = snapshot.edit
                    replacement.color = color
                    edit.annotations.append(replacement)
                    self.state.commit(edit)
                    self.state.selected = replacement.id
                    self.state.notice = nil
                    self.refresh()
                } catch is CancellationError { return } catch {
                    self?.state.notice = Bundle.main.localizedString(
                        forKey: error.localizedDescription, value: nil, table: nil)
                }
            }
        }

        private func moveRegion(with event: NSEvent, finished: Bool) {
            let point = convert(event.locationInWindow, from: nil)
            moveSelection?(
                CGSize(width: point.x - selectionAnchor.x, height: selectionAnchor.y - point.y), finished)
        }

        private func startText(at point: CGPoint) {
            let existing = editingAnnotation
            let rect = CGRect(
                x: (point.x - state.document.outputBounds.minX) * zoom,
                y: (point.y - state.document.outputBounds.minY) * zoom,
                width: min(
                    existing.map { $0.drawingBounds.width * zoom } ?? Theme.Size.captureTextEditor.width,
                    (state.document.outputBounds.maxX - point.x) * zoom),
                height: min(
                    existing.map { $0.drawingBounds.height * zoom } ?? Theme.Size.captureTextEditor.height,
                    (state.document.outputBounds.maxY - point.y) * zoom))
            guard rect.width >= 4, rect.height >= 4 else { return }
            let editor = CaptureTextEditor(frame: rect)
            editor.load(
                existing?.text ?? "",
                format: existing?.effectiveTextFormat ?? CaptureTextFormat(base: state.currentTextStyle),
                scale: zoom)
            let ink = existing?.rgba ?? state.color?.rgba ?? state.ink.rgba
            let color = NSColor(srgbRed: ink[0], green: ink[1], blue: ink[2], alpha: ink[3])
            editor.insertionPointColor = color
            editor.drawsBackground = false
            editor.textContainerInset = .zero
            editor.textContainer?.lineFragmentPadding = 0
            editor.onFinish = { [weak self] in self?.finishText() }
            editor.onStyle = { [weak state] style in state?.adoptTextStyle(style) }
            state.changeActiveText = { [weak editor] change in
                guard let editor else { return false }
                editor.apply(change)
                return true
            }
            addSubview(editor)
            textEditor = editor
            window?.makeFirstResponder(editor)
            needsDisplay = true
        }

        private func finishText() {
            guard let editor = textEditor else { return }
            if editor.hasMarkedText() { editor.unmarkText() }
            guard let (text, format) = editor.captured() else {
                state.notice = String(localized: "Use fewer text styles before finishing this annotation.")
                return
            }
            var edit = state.document.edit
            if let existing = editingAnnotation { edit.annotations.removeAll { $0.id == existing.id } }
            if !text.isEmpty {
                var annotation =
                    editingAnnotation
                    ?? CaptureAnnotation(
                        id: UUID(), tool: .text, points: [], ink: state.ink, width: state.strokeWidth,
                        rotation: state.rotation, font: state.font, fontSize: state.fontSize,
                        color: state.color)
                annotation.points = [
                    anchor,
                    CGPoint(
                        x: anchor.x + editor.frame.width / zoom,
                        y: anchor.y + editor.frame.height / zoom)
                ]
                annotation.text = text
                annotation.textFormat = format
                edit.annotations.append(annotation)
                state.selected = annotation.id
            }
            state.commit(edit)
            editor.undoManager?.removeAllActions()
            editor.removeFromSuperview()
            textEditor = nil
            state.changeActiveText = nil
            editingAnnotation = nil
            window?.makeFirstResponder(self)
        }

        override func keyDown(with event: NSEvent) {
            if event.keyCode == 53, state.pickingColor { state.cancelPickingColor(); return }
            if event.keyCode == 51 { state.deleteSelection(); return }
            if event.keyCode == 53, state.selected != nil { state.selected = nil; return }
            if let tool = CaptureAnnotation.Tool.shortcut(event.charactersIgnoringModifiers),
                event.modifierFlags.isDisjoint(with: [.command, .control, .option])
            {
                state.selectTool(tool)
                return
            }
            super.keyDown(with: event)
        }

        override func magnify(with event: NSEvent) {
            guard fixedScale == nil else { return }
            state.setZoom(zoom * (1 + event.magnification))
            refresh()
        }
    }

}
