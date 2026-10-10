import Foundation

enum CaptureToolbarItem: Codable, Hashable, Sendable {
    case annotation(CaptureAnnotation.Tool)
    case pickColor, scanCodes, addImage, suggestCovers, adjustImage, beautify

    static let all: [Self] = CaptureAnnotation.Tool.allCases.map(Self.annotation)
        + [.pickColor, .scanCodes, .addImage, .suggestCovers, .adjustImage, .beautify]
    static let standard = Set(CaptureAnnotation.Tool.allCases.filter { !$0.advanced }.map(Self.annotation))

    var title: String {
        switch self {
        case let .annotation(tool): tool.title
        case .pickColor: "Pick Color"
        case .scanCodes: "Scan QR Codes"
        case .addImage: "Add Image"
        case .suggestCovers: "Suggest Covers"
        case .adjustImage: "Adjust Image"
        case .beautify: "Beautify"
        }
    }

    var symbol: String {
        switch self {
        case let .annotation(tool): tool.symbol
        case .pickColor: "eyedropper"
        case .scanCodes: "qrcode.viewfinder"
        case .addImage: "photo.badge.plus"
        case .suggestCovers: "eye.slash"
        case .adjustImage: "slider.horizontal.below.rectangle"
        case .beautify: "photo.artframe"
        }
    }
}
