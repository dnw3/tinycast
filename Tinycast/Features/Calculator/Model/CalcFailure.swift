import Foundation

enum CalcFailure: Equatable, Sendable {
    case incompatibleOperation(operation: String, first: String, second: String)
    case differentTemperatureUnits
    case unsupportedMultiplication
    case unsupportedTemperatureDivision
    case differentDimensions
    case incompatibleConversion(first: String, second: String)
    case ratesUnavailable
    case missingRate(String)
}
