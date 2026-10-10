import Foundation

struct CaptureVideoEdit: Codable, Equatable, Sendable {
    var start: Double = 0
    var end: Double
    var speed: Double = 1
    var volume: Double = 1
    var cuts: [Range] = []
    var holds: [Hold] = []
    var effects: [CaptureVideoEffect] = []
    var trackVolumes: [Int: Double] = [:]

    struct Range: Codable, Equatable, Sendable {
        var start: Double
        var end: Double
    }

    struct Hold: Codable, Equatable, Sendable {
        var position: Double
        var duration: Double
    }

    var duration: Double { CaptureVideoTimeline(self).duration }

    func validated(duration: Double) throws -> Self {
        guard duration.isFinite, duration > 0, start.isFinite, end.isFinite,
            speed.isFinite, volume.isFinite, start >= 0, end <= duration,
            end - start >= min(0.1, duration), (0.25...4).contains(speed), (0...1).contains(volume),
            cuts.count <= 64, holds.count <= 64, effects.count <= 64,
            Set(effects.map(\.id)).count == effects.count,
            effects.allSatisfy({ $0.isValid(duration: duration) }),
            trackVolumes.count <= 16,
            trackVolumes.allSatisfy({ (0..<16).contains($0.key) && $0.value.isFinite && (0...1).contains($0.value) }),
            cuts.allSatisfy({ $0.start.isFinite && $0.end.isFinite && $0.start >= 0
                && $0.end <= duration && $0.end - $0.start >= 0.01 }),
            holds.allSatisfy({ $0.position.isFinite && $0.duration.isFinite && $0.position >= 0
                && $0.position < duration && (0.1...30).contains($0.duration) })
        else { throw CaptureVideoError.invalidConfiguration }
        let sorted = cuts.sorted { $0.start < $1.start }
        let zooms = effects.filter { $0.kind == .zoom }.sorted { $0.start < $1.start }
        guard zip(sorted, sorted.dropFirst()).allSatisfy({ $0.end <= $1.start }),
            zip(zooms, zooms.dropFirst()).allSatisfy({ $0.end <= $1.start }),
            Set(holds.map(\.position)).count == holds.count,
            self.duration >= min(0.1, duration / speed), self.duration <= 28_800
        else { throw CaptureVideoError.invalidConfiguration }
        return self
    }
}
