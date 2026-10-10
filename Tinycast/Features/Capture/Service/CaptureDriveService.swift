import CryptoKit
import Foundation

// Google returns private file links; creating a file never changes its sharing permissions.
enum CaptureDriveService {
    static let scope = "https://www.googleapis.com/auth/drive.file"

    nonisolated static func challenge(_ verifier: String) -> String {
        base64(Data(SHA256.hash(data: Data(verifier.utf8))))
    }

    nonisolated static func base64(_ data: Data) -> String {
        data.base64EncodedString().replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }

    nonisolated static func authorization(client: String, redirect: URL, verifier: String, state: String) -> URL {
        var url = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
        url.queryItems = [
            .init(name: "client_id", value: client), .init(name: "redirect_uri", value: redirect.absoluteString),
            .init(name: "response_type", value: "code"), .init(name: "scope", value: scope),
            .init(name: "code_challenge", value: challenge(verifier)), .init(name: "code_challenge_method", value: "S256"),
            .init(name: "state", value: state), .init(name: "access_type", value: "offline"),
            .init(name: "prompt", value: "consent")
        ]
        return url.url!
    }

    nonisolated static func callback(_ target: String, state: String) throws -> String? {
        guard target.utf8.count <= 8192, target.hasPrefix("/oauth/capture?"),
            let url = URLComponents(string: "http://127.0.0.1" + target), url.fragment == nil,
            let items = url.queryItems, items.filter({ $0.name == "state" }).count == 1,
            items.first(where: { $0.name == "state" })?.value == state else { return nil }
        if items.contains(where: { $0.name == "error" }) { throw CaptureUploadError.authorization }
        guard items.filter({ $0.name == "code" }).count == 1,
            let code = items.first(where: { $0.name == "code" })?.value, !code.isEmpty,
            code.utf8.count <= 4096 else { return nil }
        return code
    }

    nonisolated static func tokenRequest(_ fields: [String: String]) -> URLRequest {
        var request = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data(fields.sorted { $0.key < $1.key }.map {
            "\(CaptureUploadSigner.path($0.key))=\(CaptureUploadSigner.path($0.value).replacingOccurrences(of: "/", with: "%2F"))"
        }.joined(separator: "&").utf8)
        return request
    }

    nonisolated static func token(_ data: Data, response: HTTPURLResponse, refreshRequired: Bool) throws -> String {
        struct Token: Decodable {
            let access_token: String
            let refresh_token: String?
            let token_type: String
            let scope: String?
        }
        guard (200...299).contains(response.statusCode), let token = try? JSONDecoder().decode(Token.self, from: data),
            token.token_type.lowercased() == "bearer",
            token.scope == nil || token.scope!.split(separator: " ").contains(Substring(scope)),
            let value = refreshRequired ? token.refresh_token : token.access_token,
            !value.isEmpty, value.utf8.count <= 16_384, !value.contains(where: \.isWhitespace)
        else { throw CaptureUploadError.authorization }
        return value
    }

    nonisolated static func refresh(
        destination: CaptureUploadDestination, credential: CaptureUploadCredential,
        configuration: URLSessionConfiguration? = nil
    ) async throws -> String {
        var fields = ["client_id": destination.clientID, "refresh_token": credential.secret, "grant_type": "refresh_token"]
        if !credential.clientSecret.isEmpty { fields["client_secret"] = credential.clientSecret }
        let (data, response) = try await CaptureUploadTransport { _ in }.send(tokenRequest(fields), configuration: configuration)
        return try token(data, response: response, refreshRequired: false)
    }

    nonisolated static func prepare(
        file: URL, token: String, id: UUID, configuration: URLSessionConfiguration? = nil
    ) async throws -> CaptureUploadService.Prepared {
        let size = try file.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        let suffix = file.pathExtension.lowercased()
        guard let type = ["png": "image/png", "gif": "image/gif", "mp4": "video/mp4"][suffix],
            (1...2_000_000_000).contains(size) else { throw CaptureUploadError.unsupported }
        let name = "Capture-\(id.uuidString).\(suffix)"
        var request = URLRequest(url: URL(string:
            "https://www.googleapis.com/upload/drive/v3/files?uploadType=resumable&fields=id,webViewLink")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json; charset=UTF-8", forHTTPHeaderField: "Content-Type")
        request.setValue(type, forHTTPHeaderField: "X-Upload-Content-Type")
        request.setValue(String(size), forHTTPHeaderField: "X-Upload-Content-Length")
        request.httpBody = try JSONEncoder().encode(["name": name, "mimeType": type])
        let (_, response) = try await CaptureUploadTransport { _ in }.send(request, configuration: configuration)
        guard (200...299).contains(response.statusCode) else { throw CaptureUploadError.http(response.statusCode) }
        let session = try sessionURL(response.value(forHTTPHeaderField: "Location"))
        var upload = URLRequest(url: session)
        upload.httpMethod = "PUT"
        upload.setValue(type, forHTTPHeaderField: "Content-Type")
        upload.setValue(String(size), forHTTPHeaderField: "Content-Length")
        return .init(request: upload, file: file, result: nil, provider: .drive)
    }

    nonisolated static func sessionURL(_ value: String?) throws -> URL {
        guard let value, let url = URL(string: value), url.scheme == "https", url.host == "www.googleapis.com",
            url.port == nil || url.port == 443, url.user == nil, url.password == nil, url.fragment == nil,
            url.path == "/upload/drive/v3/files" else { throw CaptureUploadError.response }
        return url
    }

    nonisolated static func result(_ data: Data) throws -> URL {
        struct File: Decodable { let id: String; let webViewLink: String? }
        guard let file = try? JSONDecoder().decode(File.self, from: data), !file.id.isEmpty, file.id.count <= 256,
            file.id.utf8.allSatisfy({ (45...57).contains($0) && $0 != 46 && $0 != 47 || (65...90).contains($0)
                || $0 == 95 || (97...122).contains($0) }) else { throw CaptureUploadError.response }
        if let value = file.webViewLink, let link = URL(string: value), link.scheme == "https",
            link.host == "drive.google.com", link.user == nil, link.password == nil { return link }
        return URL(string: "https://drive.google.com/file/d/\(file.id)/view")!
    }
}
