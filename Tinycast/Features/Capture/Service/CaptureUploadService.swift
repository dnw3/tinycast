import CryptoKit
import Foundation

enum CaptureUploadService {
    struct Prepared: Sendable {
        let request: URLRequest
        let file: URL
        let result: URL?
        var temporary = false
        var provider = CaptureUploadDestination.Kind.s3
    }

    nonisolated static func prepare(
        file: URL, destination: CaptureUploadDestination, credential: CaptureUploadCredential,
        scratch: URL, id: UUID, date: Date
    ) throws -> Prepared {
        let destination = try destination.validated()
        guard destination.kind != .drive else { throw CaptureUploadError.configuration }
        guard !credential.secret.isEmpty, credential.secret.utf8.count <= 16_384,
            !credential.secret.contains(where: \.isNewline),
            credential.sessionToken.utf8.count <= 16_384,
            !credential.sessionToken.contains(where: \.isNewline)
        else { throw CaptureUploadError.credential }
        let size = try file.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        let types = ["png": "image/png", "gif": "image/gif", "mp4": "video/mp4"]
        let suffix = file.pathExtension.lowercased()
        guard let type = types[suffix], (1...2_000_000_000).contains(size) else { throw CaptureUploadError.unsupported }
        let name = "Capture-\(id.uuidString).\(suffix)"
        if destination.kind == .imgbb {
            guard suffix != "mp4", size <= 32_000_000 else { throw CaptureUploadError.unsupported }
            let boundary = "tinycast-\(id.uuidString)", body = scratch.appendingPathComponent("\(id).upload")
            let head = "--\(boundary)\r\nContent-Disposition: form-data; name=\"image\"; filename=\"\(name)\"\r\n"
                + "Content-Type: \(type)\r\n\r\n"
            try multipart(file, to: body, head: head, tail: "\r\n--\(boundary)--\r\n")
            var endpoint = URLComponents(string: "https://api.imgbb.com/1/upload")!
            endpoint.queryItems = [.init(name: "key", value: credential.secret)]
            var request = URLRequest(url: endpoint.url!)
            request.httpMethod = "POST"
            request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
            return Prepared(request: request, file: body, result: nil, temporary: true, provider: .imgbb)
        }
        let prefix = destination.prefix.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let key = (prefix.isEmpty ? "" : prefix + "/") + name
        guard var url = CaptureUploadDestination.endpoint(destination.endpoint) else { throw CaptureUploadError.configuration }
        let base = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        url.percentEncodedPath = CaptureUploadSigner.path(
            (base.isEmpty ? "" : "/" + base) + "/" + destination.bucket + "/" + key)
        guard let target = url.url else { throw CaptureUploadError.configuration }
        var request = URLRequest(url: target)
        request.httpMethod = "PUT"
        request.setValue(type, forHTTPHeaderField: "Content-Type")
        if !credential.sessionToken.isEmpty {
            request.setValue(credential.sessionToken, forHTTPHeaderField: "x-amz-security-token")
        }
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        var hash = SHA256()
        while let data = try handle.read(upToCount: 65_536), !data.isEmpty {
            try Task.checkCancellation()
            hash.update(data: data)
        }
        try CaptureUploadSigner.sign(&request, hash: CaptureUploadSigner.hex(hash.finalize()), date: date,
            region: destination.region, accessKey: destination.accessKey, secret: credential.secret)
        var result = target
        if var publicURL = CaptureUploadDestination.endpoint(destination.publicBase) {
            let path = publicURL.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            publicURL.percentEncodedPath = CaptureUploadSigner.path((path.isEmpty ? "" : "/" + path) + "/" + key)
            guard let link = publicURL.url else { throw CaptureUploadError.configuration }
            result = link
        }
        return Prepared(request: request, file: file, result: result)
    }

    nonisolated static func result(_ data: Data, response: HTTPURLResponse, prepared: Prepared) throws -> URL {
        guard (200...299).contains(response.statusCode) else { throw CaptureUploadError.http(response.statusCode) }
        if prepared.provider == .drive { return try CaptureDriveService.result(data) }
        if let result = prepared.result { return result }
        struct Reply: Decodable { struct Value: Decodable { let url: String }; let success: Bool; let data: Value }
        guard let reply = try? JSONDecoder().decode(Reply.self, from: data), reply.success,
            let url = URL(string: reply.data.url), url.scheme == "https", url.host != nil,
            url.user == nil, url.password == nil else { throw CaptureUploadError.response }
        return url
    }

    nonisolated private static func multipart(_ file: URL, to output: URL, head: String, tail: String) throws {
        guard FileManager.default.createFile(atPath: output.path, contents: nil, attributes: [.posixPermissions: 0o600]) else {
            throw CocoaError(.fileWriteUnknown)
        }
        var completed = false
        defer { if !completed { try? FileManager.default.removeItem(at: output) } }
        let source = try FileHandle(forReadingFrom: file), target = try FileHandle(forWritingTo: output)
        defer { try? source.close(); try? target.close() }
        try target.write(contentsOf: Data(head.utf8))
        while let data = try source.read(upToCount: 65_536), !data.isEmpty {
            try Task.checkCancellation()
            try target.write(contentsOf: data)
        }
        try target.write(contentsOf: Data(tail.utf8))
        completed = true
    }
}
