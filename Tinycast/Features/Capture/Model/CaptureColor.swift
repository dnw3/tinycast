import Foundation

struct CaptureColor: Codable, Equatable, Sendable {
    var red: UInt8
    var green: UInt8
    var blue: UInt8

    var rgba: [Double] { [Double(red) / 255, Double(green) / 255, Double(blue) / 255, 1] }
    var hex: String { String(format: "#%02X%02X%02X", red, green, blue) }

    init(red: UInt8, green: UInt8, blue: UInt8) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    init?(hex: String) {
        let value = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        let digits = value.hasPrefix("#") ? String(value.dropFirst()) : value
        guard digits.utf8.count == 6, digits.utf8.allSatisfy({
            (48...57).contains($0) || (65...70).contains($0) || (97...102).contains($0)
        }), let number = UInt32(digits, radix: 16) else { return nil }
        self.init(red: UInt8(number >> 16), green: UInt8((number >> 8) & 255), blue: UInt8(number & 255))
    }
}
