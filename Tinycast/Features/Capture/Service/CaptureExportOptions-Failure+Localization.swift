import Foundation

extension CaptureExportOptions.Failure: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .encodingBudget: String(localized: "Choose original-size PNG in sRGB, or reduce the export size to 4 million pixels.")
        case .webPDimensions: String(localized: "WebP supports up to 16,383 pixels per side. Choose PNG, or reduce the export size.")
        case .quality: String(localized: "Choose an export quality between 0 and 100%.")
        }
    }
}
