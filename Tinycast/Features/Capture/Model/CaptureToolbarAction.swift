import Foundation

enum CaptureToolbarAction: String, Codable, CaseIterable, Sendable {
    case copy, save, scroll, record, pin, recognize, translate, share, upload

    static let standard: Set<Self> = [.copy, .save, .scroll, .pin, .recognize, .translate]

    var title: String {
        switch self {
        case .copy: "Copy"
        case .save: "Save As…"
        case .scroll: "Scroll Capture"
        case .record: "Record Screen"
        case .pin: "Pin"
        case .recognize: "Extract Text"
        case .translate: "Translate"
        case .share: "Share"
        case .upload: "Upload"
        }
    }

    var symbol: String {
        switch self {
        case .copy: "doc.on.doc"
        case .save: "square.and.arrow.down"
        case .scroll: "scroll"
        case .record: "record.circle"
        case .pin: "pin"
        case .recognize: "text.viewfinder"
        case .translate: "translate"
        case .share: "square.and.arrow.up"
        case .upload: "icloud.and.arrow.up"
        }
    }

    var needsSelection: Bool { self == .scroll || self == .record }
}
