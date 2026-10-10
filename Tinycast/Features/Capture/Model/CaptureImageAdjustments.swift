import Foundation

struct CaptureImageAdjustments: Codable, Equatable, Sendable {
    var brightness = 0.0
    var contrast = 1.0
    var saturation = 1.0
    var sharpness = 0.0
    var inverted = false

    var isIdentity: Bool { self == Self() }
    var isValid: Bool {
        brightness.isFinite && (-1...1).contains(brightness)
            && contrast.isFinite && (0...2).contains(contrast)
            && saturation.isFinite && (0...2).contains(saturation)
            && sharpness.isFinite && (0...1).contains(sharpness)
    }
}
