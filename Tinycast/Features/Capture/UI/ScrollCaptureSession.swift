import AppKit
import Observation
import OSLog

@MainActor
@Observable
final class ScrollCaptureSession {
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "Capture")
    var document: CaptureDocument
    let source: CaptureSource
    var directory: URL { source.directory }
    let target: CaptureScreenService.Target
    let region: CGRect
    let targetWindowID: CGWindowID
    let targetPID: pid_t
    let targetFrame: CGRect
    let axis: CaptureDocument.Axis
    private(set) var paused = false
    @ObservationIgnored var onPauseChange: ((Bool) -> Void)?
    @ObservationIgnored var onHintChange: (() -> Void)?
    private(set) var hint: String?
    private var hintExpiry: Task<Void, Never>?
    var automatic = false
    var notice = String(localized: "Scroll inside the selected region")
    var preview: CGImage?
    private var task: Task<Void, Never>?
    private var tracker = ScrollTracker<CGImage>()
    /// The frame behind the last strip on disk, where matching starts over if a write is dropped.
    private var committed: ScrollStitchPolicy.Frame?
    /// Samples in a row at rest; the loop slows down once the content has settled.
    private var restingSamples = 0
    private var lastAutomaticScroll = ContinuousClock.now
    private var stopped = false
    private var generation = 0
    /// Pixels the scroll events over the region have moved the content by, while every one was precise.
    private var travel: Double? = 0
    @ObservationIgnored private var scrollMonitors: [Any] = []
    private(set) var diagnostics: ScrollDiagnosticsRecorder?
    private var diagnosticFrames = 0
    /// Frames are written in order behind sampling, so recording never slows the capture it watches.
    private var diagnosticWrites: Task<Void, Never>?
    private let speed: Int

    init(
        document: CaptureDocument, source: CaptureSource, target: CaptureScreenService.Target,
        region: CGRect, windowID: CGWindowID, pid: pid_t, windowFrame: CGRect,
        axis: CaptureDocument.Axis, speed: Int
    ) {
        self.document = document
        self.source = source
        self.target = target
        self.region = region
        targetWindowID = windowID
        targetPID = pid
        targetFrame = windowFrame
        self.axis = axis
        self.speed = speed
    }

    func start() {
        watchScrolling()
        task = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled, !self.stopped {
                do {
                    if !self.paused { try await self.sample() }
                    try await Task.sleep(for: self.cadence)
                } catch is CancellationError { return } catch { self.pause(Bundle.main.localizedString(forKey: error.localizedDescription, value: nil, table: nil)) }
            }
        }
    }

    /// Quick while anything moves, so a flick never outruns the overlap; slower once it rests.
    private var cadence: Duration { .milliseconds(restingSamples > 10 ? 150 : 10) }

    /// The pointer's line in a frame while it is over the region, where hovering changes content.
    private var pointerLine: Int? {
        guard let location = CGEvent(source: nil)?.location else { return nil }
        let x = location.x - target.display.frame.minX - region.minX
        let y = location.y - target.display.frame.minY - region.minY
        guard (0..<region.width).contains(x), (0..<region.height).contains(y) else { return nil }
        return Int((axis == .vertical ? y : x) * target.scale)
    }

    /// Opt-in for one session only: the frames are screen contents, kept until the reader deletes them.
    func recordDiagnostics(in root: URL) throws {
        guard diagnostics == nil else { return }
        diagnostics = try ScrollDiagnosticsRecorder.create(in: root, date: Date())
    }

    func stop() async {
        cancel()
        await task?.value
        await diagnosticWrites?.value
        if let diagnostics { NSWorkspace.shared.activateFileViewerSelecting([diagnostics.directory]) }
        // The newest frame that lined up is content the reader scrolled to, so finishing keeps it.
        if let strip = tracker.flush() { _ = try? await write(strip, generation: nil) }
        Self.logger.notice("""
            Scroll stopped: pieces=\(self.document.pieces.count), \
            width=\(self.document.size.width), height=\(self.document.size.height)
            """)
        task = nil
        tracker = ScrollTracker()
        committed = nil
        preview = nil
    }

    func cancel() {
        stopped = true
        automatic = false
        task?.cancel()
        scrollMonitors.forEach(NSEvent.removeMonitor)
        scrollMonitors = []
        setHint(nil)
    }

    /// The scroll events say how far the content went, which matching takes as a second witness.
    private func watchScrolling() {
        guard scrollMonitors.isEmpty else { return }
        let otherApps = NSEvent.addGlobalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            self?.scrolled(event)
        }
        // The global monitor never sees this app's own windows, and AI Chat is one of them.
        let thisApp = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            self?.scrolled(event)
            return event
        }
        scrollMonitors = [otherApps, thisApp].compactMap { $0 }
    }

    private func scrolled(_ event: NSEvent) {
        guard let travel, pointerLine != nil else { return }
        // A wheel's notches scroll by however many lines the app chooses, so they tell nothing exact.
        guard event.hasPreciseScrollingDeltas else { self.travel = nil; return }
        let delta = axis == .vertical ? event.scrollingDeltaY : event.scrollingDeltaX
        self.travel = travel - delta * target.scale
    }

    /// A lasting hint stays until whatever it describes is over, rather than for three seconds.
    private func setHint(_ text: String?, lasting: Bool = false) {
        hintExpiry?.cancel()
        hintExpiry = nil
        if hint != text {
            hint = text
            onHintChange?()
        }
        guard text != nil, !lasting else { return }
        hintExpiry = Task { [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            self?.setHint(nil)
        }
    }

    func pause(_ reason: String = String(localized: "Paused — captured content is kept")) {
        generation += 1
        paused = true
        automatic = false
        notice = reason
        setHint(nil)
        onPauseChange?(true)
    }

    func resume() {
        generation += 1
        paused = false
        notice = String(localized: "Scroll inside the selected region")
        onPauseChange?(false)
    }

    private func sample() async throws {
        let generation = generation
        guard validateTarget() else { return }
        let image = try await CaptureScreenService.image(target: target, rect: region, cursor: false)
        let axis = axis, tracker = tracker, pointer = pointerLine, travel = travel.map { Int($0.rounded()) }
        let (observed, steps) = try await CaptureWork.run {
            var tracker = tracker
            var frame = try ScrollFrameReader.sample(image, axis: axis)
            frame.pointer = pointer
            frame.travel = travel
            let steps = tracker.observe(frame, payload: image, match: ScrollStitchPolicy.match)
            return (tracker, steps)
        }
        try Task.checkCancellation()
        record(image, pointer: pointer, travel: travel, resting: observed.resting, steps: steps)
        guard !paused, generation == self.generation else { return }
        self.tracker = observed
        restingSamples = observed.resting ? restingSamples + 1 : 0
        for step in steps {
            switch step {
            case .commit(let strip):
                let started = ContinuousClock.now
                guard try await write(strip, generation: generation) else {
                    self.tracker.restart(from: committed)
                    return
                }
                CapturePerformance.completed("scroll-preview-ready", since: started)
            case .backward:
                notice = observed.reversed
                    ? String(localized: "Keep scrolling back to add more content")
                    : String(localized: "Scroll forward to add more content")
                setHint(notice)
            case .reversing:
                notice = String(localized: "Scrolling back: new content is added at the start")
                setHint(notice)
            case .lost:
                Self.logger.notice("Scroll alignment lost: pieces=\(self.document.pieces.count)")
                let now = observed.reversed ? travel.map { -$0 } : travel
                let gone = observed.accepted?.travel.flatMap { from in now.map { abs($0 - from) } }
                notice = gone.map { $0 * 2 >= (axis == .vertical ? image.height : image.width) } == true
                    ? String(localized: "Scrolled too fast to line up. Scroll back a little, then slower")
                    : String(localized: "Lost the overlap. Scroll back a little to continue")
                setHint(notice, lasting: true)
            case .found:
                notice = String(localized: "Scroll inside the selected region")
                setHint(nil)
            }
        }
        if automatic, !paused, ContinuousClock.now - lastAutomaticScroll >= .milliseconds(300) {
            scrollTarget()
        }
    }

    private func record(
        _ image: CGImage, pointer: Int?, travel: Int?, resting: Bool, steps: [ScrollTracker<CGImage>.Step]
    ) {
        guard let diagnostics, diagnosticFrames < ScrollDiagnosticsRecorder.frameLimit else { return }
        diagnosticFrames += 1
        let index = diagnosticFrames, previous = diagnosticWrites
        let verdict = ([resting ? "rest" : "moving"] + steps.map { step in
            switch step {
            case .commit(let strip): "commit \(strip.offset.map(String.init) ?? "whole") trailing \(strip.trailing)"
            case .backward: "backward"
            case .lost: "lost"
            case .found: "found"
            case .reversing: "reversing"
            }
        }).joined(separator: " ")
        diagnosticWrites = Task.detached {
            await previous?.value
            try? diagnostics.record(image, index: index, pointer: pointer, travel: travel, verdict: verdict)
        }
    }

    /// A nil generation is the finishing flush, which no pause can overtake.
    private func write(_ strip: ScrollTracker<CGImage>.Strip, generation: Int?) async throws -> Bool {
        let image = strip.payload
        let raster = UUID().uuidString
        let plan = try CaptureScrollAppend.plan(
            document: document, frame: try CapturePixelSize(width: image.width, height: image.height),
            raster: raster, offset: strip.offset, trailing: strip.trailing, atStart: strip.reversed)
        let destination = directory.appendingPathComponent(raster)
        let previous = preview, previousSize = document.size, directory = directory
        let nextPreview = try await CaptureWork.run {
            let available =
                try directory.resourceValues(forKeys: [.volumeAvailableCapacityKey]).volumeAvailableCapacity
                ?? 0
            guard available > Int(plan.source.width * plan.source.height * 4) + 32_000_000 else {
                throw CocoaError(.fileWriteOutOfSpace)
            }
            try ScrollFrameReader.strip(image, rect: plan.source, to: destination)
            return try CaptureRenderer.scrollPreview(
                previous: previous, previousSize: previousSize, document: plan.document, directory: directory,
                atStart: strip.reversed)
        }
        if let generation, paused || generation != self.generation {
            try? FileManager.default.removeItem(at: destination)
            return false
        }
        document = plan.document
        preview = nextPreview
        committed = strip.frame
        Self.logger.info("""
            Scroll appended: pieces=\(self.document.pieces.count), \
            width=\(self.document.size.width), height=\(self.document.size.height)
            """)
        onPauseChange?(false)
        return true
    }

    private func validateTarget() -> Bool {
        guard !stopped else { return false }
        guard CGPreflightScreenCaptureAccess() else {
            pause(String(localized: "Screen Recording permission changed. Finish this capture and grant permission again"))
            return false
        }
        guard NSScreen.screens.contains(where: { $0.frame == target.screenFrame }) else {
            pause(String(localized: "The display changed. Select a region again"))
            return false
        }
        let quartzRegion = CGRect(
            x: target.display.frame.minX + region.minX, y: target.display.frame.minY + region.minY,
            width: region.width, height: region.height)
        let assessment = CaptureScreenService.assessTarget(
            windowID: targetWindowID, pid: targetPID, frame: targetFrame, region: quartzRegion,
            excludedPIDs: target.excludedPIDs, includedWindowIDs: target.includedWindowIDs)
        guard assessment.status == .visible else { pause(assessment.status.message); return false }
        return true
    }

    private func scrollTarget() {
        guard validateTarget() else { return }
        guard Permissions.isAccessibilityTrusted() else {
            pause(String(localized: "Automatic scrolling needs Accessibility permission")); return
        }
        let amount = Int32(-max(30, min(120, 60 + speed * 30)))
        guard
            let event = CGEvent(
                scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2,
                wheel1: axis == .vertical ? amount : 0,
                wheel2: axis == .horizontal ? amount : 0, wheel3: 0)
        else { return }
        event.location = CGPoint(
            x: target.display.frame.minX + region.midX, y: target.display.frame.minY + region.midY)
        event.post(tap: .cgSessionEventTap)
        lastAutomaticScroll = .now
    }
}
