import Foundation

struct CapturePreferences: Codable, Equatable, Sendable {
    var enabled = true
    var closeAfterCopy = true
    var includesCursor = false
    var format = "png"
    var axis: CaptureDocument.Axis = .vertical
    var retentionDays = 7
    var maximumHistoryMB = 512
    var scrollSpeed = 1
}
