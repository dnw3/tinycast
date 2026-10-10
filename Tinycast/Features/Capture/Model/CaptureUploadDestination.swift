import Foundation

struct CaptureUploadDestination: Codable, Equatable, Identifiable, Sendable {
    enum Kind: String, Codable, CaseIterable, Sendable {
        case s3, imgbb, drive
        var title: String {
            switch self {
            case .s3: "S3 / R2 / MinIO"
            case .imgbb: "imgbb"
            case .drive: "Google Drive"
            }
        }
    }

    var id = UUID()
    var kind = Kind.s3
    var name = ""
    var endpoint = ""
    var bucket = ""
    var region = "auto"
    var prefix = ""
    var publicBase = ""
    var accessKey = ""
    var clientID = ""

    var title: String { name.isEmpty ? kind.title : name }

    func validated() throws -> Self {
        guard name.count <= 100 else { throw CaptureUploadError.configuration }
        if kind == .s3 {
            guard Self.endpoint(endpoint) != nil, Self.segment(bucket), Self.segment(region),
                !accessKey.isEmpty, accessKey.count <= 256,
                !accessKey.contains(where: { $0.isWhitespace || $0 == "/" }),
                prefix.count <= 1024, !prefix.contains(where: { $0.isNewline }),
                prefix.split(separator: "/").allSatisfy({ $0 != "." && $0 != ".." }),
                publicBase.isEmpty || Self.endpoint(publicBase) != nil
            else { throw CaptureUploadError.configuration }
        } else if kind == .drive {
            guard clientID.hasSuffix(".apps.googleusercontent.com"), clientID.count <= 256,
                clientID.utf8.allSatisfy({ (45...57).contains($0) && $0 != 47 || (97...122).contains($0) })
            else { throw CaptureUploadError.configuration }
        }
        return self
    }

    static func endpoint(_ value: String) -> URLComponents? {
        guard let url = URLComponents(string: value), url.scheme == "https", let host = url.host, !host.isEmpty,
            url.user == nil, url.password == nil, url.query == nil, url.fragment == nil
        else { return nil }
        return url
    }

    private static func segment(_ value: String) -> Bool {
        !value.isEmpty && value.utf8.count <= 255 && value != "." && value != ".."
            && value.utf8.allSatisfy { (45...57).contains($0) && $0 != 47 || (65...90).contains($0) || (97...122).contains($0) }
    }
}

struct CaptureUploadCredential: Codable, Sendable {
    var secret = ""
    var sessionToken = ""
    var clientSecret = ""
}

enum CaptureUploadError: LocalizedError {
    case configuration, credential, unsupported, response, responseLimit, authorization, http(Int)
    var errorDescription: String? {
        switch self {
        case .configuration: "Check the destination settings. Google Drive needs a Desktop OAuth client ID."
        case .credential: "Add an upload credential in Capture settings."
        case .unsupported: "This destination does not accept the file type or size. imgbb accepts images up to 32 MB."
        case .response: "The upload destination returned an invalid response. The local file is safe."
        case .responseLimit: "The upload response exceeded its size limit. The local file is safe."
        case .authorization: "Google Drive sign-in did not finish. Reconnect in Capture settings and retry."
        case .http(let status): "Upload failed (HTTP \(status)). Check the destination and its credentials."
        }
    }
}
