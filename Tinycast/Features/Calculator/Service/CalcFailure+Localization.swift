import Foundation

extension CalcFailure {
    func description(in bundle: Bundle = .main) -> String {
        switch self {
        case .incompatibleOperation(let operation, let first, let second):
            let operation = bundle.localizedString(forKey: operation, value: nil, table: nil)
            let first = bundle.localizedString(forKey: first, value: nil, table: nil)
            let second = bundle.localizedString(forKey: second, value: nil, table: nil)
            return String(localized: "Cannot \(operation) \(first) and \(second).", bundle: bundle)
        case .differentTemperatureUnits:
            return String(localized: "Cannot combine temperatures with different units.", bundle: bundle)
        case .unsupportedMultiplication:
            return String(localized: "Multiplication of these unit values is not supported.", bundle: bundle)
        case .unsupportedTemperatureDivision:
            return String(localized: "Division of temperature values is not supported.", bundle: bundle)
        case .differentDimensions:
            return String(localized: "Cannot compare values with different dimensions.", bundle: bundle)
        case .incompatibleConversion(let first, let second):
            let first = bundle.localizedString(forKey: first, value: nil, table: nil)
            let second = bundle.localizedString(forKey: second, value: nil, table: nil)
            return String(localized: "Cannot convert \(first) to \(second).", bundle: bundle)
        case .ratesUnavailable:
            return String(localized: "Exchange rates unavailable — check your connection.", bundle: bundle)
        case .missingRate(let code):
            return String(localized: "No exchange rate for \(code).", bundle: bundle)
        }
    }
}
