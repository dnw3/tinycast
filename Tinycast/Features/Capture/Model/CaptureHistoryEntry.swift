import Foundation

struct CaptureHistoryEntry: Codable, Sendable, Identifiable {
    let id: UUID
    let date: Date
    let size: CapturePixelSize
    let editable: Bool
    let draft: Bool
    let bytes: Int
    var videoDuration: Double?
    var animationDuration: Double?
    var title: String { "\(size.width) × \(size.height)" }
    var filename: String {
        if animationDuration != nil { return "animation.gif" }
        return videoDuration == nil ? "image.png" : "video.mp4"
    }
    var subtitle: String {
        if let animationDuration {
            return "GIF · \(Duration.seconds(animationDuration).formatted(.time(pattern: .minuteSecond)))"
        }
        if let videoDuration {
            let time = Duration.seconds(videoDuration).formatted(.time(pattern: .minuteSecond))
            return "\(draft ? "Video draft" : "Video") · \(time)"
        }
        return draft ? "Editable draft" : editable ? "Editable original" : "Flattened image"
    }
}
