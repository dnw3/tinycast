import CryptoKit
import Foundation

enum CaptureUploadSigner {
    nonisolated static func sign(
        _ request: inout URLRequest, hash: String, date: Date, region: String, accessKey: String, secret: String
    ) throws {
        guard let url = request.url, let host = url.host, let method = request.httpMethod else {
            throw CaptureUploadError.configuration
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        let timestamp = formatter.string(from: date), day = String(timestamp.prefix(8))
        request.setValue(timestamp, forHTTPHeaderField: "x-amz-date")
        request.setValue(hash, forHTTPHeaderField: "x-amz-content-sha256")
        request.setValue(host + (url.port.map { ":\($0)" } ?? ""), forHTTPHeaderField: "Host")
        let headers = (request.allHTTPHeaderFields ?? [:]).map { key, value in
            (key.lowercased(), value.split(whereSeparator: \.isWhitespace).joined(separator: " "))
        }.sorted { $0.0 < $1.0 }
        let names = headers.map(\.0).joined(separator: ";")
        let canonical = [method, url.path(percentEncoded: true), "",
            headers.map { "\($0.0):\($0.1)\n" }.joined(), names, hash].joined(separator: "\n")
        let scope = "\(day)/\(region)/s3/aws4_request"
        let signing = [day, region, "s3", "aws4_request"].reduce(Data("AWS4\(secret)".utf8)) { key, value in
            Data(HMAC<SHA256>.authenticationCode(for: Data(value.utf8), using: SymmetricKey(data: key)))
        }
        let string = "AWS4-HMAC-SHA256\n\(timestamp)\n\(scope)\n\(hex(SHA256.hash(data: Data(canonical.utf8))))"
        let signature = hex(HMAC<SHA256>.authenticationCode(for: Data(string.utf8), using: SymmetricKey(data: signing)))
        request.setValue("AWS4-HMAC-SHA256 Credential=\(accessKey)/\(scope), SignedHeaders=\(names), Signature=\(signature)",
            forHTTPHeaderField: "Authorization")
    }

    nonisolated static func hex(_ bytes: some Sequence<UInt8>) -> String {
        bytes.map { String(format: "%02x", $0) }.joined()
    }

    nonisolated static func path(_ value: String) -> String {
        value.utf8.map { byte in
            if (65...90).contains(byte) || (97...122).contains(byte) || (48...57).contains(byte)
                || [45, 46, 47, 95, 126].contains(byte) { String(UnicodeScalar(byte)) } else { String(format: "%%%02X", byte) }
        }.joined()
    }
}
