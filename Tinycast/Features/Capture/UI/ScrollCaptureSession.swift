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
    /// The picture behind the last strip written, against which the next seam is placed.
    @ObservationIgnored private var committedImage: CGImage?
    @ObservationIgnored private let frames = ScrollFrameStream()
    /// The newest frame taken, shown again to the tracker once the display stops redrawing.
    @ObservationIgnored private var lastFrame: ScrollFrameStream.Frame?
    @ObservationIgnored private var lastArrival: ContinuousClock.Instant?
    @ObservationIgnored private var lastBatch: ContinuousClock.Instant?
    @ObservationIgnored private var batches = 0
    private var lastAutomaticScroll = ContinuousClock.now
    private var stopped = false
    private var generation = 0
    @ObservationIgnored private var scrollMonitors: [Any] = []
    /// The overlap is gone; the reader may scroll back to it, or go on and leave a gap.
    private(set) var lost = false
    /// Turned to scroll back from where it began, so the result's newest lines are its first.
    private(set) var growsAtStart = false
    /// As long as a capture can be: nothing more is added, and finishing keeps it.
    private(set) var full = false
    @ObservationIgnored private var bridgeRequested = false
    @ObservationIgnored private var latest: (frame: ScrollStitchPolicy.Frame, image: CGImage)?
    private(set) var diagnostics: ScrollDiagnosticsRecorder?
    private var diagnosticFrames = 0
    /// Trace lines go in order behind matching, so recording never slows the capture it watches.
    @ObservationIgnored private var diagnosticNotes: Task<Void, Never>?
    /// Frames being written side by side; past the limit a frame is skipped and its trace line says so.
    @ObservationIgnored private var diagnosticBacklog = 0
    private static let diagnosticBacklogLimit = 8
    /// Strips are written in order behind matching too: a write waited for let a fast scroll outrun it.
    @ObservationIgnored private var writes: Task<Void, Never>?
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
                do { try await self.step() } catch is CancellationError { return } catch {
                    self.pause(Bundle.main.localizedString(forKey: error.localizedDescription, value: nil, table: nil))
                }
            }
        }
    }

    /// A pointer's line in the region's frames, or nil while it is outside the region.
    nonisolated static func line(
        of location: CGPoint?, display: CGRect, region: CGRect, scale: CGFloat, axis: CaptureDocument.Axis
    ) -> Int? {
        guard let location else { return nil }
        let x = location.x - display.minX - region.minX, y = location.y - display.minY - region.minY
        guard (0..<region.width).contains(x), (0..<region.height).contains(y) else { return nil }
        return Int((axis == .vertical ? y : x) * scale)
    }

    /// Opt-in for one session only: the frames are screen contents, kept until the reader deletes them.
    func recordDiagnostics(in root: URL) throws {
        guard diagnostics == nil else { return }
        diagnostics = try ScrollDiagnosticsRecorder.create(in: root, date: Date())
    }

    func stop() async {
        cancel()
        await task?.value
        // The newest frame that lined up is content the reader scrolled to, so finishing keeps it.
        if let strip = tracker.flush() { enqueue(strip) }
        await writes?.value
        await diagnosticNotes?.value
        while diagnosticBacklog > 0 { try? await Task.sleep(for: .milliseconds(10)) }
        if let diagnostics { NSWorkspace.shared.activateFileViewerSelecting([diagnostics.directory]) }
        Self.logger.notice("""
            Scroll stopped: pieces=\(self.document.pieces.count), \
            width=\(self.document.size.width), height=\(self.document.size.height)
            """)
        task = nil
        tracker = ScrollTracker()
        preview = nil
    }

    func cancel() {
        stopped = true
        automatic = false
        task?.cancel()
        frames.stop()
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
        guard Self.line(
            of: CGEvent(source: nil)?.location, display: target.display.frame, region: region, scale: target.scale,
            axis: axis) != nil
        else { return }
        // A wheel's notches scroll by however many lines the app chooses, so they tell nothing exact.
        let delta = event.hasPreciseScrollingDeltas
            ? (axis == .vertical ? event.scrollingDeltaY : event.scrollingDeltaX) * target.scale : nil
        frames.travel { travel in delta.flatMap { delta in travel.map { $0 - delta } } }
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
        // Resuming a full capture would match on past lines that can never be written: a silent gap.
        guard !full else { onPauseChange?(true); return }
        generation += 1
        paused = false
        notice = String(localized: "Scroll inside the selected region")
        onPauseChange?(false)
    }

    /// Taken up by the sampling loop, so going on never races a sample already in flight.
    func requestBridge() {
        guard lost else { return }
        bridgeRequested = true
    }

    private func bridge() {
        bridgeRequested = false
        var bridged = tracker
        guard let latest, let strip = bridged.bridge(latest.frame, payload: latest.image) else { return }
        tracker = bridged
        lost = false
        enqueue(strip)
        Self.logger.notice("Scroll bridged a gap")
        notice = String(localized: "Went on past a gap: what was scrolled past is missing there")
        setHint(notice)
    }

    /// One pass: whatever the display redrew since the last, matched as one batch.
    private func step() async throws {
        if automatic, !paused, ContinuousClock.now - lastAutomaticScroll >= .milliseconds(300) { scrollTarget() }
        guard !paused else {
            _ = frames.take()
            try await Task.sleep(for: .milliseconds(100))
            return
        }
        if !frames.running {
            let size = try CapturePixelSize(
                width: Int((region.width * target.scale).rounded()), height: Int((region.height * target.scale).rounded()))
            try await frames.start(filter: target.filter, region: region, size: size)
        }
        if let failure = frames.failure {
            frames.stop()
            throw Failure.stream(failure)
        }
        var batch = frames.take()
        if let newest = batch.last {
            lastArrival = newest.arrived
        } else {
            // Nothing redrawn: the same picture once more, so the tracker sees the rest and writes what waits.
            guard let last = lastFrame, !tracker.resting, let arrival = lastArrival,
                ContinuousClock.now - arrival >= .milliseconds(100)
            else {
                try await Task.sleep(for: .milliseconds(tracker.resting ? 50 : 4))
                return
            }
            batch = [last]
            lastArrival = .now
        }
        lastFrame = batch.last
        guard validateTarget() else { return }
        if bridgeRequested { bridge() }
        try await match(batch)
    }

    private func match(_ batch: [ScrollFrameStream.Frame]) async throws {
        let generation = generation
        let started = ContinuousClock.now
        let interval = lastBatch.map { started - $0 }
        lastBatch = started
        let axis = axis, tracker = tracker, display = target.display.frame, region = region, scale = target.scale
        let (observed, results, sampled) = try await CaptureWork.run {
            var tracker = tracker
            let sampled = try batch.map { shot in
                var frame = try ScrollFrameReader.sample(shot.image, axis: axis)
                frame.pointer = Self.line(of: shot.pointer, display: display, region: region, scale: scale, axis: axis)
                frame.travel = shot.travel.map { Int($0.rounded()) }
                return frame
            }
            let results = tracker.observe(
                batch: zip(sampled, batch).map { (frame: $0, payload: $1.image) }, match: ScrollStitchPolicy.match)
            return (tracker, results, sampled)
        }
        try Task.checkCancellation()
        let newest = batch[batch.count - 1], travel = sampled[sampled.count - 1].travel
        latest = (sampled[sampled.count - 1], newest.image)
        batches += 1
        let timing = [
            interval.map { "interval \(Self.milliseconds($0))" }, "frames \(batch.count)",
            "latency \(Self.milliseconds(started - newest.arrived))", "match \(Self.milliseconds(.now - started))"
        ].compactMap { $0 }.joined(separator: " ")
        for (index, steps) in results {
            record(batch[index].image, frame: sampled[index], steps: steps, timing: index == batch.count - 1 ? timing : nil)
        }
        guard !paused, generation == self.generation else { return }
        self.tracker = observed
        for step in results.flatMap(\.steps) {
            switch step {
            case .commit(let strip):
                lost = false
                enqueue(strip)
            case .backward:
                notice = observed.reversed
                    ? String(localized: "Keep scrolling back to add more content")
                    : String(localized: "Scroll forward to add more content")
                setHint(notice)
            case .reversing:
                growsAtStart = true
                notice = String(localized: "Scrolling back: new content is added at the start")
                setHint(notice)
            case .lost:
                lost = true
                Self.logger.notice("Scroll alignment lost: pieces=\(self.document.pieces.count)")
                let now = observed.reversed ? travel.map { -$0 } : travel
                let gone = observed.accepted?.travel.flatMap { from in now.map { abs($0 - from) } }
                notice = gone.map { $0 * 2 >= (axis == .vertical ? newest.image.height : newest.image.width) } == true
                    ? String(localized: "Scrolled too fast to line up. Scroll back a little, then slower")
                    : String(localized: "Lost the overlap. Scroll back a little to continue")
                setHint(notice, lasting: true)
            case .found:
                lost = false
                notice = String(localized: "Scroll inside the selected region")
                setHint(nil)
            }
        }
    }

    private func diagnosticWritten() {
        diagnosticBacklog -= 1
    }

    private static func milliseconds(_ duration: Duration) -> Int {
        Int(duration.components.seconds * 1_000 + duration.components.attoseconds / 1_000_000_000_000_000)
    }

    private static func describe(_ step: ScrollTracker<CGImage>.Step) -> String {
        switch step {
        case .commit(let strip): "commit \(strip.offset.map(String.init) ?? "whole") trailing \(strip.trailing)"
        case .backward: "backward"
        case .lost: "lost"
        case .found: "found"
        case .reversing: "reversing"
        }
    }

    /// Every frame the tracker saw, named with its batch, so a replay goes through it the same way.
    private func record(
        _ image: CGImage, frame: ScrollStitchPolicy.Frame, steps: [ScrollTracker<CGImage>.Step], timing: String?
    ) {
        guard let diagnostics, diagnosticFrames < ScrollDiagnosticsRecorder.frameLimit else { return }
        diagnosticFrames += 1
        let name = ScrollDiagnosticsRecorder.frameName(
            index: diagnosticFrames, batch: batches, pointer: frame.pointer, travel: frame.travel)
        let skipped = diagnosticBacklog >= Self.diagnosticBacklogLimit
        let verdict = (steps.map(Self.describe) + [timing, skipped ? "skipped" : nil].compactMap { $0 })
            .joined(separator: " ")
        let previous = diagnosticNotes
        diagnosticNotes = Task.detached {
            await previous?.value
            try? diagnostics.note(name, verdict: verdict)
        }
        guard !skipped else { return }
        diagnosticBacklog += 1
        Task.detached(priority: .utility) { [weak self] in
            try? diagnostics.write(image, named: name)
            await self?.diagnosticWritten()
        }
    }

    /// Decided strips are written whatever follows: the tracker has already moved its end past them.
    private func enqueue(_ strip: ScrollTracker<CGImage>.Strip) {
        let previous = writes
        writes = Task { [weak self] in
            await previous?.value
            guard let self else { return }
            let started = ContinuousClock.now
            do {
                try await self.write(strip)
                CapturePerformance.completed("scroll-preview-ready", since: started)
            } catch {
                self.pause(Bundle.main.localizedString(forKey: error.localizedDescription, value: nil, table: nil))
            }
        }
    }

    private func write(_ strip: ScrollTracker<CGImage>.Strip) async throws {
        guard !full else { return }
        let image = strip.payload, axis = axis, before = committedImage
        let raster = UUID().uuidString
        let extra = try await CaptureWork.run {
            guard let before, let offset = strip.offset else { return 0 }
            return ScrollFrameReader.seam(
                previous: before, current: image, shift: offset, retaken: strip.trailing, axis: axis,
                atStart: strip.reversed)
        }
        let plan = try CaptureScrollAppend.plan(
            document: document, frame: try CapturePixelSize(width: image.width, height: image.height),
            raster: raster, offset: strip.offset, trailing: strip.trailing + extra, atStart: strip.reversed)
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
        document = plan.document
        preview = nextPreview
        committedImage = image
        if plan.full {
            full = true
            frames.stop()
            let longest = CaptureScrollAppend.longest(
                frame: try CapturePixelSize(width: image.width, height: image.height), axis: axis)
            pause(String(localized: "Reached the longest a capture can be, \(longest) pixels. Finish to keep it"))
        }
        Self.logger.info("""
            Scroll appended: pieces=\(self.document.pieces.count), \
            width=\(self.document.size.width), height=\(self.document.size.height)
            """)
        onPauseChange?(false)
    }

    enum Failure: LocalizedError {
        case stream(String)
        var errorDescription: String? {
            switch self { case .stream(let reason): reason }
        }
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
