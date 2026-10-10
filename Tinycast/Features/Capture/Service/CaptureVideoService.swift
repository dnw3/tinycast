import AVFoundation

enum CaptureVideoService {
    struct Info: Sendable {
        let duration: Double
        let size: CapturePixelSize
        let audioTracks: Int
        var audioNames: [String] = []
    }

    struct Prepared {
        let asset: AVComposition
        let mix: AVAudioMix
        let video: AVVideoComposition
    }

    struct AudioSource: Sendable {
        let url: URL
        let offset: Double
        let title: String
    }

    nonisolated static func thumbnail(_ url: URL) async throws -> CGImage {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 256, height: 256)
        return try await generator.image(at: .zero).image
    }

    nonisolated static func inspect(_ url: URL) async throws -> Info {
        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration).seconds
        guard duration.isFinite, duration > 0, let video = try await asset.loadTracks(withMediaType: .video).first else {
            throw CaptureVideoError.invalidMedia
        }
        let natural = try await video.load(.naturalSize)
        let transform = try await video.load(.preferredTransform)
        let size = natural.applying(transform)
        let audio = try await asset.loadTracks(withMediaType: .audio)
        return try await Info(duration: duration,
            size: CapturePixelSize(width: Int(abs(size.width).rounded()), height: Int(abs(size.height).rounded())),
            audioTracks: audio.count, audioNames: names(asset, count: audio.count))
    }

    nonisolated static func join(_ urls: [URL], to destination: URL) async throws {
        try await work {
            guard !urls.isEmpty else { throw CaptureVideoError.invalidMedia }
            if urls.count == 1 {
                _ = try await inspect(urls[0])
                try Task.checkCancellation()
                try FileManager.default.copyItem(at: urls[0], to: destination)
                if Task.isCancelled {
                    try? FileManager.default.removeItem(at: destination)
                    throw CancellationError()
                }
                return
            }
            let composition = AVMutableComposition()
            var position = CMTime.zero
            var tracks: [AVMediaType: [AVMutableCompositionTrack]] = [:]
            var audioNames: [String] = []
            for url in urls {
                try Task.checkCancellation()
                let asset = AVURLAsset(url: url)
                let duration = try await asset.load(.duration)
                guard duration.isNumeric, duration.seconds > 0 else { throw CaptureVideoError.invalidMedia }
                for type in [AVMediaType.video, .audio] {
                    let sources = try await asset.loadTracks(withMediaType: type)
                    let names = type == .audio ? try await names(asset, count: sources.count) : []
                    for (sourceIndex, source) in sources.enumerated() {
                        let name = names.indices.contains(sourceIndex) ? names[sourceIndex] : "Audio \(sourceIndex + 1)"
                        let index = type == .audio ? audioNames.firstIndex(of: name) ?? audioNames.count : sourceIndex
                        if (tracks[type]?.count ?? 0) <= index {
                            guard let track = composition.addMutableTrack(withMediaType: type,
                                preferredTrackID: kCMPersistentTrackID_Invalid) else { throw CaptureVideoError.invalidMedia }
                            track.preferredTransform = try await source.load(.preferredTransform)
                            tracks[type, default: []].append(track)
                            if type == .audio { audioNames.append(name) }
                        }
                        let range = try await source.load(.timeRange).intersection(CMTimeRange(start: .zero, duration: duration))
                        try tracks[type]?[index].insertTimeRange(range, of: source, at: position + range.start)
                    }
                }
                position = CMTimeAdd(position, duration)
            }
            try await export(composition, preset: AVAssetExportPresetPassthrough, mix: nil,
                audioNames: audioNames, to: destination)
        }
    }

    nonisolated static func combineTracks(video: URL, audio: [AudioSource], to destination: URL) async throws {
        guard !audio.isEmpty else { try FileManager.default.moveItem(at: video, to: destination); return }
        let composition = AVMutableComposition()
        let videoAsset = AVURLAsset(url: video)
        let duration = try await videoAsset.load(.duration)
        let sources = [(video, AVMediaType.video, 0.0, "")] + audio.map { ($0.url, AVMediaType.audio, $0.offset, $0.title) }
        var audioNames: [String] = []
        for (url, type, offset, title) in sources {
            guard offset.isFinite, offset >= 0 else { throw CaptureVideoError.invalidMedia }
            if offset >= duration.seconds { continue }
            let asset = AVURLAsset(url: url)
            for source in try await asset.loadTracks(withMediaType: type) {
                let range = try await source.load(.timeRange).intersection(
                    CMTimeRange(start: .zero, duration: duration - time(offset)))
                guard range.duration.seconds > 0 else { continue }
                guard let track = composition.addMutableTrack(withMediaType: type,
                    preferredTrackID: kCMPersistentTrackID_Invalid) else { throw CaptureVideoError.invalidMedia }
                track.preferredTransform = try await source.load(.preferredTransform)
                try track.insertTimeRange(range, of: source, at: range.start + time(offset))
                if type == .audio { audioNames.append(title) }
            }
        }
        try await export(composition, preset: AVAssetExportPresetPassthrough, mix: nil,
            audioNames: audioNames, to: destination)
    }

    nonisolated static func render(
        _ url: URL, edit: CaptureVideoEdit, options: CaptureVideoExportOptions = .init(), to destination: URL,
        progress: @escaping @Sendable (Double) async -> Void = { _ in }
    ) async throws {
        try await work {
            let prepared = try await prepare(url, edit: edit, options: options)
            try await CaptureVideoEncoder.write(prepared, options: options, to: destination, progress: progress)
        }
    }

    nonisolated static func prepare(
        _ url: URL, edit: CaptureVideoEdit, options: CaptureVideoExportOptions = .init()
    ) async throws -> sending Prepared {
        let asset = AVURLAsset(url: url)
        let edit = try await edit.validated(duration: asset.load(.duration).seconds)
        let timeline = CaptureVideoTimeline(edit)
        let composition = AVMutableComposition()
        let mix = AVMutableAudioMix()
        var parameters: [AVAudioMixInputParameters] = []
        for type in [AVMediaType.video, .audio] {
            for (index, source) in try await asset.loadTracks(withMediaType: type).enumerated() {
                guard let track = composition.addMutableTrack(withMediaType: type,
                    preferredTrackID: kCMPersistentTrackID_Invalid) else { throw CaptureVideoError.invalidMedia }
                track.preferredTransform = try await source.load(.preferredTransform)
                let sourceRange = try await source.load(.timeRange)
                for segment in timeline.segments {
                    try Task.checkCancellation()
                    if segment.hold && type == .audio { continue }
                    let range = segment.hold
                        ? try await holdRange(asset: asset, at: segment.sourceStart)
                        : CMTimeRange(start: time(segment.sourceStart), end: time(segment.sourceEnd))
                    let available = sourceRange.intersection(range)
                    guard available.duration.seconds > 0 else { continue }
                    let scale = segment.hold ? segment.duration / available.duration.seconds : 1 / edit.speed
                    let offset = segment.hold ? 0 : (available.start.seconds - segment.sourceStart) * scale
                    let position = time(segment.outputStart + offset)
                    try track.insertTimeRange(available, of: source, at: position)
                    track.scaleTimeRange(CMTimeRange(start: position, duration: available.duration),
                        toDuration: time(available.duration.seconds * scale))
                }
                if type == .audio {
                    let volume = AVMutableAudioMixInputParameters(track: track)
                    volume.setVolume(Float(edit.volume * (edit.trackVolumes[index] ?? 1)), at: .zero)
                    parameters.append(volume)
                }
            }
        }
        mix.inputParameters = parameters
        var configuration = try await AVVideoComposition.Configuration(for: composition)
        let size = try options.videoSize(CapturePixelSize(width: Int(configuration.renderSize.width.rounded()),
            height: Int(configuration.renderSize.height.rounded())))
        guard let track = try await composition.loadTracks(withMediaType: .video).first else {
            throw CaptureVideoError.invalidMedia
        }
        let natural = try await track.load(.naturalSize)
        let preferred = try await track.load(.preferredTransform)
        let bounds = CGRect(origin: .zero, size: natural).applying(preferred)
        let transform = preferred.concatenating(CGAffineTransform(translationX: -bounds.minX, y: -bounds.minY))
            .concatenating(CGAffineTransform(scaleX: CGFloat(size.width) / bounds.width,
                y: CGFloat(size.height) / bounds.height))
        var layer = AVVideoCompositionLayerInstruction.Configuration(assetTrack: track)
        layer.setTransform(transform, at: .zero)
        configuration.instructions = [AVVideoCompositionInstruction(configuration: .init(
            layerInstructions: [AVVideoCompositionLayerInstruction(configuration: layer)],
            timeRange: CMTimeRange(start: .zero, duration: time(edit.duration))))]
        configuration.renderSize = CGSize(width: size.width, height: size.height)
        configuration.frameDuration = CMTime(value: 1, timescale: Int32(options.videoFramesPerSecond))
        configuration.sourceTrackIDForFrameTiming = kCMPersistentTrackID_Invalid
        if !edit.effects.isEmpty {
            let renderer = try CaptureVideoEffectRenderer(effects: edit.effects, size: size)
            let filtered = try await AVVideoComposition(applyingFiltersTo: composition) { request in
                let position = timeline.sourceTime(at: request.compositionTime.seconds) ?? edit.end - 1 / 60_000.0
                return AVCIImageFilteringResult(resultImage: renderer.image(request.sourceImage, at: position))
            }
            configuration.customVideoCompositorClass = filtered.customVideoCompositorClass
            configuration.instructions = filtered.instructions
        }
        try Task.checkCancellation()
        return Prepared(asset: composition, mix: mix, video: AVVideoComposition(configuration: configuration))
    }

    nonisolated private static func holdRange(asset: AVAsset, at position: Double) async throws -> CMTimeRange {
        let generator = AVAssetImageGenerator(asset: asset)
        generator.maximumSize = CGSize(width: 1, height: 1)
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        let frame = try await generator.image(at: time(position))
        return CMTimeRange(start: frame.actualTime, duration: CMTime(value: 1, timescale: 600))
    }

    nonisolated static func time(_ seconds: Double) -> CMTime { CMTime(seconds: seconds, preferredTimescale: 60_000) }

    nonisolated private static func export(
        _ asset: AVAsset, preset: String, mix: AVAudioMix?, video: AVVideoComposition? = nil,
        audioNames: [String] = [], to destination: URL,
        progress: @escaping @Sendable (Double) async -> Void = { _ in }
    ) async throws {
        guard let exporter = AVAssetExportSession(asset: asset, presetName: preset) else {
            throw CaptureVideoError.invalidMedia
        }
        exporter.audioMix = mix
        exporter.audioTimePitchAlgorithm = .timeDomain
        exporter.videoComposition = video
        if !audioNames.isEmpty {
            let item = AVMutableMetadataItem()
            item.identifier = .commonIdentifierDescription
            item.dataType = kCMMetadataBaseDataType_UTF8 as String
            item.extendedLanguageTag = "und"
            item.value = ("Audio tracks: " + audioNames.joined(separator: ", ")) as NSString
            exporter.metadata = [item]
        }
        exporter.shouldOptimizeForNetworkUse = true
        exporter.timeRange = try await CMTimeRange(start: .zero, duration: asset.load(.duration))
        do {
            let states = exporter.states(updateInterval: 0.2)
            try await withThrowingTaskGroup(of: Void.self) { group in
                group.addTask {
                    for await state in states {
                        if case .exporting(let value) = state { await progress(value.fractionCompleted) }
                    }
                }
                try await exporter.export(to: destination, as: .mp4)
                group.cancelAll()
            }
            try Task.checkCancellation()
            await progress(1)
        } catch {
            try? FileManager.default.removeItem(at: destination)
            throw error
        }
    }

    nonisolated private static func names(_ asset: AVAsset, count: Int) async throws -> [String] {
        let metadata = try await asset.load(.metadata)
        guard let item = metadata.first(where: { $0.commonKey == .commonKeyDescription }),
            let value = try await item.load(.stringValue), value.utf8.count <= 2048,
            value.hasPrefix("Audio tracks: ") else { return [] }
        let names = value.dropFirst("Audio tracks: ".count).components(separatedBy: ", ")
        guard names.count == count,
            Set(names).count == names.count, names.allSatisfy({ !$0.isEmpty && $0.utf8.count <= 96 })
        else { return [] }
        return names
    }

    nonisolated private static func work<Value: Sendable>(
        _ operation: @escaping @Sendable () async throws -> Value
    ) async throws -> Value {
        let worker = Task.detached(priority: .userInitiated, operation: operation)
        return try await withTaskCancellationHandler { try await worker.value } onCancel: { worker.cancel() }
    }
}
