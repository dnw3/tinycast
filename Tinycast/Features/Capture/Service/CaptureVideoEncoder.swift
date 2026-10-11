import AVFoundation

enum CaptureVideoEncoder {
    nonisolated static func write(
        _ prepared: CaptureVideoService.Prepared, options: CaptureVideoExportOptions, to destination: URL,
        progress: @escaping @Sendable (Double) async -> Void
    ) async throws {
        let duration = try await prepared.asset.load(.duration)
        let tracks = try await prepared.asset.loadTracks(withMediaType: .video)
        let audioTracks = try await prepared.asset.loadTracks(withMediaType: .audio)
        let reader = try AVAssetReader(asset: prepared.asset)
        reader.timeRange = CMTimeRange(start: .zero, duration: duration)
        let output = AVAssetReaderVideoCompositionOutput(videoTracks: tracks,
            videoSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
        output.videoComposition = prepared.video
        let video = reader.outputProvider(for: output)
        let writer = try AVAssetWriter(outputURL: destination, fileType: .mp4)
        writer.shouldOptimizeForNetworkUse = true
        let size = try CapturePixelSize(width: Int(prepared.video.renderSize.width),
            height: Int(prepared.video.renderSize.height))
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: size.width, AVVideoHeightKey: size.height,
            AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: options.bitRate(size: size),
                AVVideoExpectedSourceFrameRateKey: options.videoFramesPerSecond,
                AVVideoMaxKeyFrameIntervalKey: options.videoFramesPerSecond * 2,
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel]
        ])
        let receiver = writer.inputReceiver(for: input)
        var audio: AVAssetReaderOutput.Provider<CMReadySampleBuffer<CMSampleBuffer.DynamicContent>>?
        var audioReceiver: AVAssetWriterInput.SampleBufferReceiver?
        if !audioTracks.isEmpty {
            let output = AVAssetReaderAudioMixOutput(audioTracks: audioTracks, audioSettings: [
                AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 48_000, AVNumberOfChannelsKey: 2
            ])
            output.audioMix = prepared.mix
            output.audioTimePitchAlgorithm = .timeDomain
            audio = reader.outputProvider(for: output)
            let input = AVAssetWriterInput(mediaType: .audio, outputSettings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 48_000,
                AVNumberOfChannelsKey: 2, AVEncoderBitRateKey: 192_000
            ])
            audioReceiver = writer.inputReceiver(for: input)
        }
        var complete = false
        defer {
            if !complete {
                reader.cancelReading(); writer.cancelWriting()
                try? FileManager.default.removeItem(at: destination)
            }
        }
        try Task.checkCancellation()
        try reader.start()
        try writer.start()
        writer.startSession(atSourceTime: .zero)
        let cancellation = CaptureEncodingCancellation(writer: writer)
        do {
            async let videoResult = pipe(video, to: receiver, duration: duration.seconds,
                cancellation: cancellation, progress: progress)
            async let audioResult = pipe(audio, to: audioReceiver, duration: nil,
                cancellation: cancellation, progress: progress)
            _ = try await (videoResult, audioResult)
        } catch {
            reader.cancelReading(); writer.cancelWriting()
            throw error
        }
        try Task.checkCancellation()
        writer.endSession(atSourceTime: duration)
        try await withTaskCancellationHandler {
            try await cancellation.finish()
        } onCancel: { cancellation.cancel() }
        if let error = reader.error ?? writer.error { throw error }
        guard writer.status == .completed else { throw CaptureVideoError.invalidMedia }
        try Task.checkCancellation()
        complete = true
        await progress(1)
    }

    nonisolated private static func pipe(
        _ provider: sending AVAssetReaderOutput.Provider<CMReadySampleBuffer<CMSampleBuffer.DynamicContent>>?,
        to receiver: sending AVAssetWriterInput.SampleBufferReceiver?, duration: Double?,
        cancellation: CaptureEncodingCancellation,
        progress: @escaping @Sendable (Double) async -> Void
    ) async throws {
        guard let provider, let receiver else { return }
        defer { receiver.finish() }
        try await withTaskCancellationHandler {
            var reported = -1.0
            while true {
                try Task.checkCancellation()
                guard let sample = try await provider.next() else { break }
                try Task.checkCancellation()
                try await receiver.append(sample)
                if let duration {
                    let fraction = min(0.99, sample.presentationTimeStamp.seconds / duration)
                    if fraction - reported >= 0.01 { await progress(fraction); reported = fraction }
                }
            }
            try Task.checkCancellation()
        } onCancel: { cancellation.cancel() }
    }
}
