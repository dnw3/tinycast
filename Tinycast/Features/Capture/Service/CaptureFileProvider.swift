import Foundation
import UniformTypeIdentifiers

enum CaptureFileProvider {
    nonisolated static func make(_ entry: CaptureHistoryEntry, repository: CaptureRepository) -> NSItemProvider {
        let provider = NSItemProvider()
        let type: UTType = entry.animationDuration != nil ? .gif : entry.videoDuration != nil ? .mpeg4Movie : .png
        provider.suggestedName = entry.filename
        provider.registerFileRepresentation(forTypeIdentifier: type.identifier, visibility: .all) { completion in
            let progress = Progress(totalUnitCount: 1)
            let worker = Task.detached(priority: .userInitiated) {
                do {
                    try Task.checkCancellation()
                    let source = try repository.openFile(entry, id: UUID())
                    try Task.checkCancellation()
                    withExtendedLifetime(source) {
                        completion(source.directory.appendingPathComponent(entry.filename), false, nil)
                    }
                    progress.completedUnitCount = 1
                } catch { completion(nil, false, error) }
            }
            progress.cancellationHandler = { worker.cancel() }
            return progress
        }
        return provider
    }
}
