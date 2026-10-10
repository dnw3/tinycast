enum CaptureCopyPolicy {
    static let maximumEncodedBytes = 8_000_000

    static func accepts(encodedBytes: Int) -> Bool {
        (1...maximumEncodedBytes).contains(encodedBytes)
    }
}
