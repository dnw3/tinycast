import AVFoundation
import CoreImage
import CoreVideo
import ImageIO
import UniformTypeIdentifiers

@main
struct CaptureVideoTests {
    static func main() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("capture-video-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }
        let red = root.appendingPathComponent("red.mp4"), green = root.appendingPathComponent("green.mp4")
        try await fixture(red, red: true)
        try await fixture(green, red: false)
        let joined = root.appendingPathComponent("joined.mp4")
        try await CaptureVideoService.join([red, green], to: joined)
        let info = try await CaptureVideoService.inspect(joined)
        precondition(info.size.width == 128 && info.size.height == 64 && info.audioTracks == 0)
        precondition(abs(info.duration - 2) < 0.11, "pause time must not enter the joined timeline")
        try await expectColor(joined, at: 0.5, red: true)
        try await expectColor(joined, at: 1.5, red: false)
        let output = root.appendingPathComponent("trimmed.mp4")
        let edit = CaptureVideoEdit(start: 0.5, end: 1.5, speed: 2, volume: 0)
        try await CaptureVideoService.render(joined, edit: edit, to: output)
        let shortened = try await CaptureVideoService.inspect(output)
        precondition(abs(shortened.duration - 0.5) < 0.11)
        try await expectColor(output, at: 0.05, red: true)
        try await expectColor(output, at: 0.4, red: false)
        precondition((try? CaptureVideoEdit(start: .nan, end: 1).validated(duration: 2)) == nil)
        precondition((try? CaptureVideoEdit(start: 1, end: 1).validated(duration: 2)) == nil)
        precondition((try? CaptureVideoEdit(end: 3).validated(duration: 2)) == nil)
        precondition((try? CaptureVideoEdit(end: 2, speed: 0).validated(duration: 2)) == nil)
        let options = CaptureRecordingOptions()
        precondition(!options.systemAudio && !options.microphone)
        let resized = try options.outputSize(CGSize(width: 5121, height: 2881))
        precondition(resized.width <= 3840 && resized.width.isMultiple(of: 2) && resized.height.isMultiple(of: 2))
        precondition((try? options.outputSize(CGSize(width: CGFloat.infinity, height: 10))) == nil)
        let cancelled = root.appendingPathComponent("cancelled.mp4")
        let task = Task { try await CaptureVideoService.join(Array(repeating: red, count: 100), to: cancelled) }
        task.cancel()
        do { try await task.value; preconditionFailure("cancelled video export succeeded") } catch is CancellationError {}
        precondition(!FileManager.default.fileExists(atPath: cancelled.path))
        precondition(FileManager.default.fileExists(atPath: red.path) && FileManager.default.fileExists(atPath: green.path))
        let repository = CaptureRepository(root: root.appendingPathComponent("captures"))
        let preview = try await CaptureVideoService.thumbnail(joined)
        try repository.commitVideo(joined, info: info, preview: preview)
        let entries = try repository.entries()
        precondition(entries.count == 1 && entries[0].videoDuration == info.duration && entries[0].filename == "video.mp4")
        let reopened = try repository.openFile(entries[0], id: UUID())
        let copied = try repository.transfer(entries[0], now: Date(), keeping: [])
        try FileManager.default.removeItem(at: repository.history)
        let restored = try await CaptureVideoService.inspect(reopened.directory.appendingPathComponent(entries[0].filename))
        precondition(restored.duration == info.duration, "history deletion must not invalidate an open recording")
        let copiedInfo = try await CaptureVideoService.inspect(copied)
        precondition(copiedInfo.duration == info.duration, "history deletion must not invalidate a copied recording")
        let gif = root.appendingPathComponent("clip.gif")
        let gifOptions = CaptureVideoExportOptions(format: .gif, maximumDimension: 320, framesPerSecond: 10)
        try await CaptureGIFService.render(joined, edit: edit, options: gifOptions, to: gif) { _ in }
        let imageSource = CGImageSourceCreateWithURL(gif as CFURL, nil)!
        precondition(CGImageSourceGetCount(imageSource) == 5)
        let first = CGImageSourceCreateImageAtIndex(imageSource, 0, nil)!
        let last = CGImageSourceCreateImageAtIndex(imageSource, 4, nil)!
        precondition(first.width == 128 && first.height == 64 && last.width == 128)
        precondition(color(first)[0] > 200 && color(last)[1] > 200)
        var gifDuration = 0.0
        for index in 0..<5 {
            guard let properties = CGImageSourceCopyPropertiesAtIndex(imageSource, index, nil) as? [String: Any],
                let values = properties[kCGImagePropertyGIFDictionary as String] as? [String: Any]
            else { preconditionFailure("GIF frame metadata is missing") }
            gifDuration += values[kCGImagePropertyGIFUnclampedDelayTime as String] as? Double ?? 0
        }
        precondition(abs(gifDuration - 0.5) < 0.001)
        let gifInfo = try CaptureGIFService.inspect(gif)
        precondition(gifInfo.frames == 5 && abs(gifInfo.duration - 0.5) < 0.001 && gifInfo.size.width == 128)
        var playback: [[UInt8]] = []
        for try await frame in CaptureGIFService.frames(gif) { playback.append(color(frame)) }
        precondition(playback.count == 5 && playback.first![0] > 200 && playback.last![1] > 200)
        try repository.commitGIF(gif)
        let gifEntry = try repository.entries()[0]
        precondition(gifEntry.videoDuration == nil && gifEntry.animationDuration == gifInfo.duration)
        precondition(gifEntry.filename == "animation.gif")
        let gifLease = try repository.openFile(gifEntry, id: UUID())
        let providedGIF = try await fileData(CaptureFileProvider.make(gifEntry, repository: repository), type: .gif)
        let expectedGIF = try Data(contentsOf: gif)
        precondition(providedGIF == expectedGIF, "drag providers must deliver every animation frame")
        let oldDate = Date().addingTimeInterval(-172_800)
        try FileManager.default.setAttributes([.modificationDate: oldDate],
            ofItemAtPath: copied.deletingLastPathComponent().path)
        let transfer = try repository.transfer(gifEntry, now: Date(), keeping: [copied])
        precondition(FileManager.default.fileExists(atPath: copied.path), "the current clipboard file must survive cleanup")
        let copiedGIF = try Data(contentsOf: transfer), originalGIF = try Data(contentsOf: gif)
        precondition(copiedGIF == originalGIF)
        _ = try repository.transfer(gifEntry, now: Date(), keeping: [transfer])
        precondition(!FileManager.default.fileExists(atPath: copied.path), "expired inactive transfers must be reclaimed")
        try FileManager.default.removeItem(at: repository.history)
        let reopenedGIF = try CaptureGIFService.inspect(gifLease.directory.appendingPathComponent(gifEntry.filename))
        precondition(reopenedGIF.frames == 5 && reopenedGIF.duration == gifInfo.duration)
        precondition(FileManager.default.fileExists(atPath: transfer.path))
        try await previewFailure(source: reopened, root: root)
        precondition((try? gifOptions.gifFrames(size: info.size, duration: 31)) == nil)
        try await CaptureRecordingFixture.run(video: joined, root: root)
        try await timeline(joined, root: root)
        try await effects(joined, root: root)
        try await quality(root: root)
        try await seeking(joined, root: root)
        print("Video segment continuity, decoded frames, trim/speed duration, bounds and cancellation passed")
    }

    static func fileData(_ provider: NSItemProvider, type: UTType) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            _ = provider.loadFileRepresentation(for: type) { url, _, error in
                if let error { continuation.resume(throwing: error); return }
                do {
                    guard let url else { throw CaptureVideoError.invalidMedia }
                    continuation.resume(returning: try Data(contentsOf: url))
                } catch { continuation.resume(throwing: error) }
            }
        }
    }

    @MainActor
    static func previewFailure(source: CaptureSource, root: URL) async throws {
        let state = CaptureVideoState(source: source, url: root.appendingPathComponent("missing.mp4"),
            info: .init(duration: 2, size: try .init(width: 128, height: 64), audioTracks: 0))
        await state.updatePreview()
        guard case .failed = state.preview else { preconditionFailure("failed previews must stop loading") }
        precondition(state.player.currentItem == nil && state.needsPreservation)
        let task = Task { await state.updatePreview() }
        task.cancel()
        await task.value
        precondition(state.player.currentItem == nil)
    }

    static func timeline(_ source: URL, root: URL) async throws {
        let original = CaptureVideoEdit(end: 2)
        let edit = CaptureVideoEdit(end: 2, speed: 2,
            cuts: [.init(start: 0.75, end: 1.25)], holds: [.init(position: 0.5, duration: 0.4)])
        _ = try edit.validated(duration: 2)
        precondition(abs(edit.duration - 1.15) < 0.0001)
        let timeline = CaptureVideoTimeline(edit)
        precondition(timeline.sourceTime(at: 0.5) == 0.5)
        precondition(abs(timeline.sourceTime(at: 0.9)! - 1.5) < 0.0001)
        precondition(timeline.sourceTime(at: edit.duration) == nil)
        let output = root.appendingPathComponent("cut-hold.mp4")
        try await CaptureVideoService.render(source, edit: edit, to: output)
        let info = try await CaptureVideoService.inspect(output)
        precondition(abs(info.duration - 1.15) < 0.04)
        try await expectColor(output, at: 0.1, red: true)
        try await expectColor(output, at: 0.5, red: true)
        try await expectColor(output, at: 1, red: false)
        let preview = try await CaptureVideoService.prepare(source, edit: edit)
        let generator = AVAssetImageGenerator(asset: preview.asset)
        generator.videoComposition = preview.video
        let held = try await generator.image(at: CaptureVideoService.time(0.5)).image
        precondition(color(held)[0] > 200, "preview must use the same hold as export")
        var invalid = edit
        invalid.cuts.append(.init(start: 0.7, end: 1.5))
        precondition((try? invalid.validated(duration: 2)) == nil)
        invalid = original
        invalid.cuts = [.init(start: 0, end: 2)]
        precondition((try? invalid.validated(duration: 2)) == nil)
        var history = CaptureVideoUndoHistory(), current = original
        history.begin(current)
        history.commit(CaptureVideoEdit(end: 1.8), to: &current)
        history.commit(edit, to: &current)
        history.end(current)
        history.undo(&current)
        precondition(current == original && !history.canUndo && history.canRedo)
        history.redo(&current)
        precondition(current == edit)
        history.undo(&current)
        history.commit(CaptureVideoEdit(end: 1.5), to: &current)
        precondition(!history.canRedo)
        let alternating = root.appendingPathComponent("alternating.mp4")
        try await fixture(alternating, red: true, alternating: true)
        let frozen = root.appendingPathComponent("frozen.mp4")
        try await CaptureVideoService.render(alternating,
            edit: CaptureVideoEdit(end: 1, holds: [.init(position: 0.55, duration: 1)]), to: frozen)
        try await expectColor(frozen, at: 0.7, red: false)
        try await expectColor(frozen, at: 1.4, red: false)
        let withAudio = root.appendingPathComponent("audio.mp4")
        try await addAudio(source, destination: withAudio)
        let audioOutput = root.appendingPathComponent("audio-edited.mp4")
        var audioEdit = edit
        audioEdit.volume = 0.5
        try await CaptureVideoService.render(withAudio, edit: audioEdit, to: audioOutput)
        let audioInfo = try await CaptureVideoService.inspect(audioOutput)
        precondition(audioInfo.audioTracks == 1 && abs(audioInfo.duration - 1.15) < 0.05)
        let file = try AVAudioFile(forReading: audioOutput)
        let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length))!
        try file.read(into: buffer)
        let samples = buffer.floatChannelData![0]
        func energy(_ start: Double, _ end: Double) -> Double {
            let range = Int(start * file.processingFormat.sampleRate)..<Int(end * file.processingFormat.sampleRate)
            return sqrt(range.reduce(0.0) { $0 + Double(samples[$1] * samples[$1]) } / Double(range.count))
        }
        precondition((0.12...0.22).contains(energy(0.08, 0.18)), "export must apply the selected volume")
        precondition(energy(0.35, 0.55) < 0.002, "freeze must insert silence instead of stretching a voice sample")
        let gif = root.appendingPathComponent("cut-hold.gif")
        try await CaptureGIFService.render(source, edit: edit,
            options: .init(format: .gif, maximumDimension: 320, framesPerSecond: 10), to: gif) { _ in }
        let images = CGImageSourceCreateWithURL(gif as CFURL, nil)!
        precondition(CGImageSourceGetCount(images) == 12)
        precondition(color(CGImageSourceCreateImageAtIndex(images, 5, nil)!)[0] > 200)
        precondition(color(CGImageSourceCreateImageAtIndex(images, 10, nil)!)[1] > 200)
        let sparse = root.appendingPathComponent("sparse.mp4")
        try await fixture(sparse, red: true, times: [0, 0.4, 1.4, 2.4, 3.4, 4.4, 5.4, 6.4], duration: 7)
        let sparseOutput = root.appendingPathComponent("sparse-edited.mp4")
        try await CaptureVideoService.render(sparse,
            edit: CaptureVideoEdit(end: 6, cuts: [.init(start: 1, end: 2)], holds: [.init(position: 3, duration: 1)]),
            options: .init(videoFramesPerSecond: 15), to: sparseOutput)
        let sparseInfo = try await CaptureVideoService.inspect(sparseOutput)
        precondition(abs(sparseInfo.duration - 6) < 0.001, "variable-rate exports must preserve the trailing frame time")
    }

    static func addAudio(_ video: URL, destination: URL) async throws {
        let audio = destination.deletingPathExtension().appendingPathExtension("m4a")
        try audioFixture(audio)
        let composition = AVMutableComposition()
        for (url, type) in [(video, AVMediaType.video), (audio, .audio)] {
            let asset = AVURLAsset(url: url)
            let source = try await asset.loadTracks(withMediaType: type)[0]
            let available = try await source.load(.timeRange)
            let track = composition.addMutableTrack(withMediaType: type, preferredTrackID: kCMPersistentTrackID_Invalid)!
            let range = available.intersection(CMTimeRange(start: .zero, duration: CaptureVideoService.time(2)))
            try withExtendedLifetime(asset) { try track.insertTimeRange(range, of: source, at: range.start) }
        }
        let exporter = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetPassthrough)!
        try await exporter.export(to: destination, as: .mp4)
    }

    static func audioFixture(_ url: URL, frequency: Double = 440) throws {
        let format = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 96_000)!
        buffer.frameLength = 96_000
        for index in 0..<96_000 {
            buffer.floatChannelData![0][index] = Float(sin(Double(index) * 2 * .pi * frequency / 48_000)) * 0.5
        }
        let file = try AVAudioFile(forWriting: url, settings: [
            AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 48_000,
            AVNumberOfChannelsKey: 1, AVEncoderBitRateKey: 128_000
        ])
        try file.write(from: buffer)
    }

    static func fixture(
        _ url: URL, red: Bool, alternating: Bool = false,
        times: [Double] = (0..<10).map { Double($0) / 10 }, duration: Double = 1
    ) async throws {
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: 128, AVVideoHeightKey: 64
        ])
        let attributes = CVPixelBufferCreationAttributes(pixelFormatType: .init(rawValue: kCVPixelFormatType_32BGRA),
            size: .init(width: 128, height: 64))
        let receiver = writer.inputPixelBufferReceiver(for: input, pixelBufferAttributes: attributes)
        try writer.start()
        writer.startSession(atSourceTime: .zero)
        for (index, position) in times.enumerated() {
            let red = alternating ? index.isMultiple(of: 2) : red
            var buffer = try CVMutablePixelBuffer(attributes)
            buffer.accessUnsafeMutableRawPlaneBytes { planes in
                let plane = planes[0]
                for row in 0..<64 {
                    for column in 0..<128 {
                        let offset = row * plane.properties.bytesPerRow + column * 4
                        plane.bytes[offset] = 0
                        plane.bytes[offset + 1] = red ? 0 : 255
                        plane.bytes[offset + 2] = red ? 255 : 0
                        plane.bytes[offset + 3] = 255
                    }
                }
            }
            try await receiver.append(CVReadOnlyPixelBuffer(buffer), with: CaptureVideoService.time(position))
        }
        writer.endSession(atSourceTime: CaptureVideoService.time(duration))
        receiver.finish()
        await writer.finishWriting()
        if let error = writer.error { throw error }
    }

    static func effects(_ source: URL, root: URL) async throws {
        let cover = CaptureVideoEffect(kind: .cover, start: 0.25, end: 1.75,
            rect: CGRect(x: 0.1, y: 0.1, width: 0.3, height: 0.3))
        let zoom = CaptureVideoEffect(kind: .zoom, start: 0.5, end: 1.5,
            rect: CGRect(x: 0, y: 0, width: 0.5, height: 0.5))
        let text = CaptureVideoEffect(kind: .text, start: 0, end: 2,
            rect: CGRect(x: 0.5, y: 0.5, width: 0.5, height: 0.5), text: "QA",
            color: .init(red: 255, green: 255, blue: 255))
        let edit = CaptureVideoEdit(end: 2, effects: [cover, zoom, text])
        _ = try edit.validated(duration: 2)
        let prepared = try await CaptureVideoService.prepare(source, edit: edit)
        let preview = AVAssetImageGenerator(asset: prepared.asset)
        preview.videoComposition = prepared.video
        preview.requestedTimeToleranceBefore = .zero
        preview.requestedTimeToleranceAfter = .zero
        let output = root.appendingPathComponent("effects.mp4")
        try await CaptureVideoService.render(source, edit: edit, to: output)
        let encoded = AVAssetImageGenerator(asset: AVURLAsset(url: output))
        encoded.requestedTimeToleranceBefore = .zero
        encoded.requestedTimeToleranceAfter = .zero
        for (time, point, hidden) in [(0.1, CGPoint(x: 0.2, y: 0.2), false),
            (0.3, CGPoint(x: 0.2, y: 0.2), true), (0.7, CGPoint(x: 0.65, y: 0.65), true),
            (1.6, CGPoint(x: 0.65, y: 0.65), false), (1.9, CGPoint(x: 0.2, y: 0.2), false)]
        {
            let left = try await preview.image(at: CaptureVideoService.time(time)).image
            let right = try await encoded.image(at: CaptureVideoService.time(time)).image
            let a = sample(left, at: point), b = sample(right, at: point)
            precondition(hidden ? a.prefix(3).allSatisfy { $0 < 10 } : a.prefix(3).contains { $0 > 200 },
                "preview must apply timed cover/zoom at \(time): \(a)")
            precondition(hidden ? b.prefix(3).allSatisfy { $0 < 10 } : b.prefix(3).contains { $0 > 200 },
                "export must apply the same timed cover/zoom at \(time): \(b)")
        }
        let renderer = try CaptureVideoEffectRenderer(effects: [text], size: .init(width: 128, height: 64))
        let image = renderer.image(CIImage(color: .red).cropped(to: CGRect(x: 0, y: 0, width: 128, height: 64)), at: 0)
        let rendered = CIContext().createCGImage(image, from: image.extent)!
        var white = 0
        for y in 33..<64 {
            for x in 65..<128 where sample(rendered, at: CGPoint(x: Double(x) / 128, y: Double(y) / 64))
                .prefix(3).allSatisfy({ $0 > 200 }) {
                white += 1
            }
        }
        precondition(white > 10, "video text must render in its own rectangle")
        var invalid = edit
        invalid.effects.append(zoom)
        precondition((try? invalid.validated(duration: 2)) == nil)
        invalid = edit; invalid.effects[0].rect.origin.x = -.infinity
        precondition((try? invalid.validated(duration: 2)) == nil)
        invalid = edit; invalid.trackVolumes[0] = .nan
        precondition((try? invalid.validated(duration: 2)) == nil)
        let timeline = CaptureVideoTimeline(.init(start: 0.1, end: 2, speed: 2,
            cuts: [.init(start: 0.5, end: 1)], holds: [.init(position: 1.5, duration: 1)]))
        precondition(abs(timeline.outputTime(at: 0.7) - 0.2) < 0.001)
        precondition(abs(timeline.outputTime(at: 1.5) - 0.45) < 0.001)
        precondition(abs(timeline.outputTime(at: 1.7) - 1.55) < 0.001)
        let gif = root.appendingPathComponent("effects.gif")
        try await CaptureGIFService.render(source, edit: edit,
            options: .init(format: .gif, maximumDimension: 320, framesPerSecond: 10), to: gif) { _ in }
        let gifSource = CGImageSourceCreateWithURL(gif as CFURL, nil)!
        let frame = CGImageSourceCreateImageAtIndex(gifSource, 7, nil)!
        precondition(sample(frame, at: CGPoint(x: 0.65, y: 0.65)).prefix(3).allSatisfy { $0 < 10 },
            "GIF must carry the same timed cover and zoom")
        let repository = CaptureRepository(root: root.appendingPathComponent("video-drafts"))
        let info = try await CaptureVideoService.inspect(output)
        let thumbnail = try await CaptureVideoService.thumbnail(output)
        try repository.commitVideo(output, info: info, preview: thumbnail,
            draft: .init(original: source, duration: 2, edit: edit))
        let entry = try repository.entries()[0]
        precondition(entry.draft && entry.editable && entry.subtitle.hasPrefix("Video draft"))
        let (lease, reopened) = try repository.openVideo(entry, id: UUID())
        precondition(reopened == edit)
        let originalBytes = try Data(contentsOf: source)
        let leasedBytes = try Data(contentsOf: lease.directory.appendingPathComponent("original.mp4"))
        precondition(originalBytes == leasedBytes)
        let transfer = try repository.transfer(entry, now: Date(), keeping: [])
        let copiedBytes = try Data(contentsOf: transfer), renderedBytes = try Data(contentsOf: output)
        precondition(copiedBytes == renderedBytes && copiedBytes != originalBytes,
            "copying a video draft must never disclose the retained unredacted source")
        let dragged = try await fileData(CaptureFileProvider.make(entry, repository: repository), type: .mpeg4Movie)
        precondition(dragged == renderedBytes)
        try repository.prune(now: Date().addingTimeInterval(100_000), days: 1, maximumBytes: 1)
        let retained = try repository.entries()
        precondition(retained.count == 1, "explicit drafts must survive automatic pruning")
        try FileManager.default.removeItem(at: repository.history)
        let leasedInfo = try await CaptureVideoService.inspect(lease.directory.appendingPathComponent("original.mp4"))
        precondition(leasedInfo.duration == 2)
    }

    @MainActor
    static func seeking(_ url: URL, root: URL) async throws {
        let source = try CaptureSource(directory: CaptureRepository(root: root.appendingPathComponent("seek")).create(id: UUID()))
        let state = try await CaptureVideoState(source: source, url: url, info: CaptureVideoService.inspect(url))
        await state.updatePreview()
        precondition(state.preview == .ready)
        state.seek(to: 0.7)
        let deadline = ContinuousClock.now + .seconds(2)
        while abs(state.player.currentTime().seconds - 0.7) > 0.02, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        precondition(abs(state.player.currentTime().seconds - 0.7) < 0.02,
            "scrubbing must seek to the requested time rather than an earlier key frame")
        state.player.replaceCurrentItem(with: nil)
    }

    static func quality(root: URL) async throws {
        let url = root.appendingPathComponent("noise.mp4")
        try await noise(url)
        var bytes: [Int] = []
        for quality in CaptureVideoExportOptions.Quality.allCases {
            let destination = root.appendingPathComponent("\(quality).mp4")
            try await CaptureVideoService.render(url, edit: .init(end: 1),
                options: .init(videoFramesPerSecond: 30, quality: quality), to: destination)
            let info = try await CaptureVideoService.inspect(destination)
            precondition(info.size.width == 512 && info.size.height == 320 && abs(info.duration - 1) < 0.01)
            bytes.append(try destination.resourceValues(forKeys: [.fileSizeKey]).fileSize!)
        }
        precondition(bytes[1] > bytes[0] * 11 / 10 && bytes[2] > bytes[1] * 11 / 10,
            "quality must change actual encoded output: \(bytes)")
        let (progress, updates) = AsyncStream<Double>.makeStream()
        let cancelled = root.appendingPathComponent("quality-cancelled.mp4")
        let worker = Task {
            try await CaptureVideoService.render(url, edit: .init(end: 1), to: cancelled) { updates.yield($0) }
        }
        for await value in progress where value > 0.05 { worker.cancel(); break }
        do { try await worker.value; preconditionFailure("cancelled encoding completed") } catch is CancellationError {}
        updates.finish()
        precondition(!FileManager.default.fileExists(atPath: cancelled.path))
    }

    static func noise(_ url: URL) async throws {
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: 512, AVVideoHeightKey: 320,
            AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: 12_000_000]
        ])
        let attributes = CVPixelBufferCreationAttributes(pixelFormatType: .init(rawValue: kCVPixelFormatType_32BGRA),
            size: .init(width: 512, height: 320))
        let receiver = writer.inputPixelBufferReceiver(for: input, pixelBufferAttributes: attributes)
        try writer.start(); writer.startSession(atSourceTime: .zero)
        var random: UInt64 = 0x81B956FF
        for index in 0..<30 {
            var buffer = try CVMutablePixelBuffer(attributes)
            buffer.accessUnsafeMutableRawPlaneBytes { planes in
                let plane = planes[0]
                for row in 0..<320 {
                    for column in 0..<512 {
                        random = random &* 6_364_136_223_846_793_005 &+ 1
                        let offset = row * plane.properties.bytesPerRow + column * 4
                        for channel in 0..<3 {
                            plane.bytes[offset + channel] = UInt8(truncatingIfNeeded: random >> (32 + channel * 8))
                        }
                        plane.bytes[offset + 3] = 255
                    }
                }
            }
            try await receiver.append(CVReadOnlyPixelBuffer(buffer), with: CaptureVideoService.time(Double(index) / 30))
        }
        writer.endSession(atSourceTime: CaptureVideoService.time(1)); receiver.finish()
        await writer.finishWriting()
        if let error = writer.error { throw error }
    }

    static func sample(_ image: CGImage, at point: CGPoint) -> [UInt8] {
        let rect = CGRect(x: Int(point.x * Double(image.width)), y: Int(point.y * Double(image.height)), width: 1, height: 1)
        return color(image.cropping(to: rect)!)
    }

    static func expectColor(_ url: URL, at seconds: Double, red: Bool) async throws {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        let (image, _) = try await generator.image(at: CaptureVideoService.time(seconds))
        let bytes = color(image)
        precondition(red ? bytes[0] > 200 && bytes[1] < 90 : bytes[1] > 200 && bytes[0] < 90,
            "decoded video frame has the wrong segment color at \(seconds): \(bytes)")
    }

    static func color(_ image: CGImage) -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: 4)
        bytes.withUnsafeMutableBytes { data in
            let context = CGContext(data: data.baseAddress, width: 1, height: 1, bitsPerComponent: 8,
                bytesPerRow: 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.draw(image, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        }
        return bytes
    }
}
