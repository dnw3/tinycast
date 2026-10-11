import Foundation

extension CapturePresentationPreset.Failure: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .name: String(localized: "Use a preset name of 1–40 characters without control characters.")
        case .style: String(localized: "The styling parameters are outside the supported range.")
        case .limit: String(localized: "Keep up to 20 custom presets. Remove one before saving another.")
        case .duplicate: String(localized: "A preset with this name already exists. Replace it or choose another name.")
        case .missing: String(localized: "This preset was removed. Save the style as a new preset.")
        }
    }
}
