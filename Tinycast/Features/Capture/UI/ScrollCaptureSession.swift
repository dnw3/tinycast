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
    var automatic = false
    var notice = String(localized: "Scroll inside the selected region")
    var preview: CGImage?
    private var task: Task<Void, Never>?
    private var accepted: ScrollStitchPolicy.Frame?
    private var candidate: ScrollStitchPolicy.Frame?
    private var stopped = false
    private var generation = 0
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
        task = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled, !self.stopped {
                do {
                    if !self.paused { try await self.sample() }
                    try await Task.sleep(for: .milliseconds(300))
                } catch is CancellationError { return } catch { self.pause(Bundle.main.localizedString(forKey: error.localizedDescription, value: nil, table: nil)) }
            }
        }
    }

    func stop() async {
        cancel()
        await task?.value
        Self.logger.notice("""
            Scroll stopped: pieces=\(self.document.pieces.count), \
            width=\(self.document.size.width), height=\(self.document.size.height)
            """)
        task = nil
        accepted = nil
        candidate = nil
        preview = nil
    }

    func cancel() {
        stopped = true
        automatic = false
        task?.cancel()
    }

    func pause(_ reason: String = String(localized: "Paused — captured content is kept")) {
        generation += 1
        paused = true
        automatic = false
        candidate = nil
        notice = reason
        onPauseChange?(true)
    }

    func resume() {
        generation += 1
        paused = false
        candidate = nil
        notice = String(localized: "Scroll inside the selected region")
        onPauseChange?(false)
    }

    private func sample() async throws {
        let generation = generation
        guard validateTarget() else { return }
        let temporary = directory.appendingPathComponent("candidate-\(UUID())")
        defer { try? FileManager.default.removeItem(at: temporary) }
        let image = try await CaptureScreenService.image(target: target, rect: region, cursor: false)
        let axis = axis
        let frame = try await CaptureWork.run {
            _ = try CaptureImageSource.store(image, at: temporary)
            return try ScrollFrameReader.sample(directory: temporary, axis: axis)
        }
        try Task.checkCancellation()
        guard !paused, generation == self.generation else { return }
        guard let candidate, ScrollStitchPolicy.stable(candidate, frame) else {
            self.candidate = frame
            return
        }
        let stable = ContinuousClock.now
        if let accepted {
            let decision = try await CaptureWork.run {
                ScrollStitchPolicy.match(previous: accepted, current: frame)
            }
            guard !paused, generation == self.generation else { return }
            switch decision {
            case .duplicate: notice = String(localized: "No new content found")
            case .reverse: notice = String(localized: "Scroll forward to add more content")
            case .uncertain:
                Self.logger.notice("Scroll alignment uncertain: pieces=\(self.document.pieces.count)")
                pause(String(localized: "Could not align. Scroll back slightly, or select a region without fixed sidebars or scrollbars"))
            case .append(let offset, _, let trailing):
                guard try await append(temporary, offset: offset, trailing: trailing) else { return }
                self.accepted = frame
                CapturePerformance.completed("scroll-preview-ready", since: stable)
            }
        } else {
            guard try await append(temporary, offset: nil, trailing: 0) else { return }
            accepted = frame
            CapturePerformance.completed("scroll-preview-ready", since: stable)
        }
        self.candidate = frame
        if automatic, !paused { scrollTarget() }
    }

    private func append(_ source: URL, offset: Int?, trailing: Int) async throws -> Bool {
        let generation = generation
        let metadata = try CaptureRasterStore.read(at: source)
        let raster = UUID().uuidString
        let plan = try CaptureScrollAppend.plan(
            document: document, frame: metadata.size, raster: raster, offset: offset, trailing: trailing)
        let destination = directory.appendingPathComponent(raster)
        let previous = preview, previousSize = document.size, directory = directory
        let nextPreview = try await CaptureWork.run {
            let available =
                try directory.resourceValues(forKeys: [.volumeAvailableCapacityKey]).volumeAvailableCapacity
                ?? 0
            guard available > Int(plan.source.width * plan.source.height * 4) + 32_000_000 else {
                throw CocoaError(.fileWriteOutOfSpace)
            }
            try ScrollFrameReader.strip(from: source, rect: plan.source, to: destination)
            return try CaptureRenderer.scrollPreview(
                previous: previous, previousSize: previousSize, document: plan.document, directory: directory)
        }
        try Task.checkCancellation()
        guard !paused, generation == self.generation else {
            try? FileManager.default.removeItem(at: destination)
            return false
        }
        document = plan.document
        preview = nextPreview
        Self.logger.info("""
            Scroll appended: pieces=\(self.document.pieces.count), \
            width=\(self.document.size.width), height=\(self.document.size.height)
            """)
        notice = String(localized: "Scroll inside the selected region")
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
            excludedPIDs: target.excludedPIDs)
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
        candidate = nil
    }
}
