import AVFoundation
import CoreImage
import ScreenCaptureKit

// Fixed tones distinguish the recorded inputs without trusting track counts or UI labels.
enum CaptureRecordingFixture {
    static func run(video: URL, root: URL) async throws {
        let system = root.appendingPathComponent("system-tone.m4a")
        let microphone = root.appendingPathComponent("microphone-tone.m4a")
        try CaptureVideoTests.audioFixture(system, frequency: 440)
        try CaptureVideoTests.audioFixture(microphone, frequency: 880)
        let events = try await frames(video, type: .video, track: .screen)
            + frames(system, type: .audio, track: .system)
            + frames(microphone, type: .audio, track: .microphone, offset: 0.2)
        let ordered = events.sorted {
            if $0.sample.presentationTimeStamp == $1.sample.presentationTimeStamp { return $0.track.rawValue < $1.track.rawValue }
            return $0.sample.presentationTimeStamp < $1.sample.presentationTimeStamp
        }
        try await screenStatuses(first: ordered.first!.sample)
        let url = root.appendingPathComponent("recorded-tracks.mp4")
        let buffers = CaptureRecordingBuffers()
        let size = try CapturePixelSize(width: 128, height: 64)
        let task = Task.detached {
            try await CaptureRecordingWriter.write(buffers, to: url, size: size,
                options: .init(systemAudio: true, microphone: true))
        }
        for try await _ in buffers.ready { break }
        var previous = 1000.0
        for frame in ordered where frame.sample.presentationTimeStamp.seconds < 1002 {
            let now = frame.sample.presentationTimeStamp.seconds
            try await Task.sleep(for: .seconds(max(0, now - previous)))
            buffers.yield(frame.sample, track: frame.track)
            previous = now
        }
        buffers.finish(at: CaptureVideoService.time(1002))
        try await task.value
        let info = try await CaptureVideoService.inspect(url)
        precondition(info.audioTracks == 2 && abs(info.duration - 2) < 0.005)
        precondition(info.audioNames == ["System Audio", "Microphone"])
        try await CaptureVideoTests.expectColor(url, at: 0.5, red: true)
        try await CaptureVideoTests.expectColor(url, at: 1.5, red: false)
        for index in 0..<2 {
            var edit = CaptureVideoEdit(end: 2)
            edit.trackVolumes[1 - index] = 0
            let exported = root.appendingPathComponent("track-\(index).mp4")
            try await CaptureVideoService.render(url, edit: edit, to: exported)
            let own = try amplitude(exported, frequency: index == 0 ? 440 : 880, start: 0.5)
            let other = try amplitude(exported, frequency: index == 0 ? 880 : 440, start: 0.5)
            precondition(own > 0.25 && other < 0.01, "each volume must control only its recorded input: \(own), \(other)")
            if index == 1 {
                let leading = try amplitude(exported, frequency: 880, start: 0.03)
                precondition(leading < 0.002,
                    "microphone's delayed timestamps must not slide to the first video frame")
            }
        }
        let paused = root.appendingPathComponent("independent-paused.mp4")
        try await CaptureVideoService.join([url, url], to: paused)
        let pausedInfo = try await CaptureVideoService.inspect(paused)
        precondition(pausedInfo.audioTracks == 2)
        precondition(pausedInfo.audioNames == info.audioNames)
        let microphoneOnly = root.appendingPathComponent("microphone-only.mp4")
        try await CaptureVideoService.combineTracks(video: video,
            audio: [.init(url: microphone, offset: 0, title: "Microphone")], to: microphoneOnly)
        let missingTrack = root.appendingPathComponent("missing-system-segment.mp4")
        try await CaptureVideoService.join([microphoneOnly, url], to: missingTrack)
        let missingInfo = try await CaptureVideoService.inspect(missingTrack)
        precondition(missingInfo.audioNames == ["Microphone", "System Audio"])
        let isolatedSystem = root.appendingPathComponent("system-after-pause.mp4")
        var isolated = CaptureVideoEdit(end: 4)
        isolated.trackVolumes[0] = 0
        try await CaptureVideoService.render(missingTrack, edit: isolated, to: isolatedSystem)
        let initial = try amplitude(isolatedSystem, frequency: 880, start: 0.5)
        let later = try amplitude(isolatedSystem, frequency: 440, start: 2.5)
        precondition(initial < 0.002 && later > 0.25, "pause joins must not swap an absent system track with microphone")
        let sparse = CaptureRecordingBuffers(), sparseURL = root.appendingPathComponent("static-tail.mp4")
        sparse.yield(ordered.first!.sample, track: .screen)
        sparse.finish(at: CaptureVideoService.time(1002))
        try await CaptureRecordingWriter.write(sparse, to: sparseURL, size: size, options: .init())
        let sparseInfo = try await CaptureVideoService.inspect(sparseURL)
        precondition(abs(sparseInfo.duration - 2) < 0.005, "a static screen must remain visible until Stop")
        try await CaptureVideoTests.expectColor(sparseURL, at: 1.9, red: true)
        let overflow = CaptureRecordingBuffers(), failed = root.appendingPathComponent("overflow.mp4")
        for _ in 0..<4 { overflow.yield(ordered.first!.sample, track: .screen) }
        do {
            try await CaptureRecordingWriter.write(overflow, to: failed, size: size, options: .init())
            preconditionFailure("overload must not silently drop content")
        } catch CaptureRecordingBuffers.Failure.overloaded { }
        precondition(!FileManager.default.fileExists(atPath: failed.path))
        try await cancellation(first: ordered.first!.sample, size: size, root: root)
        let silent = CaptureRecordingBuffers(), silentURL = root.appendingPathComponent("enabled-without-samples.mp4")
        silent.yield(ordered.first!.sample, track: .screen)
        silent.finish(at: CaptureVideoService.time(1002))
        try await CaptureRecordingWriter.write(silent, to: silentURL, size: size,
            options: .init(systemAudio: true, microphone: true))
        let silentInfo = try await CaptureVideoService.inspect(silentURL)
        precondition(silentInfo.audioTracks == 0 && abs(silentInfo.duration - 2) < 0.005)
        try await overlays(videoFrames: ordered.filter { $0.track == .screen }, root: root, size: size)
    }

    private static func screenStatuses(first: CaptureRecordingBuffers.Sample) async throws {
        let buffers = CaptureRecordingBuffers()
        precondition(!buffers.hasScreenFrame)
        for status in [SCFrameStatus.started, .suspended, .blank, .complete, .idle, .stopped] {
            try first.withUnsafeSampleBuffer { original in
                let sample = try CMSampleBuffer(copying: original)
                let attachments = CMSampleBufferGetSampleAttachmentsArray(sample, createIfNecessary: true)!
                let dictionary = unsafeBitCast(CFArrayGetValueAtIndex(attachments, 0), to: CFMutableDictionary.self)
                let key = SCStreamFrameInfo.status.rawValue as NSString, value = NSNumber(value: status.rawValue)
                CFDictionarySetValue(dictionary, Unmanaged.passUnretained(key).toOpaque(),
                    Unmanaged.passUnretained(value).toOpaque())
                buffers.receive(sample, type: .screen)
            }
            precondition(buffers.screenStatus == status, "non-image frames must still update capture availability")
            if status == .started || status == .suspended || status == .blank {
                precondition(!buffers.hasScreenFrame, "an unavailable source must not claim recording has started")
            }
        }
        precondition(buffers.hasScreenFrame)
        buffers.finish(at: CaptureVideoService.time(1001))
        var count = 0
        for try await _ in buffers.frames[.screen]! { count += 1 }
        precondition(count == 1, "idle, suspended and stopped frames must not enter the encoded video")
    }

    private static func overlays(
        videoFrames: [CaptureRecordingBuffers.Frame], root: URL, size: CapturePixelSize
    ) async throws {
        func label(_ mode: CaptureRecordingOptions.Keys, command: Bool = false, secure: Bool = false) -> String? {
            CaptureKeystrokePolicy.label(mode: mode, keyCode: 0, characters: "a", command: command,
                control: false, option: false, shift: false, repeated: false, secure: secure)
        }
        precondition(label(.off, command: true) == nil && label(.shortcuts) == nil)
        precondition(label(.shortcuts, command: true) == "⌘A" && label(.all) == "A")
        precondition(label(.all, command: true, secure: true) == nil)
        let layers = CaptureRecordingOverlays(), first = videoFrames.first!.sample
        layers.camera(videoFrames.last!.sample)
        var options = CaptureRecordingOptions()
        options.camera = true
        let renderer = try CaptureRecordingRenderer(size: size, options: options, overlays: layers)
        let withCamera = try renderer.render(first)
        let context = CIContext(options: [.useSoftwareRenderer: true])
        func image(_ sample: CaptureRecordingBuffers.Sample) throws -> CGImage {
            guard case .pixelBuffer(let buffer) = sample.content else { throw CaptureVideoError.invalidMedia }
            let source = buffer.withUnsafeBuffer { CIImage(cvPixelBuffer: $0) }
            return context.createCGImage(source, from: CGRect(x: 0, y: 0, width: size.width, height: size.height))!
        }
        let green = CaptureVideoTests.sample(try image(withCamera), at: CGPoint(x: 0.925, y: 0.85))
        let red = CaptureVideoTests.sample(try image(withCamera), at: CGPoint(x: 0.1, y: 0.1))
        precondition(green[1] > 200 && green[0] < 80 && red[0] > 200 && red[1] < 80)
        options.camera = false; options.keys = .shortcuts
        layers.key("⌘K", at: CaptureVideoService.time(1000))
        let keyboard = try CaptureRecordingRenderer(size: size, options: options, overlays: layers)
        let caption = try image(keyboard.render(first))
        let dark = CaptureVideoTests.sample(caption, at: CGPoint(x: 0.4, y: 0.8))
        precondition(dark[0] < 180, "keyboard content must be burned into the frame")
        var later = first
        later.sampleProperties.timings = .sequential(presentationTimeOfFirstSample: CaptureVideoService.time(1002),
            uniformDuration: CMTime(value: 1, timescale: 30))
        later.outputPresentationTimeStamp = CaptureVideoService.time(1002)
        let expired = CaptureVideoTests.sample(try image(keyboard.render(later)), at: CGPoint(x: 0.4, y: 0.8))
        precondition(expired[0] > 200 && expired[1] < 80, "keyboard content must expire without a new key event")
        let buffers = CaptureRecordingBuffers(overlayFrames: true), url = root.appendingPathComponent("static-overlays.mp4")
        buffers.accept(first, track: .screen)
        layers.key("⌘K", at: CMClockGetTime(CMClockGetHostTimeClock()))
        let recordingOptions = options
        let writer = Task.detached {
            try await CaptureRecordingWriter.write(buffers, to: url, size: size, options: recordingOptions, overlays: layers)
        }
        for try await _ in buffers.ready { break }
        let pump = buffers.pump(framesPerSecond: 30)
        try await Task.sleep(for: .milliseconds(450))
        pump.cancel(); buffers.finish(at: CMClockGetTime(CMClockGetHostTimeClock()))
        try await writer.value
        let info = try await CaptureVideoService.inspect(url)
        precondition(info.duration > 0.35 && info.duration < 1)
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        let (frame, _) = try await generator.image(at: CaptureVideoService.time(0.2))
        let saved = CaptureVideoTests.sample(frame, at: CGPoint(x: 0.4, y: 0.8))
        precondition(saved[0] < 180, "a static screen must still encode moving overlay content")
        layers.clear()
        precondition(!layers.cameraIsFresh && layers.snapshot(at: .zero).key == nil)
    }

    private static func cancellation(
        first: CaptureRecordingBuffers.Sample, size: CapturePixelSize, root: URL
    ) async throws {
        for withFrame in [false, true] {
            let buffers = CaptureRecordingBuffers(), url = root.appendingPathComponent("cancelled-\(withFrame).mp4")
            let writer = Task.detached {
                try await CaptureRecordingWriter.write(buffers, to: url, size: size,
                    options: .init(systemAudio: true, microphone: true))
            }
            for try await _ in buffers.ready { break }
            if withFrame {
                buffers.yield(first, track: .screen)
                try await Task.sleep(for: .milliseconds(40))
            }
            let start = ContinuousClock.now
            writer.cancel()
            do {
                try await writer.value
                preconditionFailure("cancelled recording must not publish a partial file")
            } catch { }
            precondition(start.duration(to: .now) < .seconds(2))
            let files = try FileManager.default.contentsOfDirectory(atPath: root.path)
            let prefix = url.deletingPathExtension().lastPathComponent
            precondition(!files.contains(where: { $0.hasPrefix(prefix) }))
        }
    }

    private static func frames(
        _ url: URL, type: AVMediaType, track: CaptureRecordingBuffers.Track, offset: Double = 0
    ) async throws -> [CaptureRecordingBuffers.Frame] {
        let asset = AVURLAsset(url: url)
        let source = try await asset.loadTracks(withMediaType: type)[0]
        let reader = try AVAssetReader(asset: asset)
        let settings: [String: Any] = type == .video
            ? [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
            : [AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 48_000, AVNumberOfChannelsKey: 1]
        let output = reader.outputProvider(for: AVAssetReaderTrackOutput(track: source, outputSettings: settings))
        try reader.start()
        var result: [CaptureRecordingBuffers.Frame] = []
        while var sample = try await output.next() {
            let timing = sample.sampleProperties[0].timing, shift = CaptureVideoService.time(1000 + offset)
            sample.sampleProperties.timings = .sequential(startingAt: .init(duration: timing.duration,
                presentationTimeStamp: timing.presentationTimeStamp + shift,
                decodeTimeStamp: timing.decodeTimeStamp.isNumeric ? timing.decodeTimeStamp + shift : .invalid))
            sample.outputPresentationTimeStamp = sample.presentationTimeStamp
            result.append(.init(sample: sample, track: track))
        }
        return result
    }

    private static func amplitude(_ url: URL, frequency: Double, start: Double) throws -> Double {
        let file = try AVAudioFile(forReading: url)
        let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length))!
        try file.read(into: buffer)
        let samples = buffer.floatChannelData![0], rate = file.processingFormat.sampleRate
        let range = Int(start * rate)..<Int((start + 0.1) * rate)
        var real = 0.0, imaginary = 0.0
        for index in range {
            let phase = Double(index) * 2 * .pi * frequency / rate
            real += Double(samples[index]) * cos(phase)
            imaginary += Double(samples[index]) * sin(phase)
        }
        return 2 * hypot(real, imaginary) / Double(range.count)
    }
}
