import AVFoundation

enum CaptureRecordingWriter {
    nonisolated static func write(
        _ buffers: CaptureRecordingBuffers, to url: URL, size: CapturePixelSize,
        options: CaptureRecordingOptions,
        overlays: CaptureRecordingOverlays? = nil
    ) async throws {
        let stem = url.deletingPathExtension()
        let raw = stem.appendingPathExtension("video.mp4")
        let system = stem.appendingPathExtension("system.m4a"),
            microphone = stem.appendingPathExtension("microphone.m4a")
        defer { for file in [raw, system, microphone] { try? FileManager.default.removeItem(at: file) } }
        let writer = try AVAssetWriter(outputURL: raw, fileType: .mp4)
        let input = AVAssetWriterInput(
            mediaType: .video,
            outputSettings: [
                AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: size.width,
                AVVideoHeightKey: size.height,
                AVVideoCompressionPropertiesKey: [
                    AVVideoAverageBitRateKey: min(40_000_000, size.width * size.height * 3),
                    AVVideoExpectedSourceFrameRateKey: options.framesPerSecond,
                    AVVideoAllowFrameReorderingKey: false,
                    AVVideoMaxKeyFrameIntervalKey: options.framesPerSecond * 2
                ]
            ])
        var complete = false
        defer { if !complete { writer.cancelWriting(); try? FileManager.default.removeItem(at: url) } }
        try Task.checkCancellation()
        let cancellation = CaptureEncodingCancellation(writer: writer)
        try await withTaskCancellationHandler {
            try await record(
                buffers, writer: writer, input: input, options: options,
                system: system, microphone: microphone, raw: raw, destination: url,
                cancellation: cancellation, size: size, overlays: overlays)
        } onCancel: {
            buffers.fail(CancellationError())
            cancellation.cancel()
        }
        complete = true
    }

    nonisolated private static func record(
        _ buffers: CaptureRecordingBuffers, writer: AVAssetWriter,
        input: AVAssetWriterInput, options: CaptureRecordingOptions,
        system: URL, microphone: URL, raw: URL, destination: URL, cancellation: CaptureEncodingCancellation,
        size: CapturePixelSize, overlays: CaptureRecordingOverlays?
    ) async throws {
        let receiver = writer.inputReceiver(for: input)
        let renderer = try overlays.map {
            try CaptureRecordingRenderer(size: size, options: options, overlays: $0)
        }
        try Task.checkCancellation()
        try writer.start()
        buffers.started()
        var iterator = buffers.frames[.screen]!.makeAsyncIterator()
        guard let first = try await iterator.next() else { throw CaptureVideoError.invalidMedia }
        let origin = first.presentationTimeStamp
        writer.startSession(atSourceTime: origin)
        async let videoEnd = consumeVideo(
            buffers, first: first, receiver: receiver,
            fps: options.framesPerSecond, renderer: renderer)
        async let systemURL = writeAudio(
            buffers, track: .system, enabled: options.systemAudio,
            to: system, title: String(localized: "System Audio"), origin: origin)
        async let microphoneURL = writeAudio(
            buffers, track: .microphone, enabled: options.microphone,
            to: microphone, title: String(localized: "Microphone"), origin: origin)
        let end: CMTime, audio: [CaptureVideoService.AudioSource]
        do {
            let result = try await (videoEnd, systemURL, microphoneURL)
            end = result.0; audio = [result.1, result.2].compactMap { $0 }
        } catch {
            writer.cancelWriting()
            buffers.fail(error)
            throw error
        }
        writer.endSession(atSourceTime: end)
        try await cancellation.finish()
        try await CaptureVideoService.combineTracks(video: raw, audio: audio, to: destination)
    }

    nonisolated private static func writeAudio(
        _ buffers: CaptureRecordingBuffers, track: CaptureRecordingBuffers.Track, enabled: Bool,
        to url: URL, title: String, origin: CMTime
    ) async throws -> CaptureVideoService.AudioSource? {
        guard enabled else { return nil }
        let writer = try AVAssetWriter(outputURL: url, fileType: .m4a)
        let input = AVAssetWriterInput(
            mediaType: .audio,
            outputSettings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 48_000,
                AVNumberOfChannelsKey: 2, AVEncoderBitRateKey: 192_000
            ])
        let label = AVMutableMetadataItem()
        label.identifier = .commonIdentifierTitle; label.value = title as NSString
        input.metadata = [label]
        let receiver = writer.inputReceiver(for: input)
        let cancellation = CaptureEncodingCancellation(writer: writer)
        do {
            return try await withTaskCancellationHandler {
                try await audio(
                    buffers.frames[track]!, writer: writer, receiver: receiver,
                    url: url, title: title, origin: origin, cancellation: cancellation)
            } onCancel: {
                cancellation.cancel()
            }
        } catch {
            buffers.fail(error)
            throw error
        }
    }

    nonisolated private static func audio(
        _ frames: AsyncThrowingStream<CaptureRecordingBuffers.Sample, Error>, writer: AVAssetWriter,
        receiver: AVAssetWriterInput.SampleBufferReceiver, url: URL, title: String, origin: CMTime,
        cancellation: CaptureEncodingCancellation
    ) async throws -> CaptureVideoService.AudioSource? {
        var start: CMTime?, complete = false
        defer { if !complete { writer.cancelWriting(); try? FileManager.default.removeItem(at: url) } }
        try writer.start()
        for try await sample in frames where sample.presentationTimeStamp >= origin {
            try Task.checkCancellation()
            if start == nil {
                start = sample.presentationTimeStamp
                writer.startSession(atSourceTime: sample.presentationTimeStamp)
            }
            try await append(sample, to: receiver)
        }
        try Task.checkCancellation()
        guard let start else { return nil }
        receiver.finish()
        try await cancellation.finish()
        complete = true
        return .init(url: url, offset: (start - origin).seconds, title: title)
    }

    nonisolated private static func consumeVideo(
        _ buffers: CaptureRecordingBuffers, first: CaptureRecordingBuffers.Sample,
        receiver: sending AVAssetWriterInput.SampleBufferReceiver, fps: Int,
        renderer: sending CaptureRecordingRenderer?
    ) async throws -> CMTime {
        defer { receiver.finish() }
        var last = first
        try await append(renderer?.render(first) ?? first, to: receiver)
        for try await sample in buffers.frames[.screen]! {
            try Task.checkCancellation()
            try await append(renderer?.render(sample) ?? sample, to: receiver)
            last = sample
        }
        try Task.checkCancellation()
        let interval = CMTime(value: 1, timescale: Int32(fps))
        let end = max(
            buffers.stopped ?? last.presentationTimeStamp + interval, last.presentationTimeStamp + interval)
        if end - last.presentationTimeStamp > interval + interval {
            var tail = last
            tail.sampleProperties.timings = .sequential(
                presentationTimeOfFirstSample: end - interval,
                uniformDuration: interval)
            tail.outputPresentationTimeStamp = end - interval
            try await append(renderer?.render(tail) ?? tail, to: receiver)
        }
        return end
    }

    nonisolated private static func append(
        _ sample: CaptureRecordingBuffers.Sample, to receiver: AVAssetWriterInput.SampleBufferReceiver
    ) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(1))
        while try !receiver.appendImmediately(sample) {
            try Task.checkCancellation()
            guard .now < deadline else { throw CaptureRecordingBuffers.Failure.encoderStalled }
            try await Task.sleep(for: .milliseconds(2))
        }
    }
}
