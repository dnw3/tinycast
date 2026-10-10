import Foundation

class UploadFixtureProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool {
        ["upload.invalid", "www.googleapis.com", "oauth2.googleapis.com"].contains(request.url?.host ?? "")
    }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        if request.url?.host == "oauth2.googleapis.com" {
            precondition(request.httpMethod == "POST")
            reply(200, body: "{\"access_token\":\"access-fixture\",\"token_type\":\"Bearer\"}")
            return
        }
        if request.url?.host == "www.googleapis.com" {
            if request.httpMethod == "POST" {
                precondition(request.value(forHTTPHeaderField: "Authorization") == "Bearer access-fixture")
                precondition(request.httpBody?.range(of: Data("parents".utf8)) == nil)
                reply(200, headers: ["Location": "https://www.googleapis.com/upload/drive/v3/files?upload_id=fixture"])
            } else {
                precondition(request.httpMethod == "PUT" && request.value(forHTTPHeaderField: "Authorization") == nil)
                reply(200, body: "{\"id\":\"test-file_42\"}")
            }
            return
        }
        let path = request.url!.lastPathComponent
        guard path != "waiting" else { return }
        let response = HTTPURLResponse(url: request.url!, statusCode: path == "denied" ? 403 : 200,
            httpVersion: "HTTP/1.1", headerFields: [:])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: path == "large" ? Data(repeating: 7, count: 65_537) : Data("ok".utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() { }
    private func reply(_ status: Int, headers: [String: String] = [:], body: String = "") {
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
}

@main
struct CaptureUploadTests {
    static func expect(_ value: Bool, _ message: String) { precondition(value, message) }

    static func main() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("capture-upload-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("final.png"), payload = Data([0, 1, 2, 255, 128])
        try payload.write(to: file)
        try signature()
        var destination = CaptureUploadDestination()
        destination.endpoint = "https://storage.example.com:8443/base"
        destination.bucket = "capture"; destination.region = "us-east-1"
        destination.prefix = "QA 日本語/a b"; destination.accessKey = "EXAMPLE"
        destination.publicBase = "https://cdn.example.com/images"
        let id = UUID(), date = Date(timeIntervalSince1970: 1_369_353_600)
        let prepared = try CaptureUploadService.prepare(file: file, destination: destination,
            credential: .init(secret: "test-secret", sessionToken: "test-session"), scratch: root, id: id, date: date)
        expect(prepared.file == file && !prepared.temporary, "S3 streams the rendered file")
        expect(prepared.request.url?.port == 8443, "Signing includes explicit ports")
        expect(prepared.request.url!.absoluteString.contains("QA%20%E6%97%A5%E6%9C%AC%E8%AA%9E/a%20b"), "UTF8 path encoding")
        expect(prepared.request.value(forHTTPHeaderField: "x-amz-security-token") == "test-session", "Temporary credentials")
        expect(prepared.request.value(forHTTPHeaderField: "x-amz-acl") == nil, "Upload does not make objects public")
        expect(prepared.result!.host == "cdn.example.com", "Configured link base")
        for endpoint in ["http://example.com", "https://user:password@example.com", "https://example.com?a=1",
            "https://example.com/#x"] {
            destination.endpoint = endpoint
            expect((try? destination.validated()) == nil, "Invalid destination must fail before credential delivery")
        }
        destination.kind = .imgbb
        let form = try CaptureUploadService.prepare(file: file, destination: destination,
            credential: .init(secret: "test-api-key"), scratch: root, id: id, date: date)
        let body = try Data(contentsOf: form.file)
        expect(form.temporary && body.range(of: payload) != nil, "Multipart includes exact final bytes")
        expect(form.request.url?.query == "key=test-api-key", "imgbb API key parameter")
        expect(body.range(of: Data("test-api-key".utf8)) == nil, "No credential written into the scratch upload file")
        let response = HTTPURLResponse(url: form.request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        let link = try CaptureUploadService.result(Data("{\"success\":true,\"data\":{\"url\":\"https://i.example/a.png\"}}".utf8),
            response: response, prepared: form)
        expect(link.absoluteString == "https://i.example/a.png", "Provider URL is returned")
        expect((try? CaptureUploadService.result(Data("{\"success\":true,\"data\":{\"url\":\"file:///tmp/a\"}}".utf8),
            response: response, prepared: form)) == nil, "Invalid provider URL rejected")
        try await transport(file: file)
        try await drive(file: file)
        try await callback()
        for _ in 0..<100 { try await cancelledCallback() }
        print("Upload signing, UTF8 paths, private ACL, multipart bytes, response limits and cancellation passed")
    }

    static func drive(file: URL) async throws {
        expect(CaptureDriveService.challenge("dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk")
            == "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM", "RFC 7636 PKCE S256 vector")
        for target in ["/other?state=ok&code=x", "/oauth/capture?state=wrong&code=x",
            "/oauth/capture?state=ok&state=ok&code=x", "/oauth/capture?state=ok&code=x&code=y"] {
            expect(try CaptureDriveService.callback(target, state: "ok") == nil, "Reject callback route/state ambiguity")
        }
        expect(try CaptureDriveService.callback("/oauth/capture?state=ok&code=a%2Bb%2Fc", state: "ok") == "a+b/c",
            "Preserve opaque authorization code")
        let request = CaptureDriveService.tokenRequest(["code": "a+b/c?d=&", "client_id": "fixture"])
        expect(String(data: request.httpBody!, encoding: .utf8) == "client_id=fixture&code=a%2Bb%2Fc%3Fd%3D%26",
            "Form encoding cannot inject OAuth fields")
        for value in ["http://www.googleapis.com/upload/drive/v3/files", "https://evil.example/upload/drive/v3/files",
            "https://user@www.googleapis.com/upload/drive/v3/files", "https://www.googleapis.com/token",
            "https://www.googleapis.com:8443/upload/drive/v3/files"] {
            expect((try? CaptureDriveService.sessionURL(value)) == nil, "Session target must stay on Drive HTTPS origin")
        }
        var destination = CaptureUploadDestination()
        destination.kind = .drive; destination.clientID = "123-fixture.apps.googleusercontent.com"
        _ = try destination.validated()
        let token = try await CaptureDriveService.refresh(destination: destination, credential: .init(secret: "refresh-fixture"),
            configuration: configuration())
        let prepared = try await CaptureDriveService.prepare(file: file, token: token, id: UUID(), configuration: configuration())
        expect(prepared.file == file && !prepared.temporary, "Drive streams the final file without a second copy")
        let (data, response) = try await CaptureUploadTransport { _ in }.upload(prepared.request, file: file,
            configuration: configuration())
        let link = try CaptureUploadService.result(data, response: response, prepared: prepared)
        expect(link.absoluteString == "https://drive.google.com/file/d/test-file_42/view", "Private Drive file link")
    }

    static func callback() async throws {
        let (ready, continuation) = AsyncStream<URL>.makeStream(bufferingPolicy: .bufferingNewest(1))
        defer { continuation.finish() }
        async let received = CaptureDriveAuthorization.receive(state: "fixture-state", timeout: .seconds(10)) {
            continuation.yield($0); return true
        }
        let session = URLSession(configuration: .ephemeral)
        defer { session.invalidateAndCancel() }
        for await url in ready {
            expect(url.host == "127.0.0.1" && url.port != nil, "Only random loopback endpoint is exposed")
            let (_, bad) = try await session.data(from: URL(string: url.absoluteString + "?state=wrong&code=ignored")!)
            expect((bad as? HTTPURLResponse)?.statusCode == 400, "Wrong-state callback does not finish authorization")
            let valid = URL(string: url.absoluteString + "?state=fixture-state&code=accepted")!
            let (body, good) = try await session.data(from: valid)
            expect((good as? HTTPURLResponse)?.statusCode == 200, "Loopback valid callback accepted")
            expect(body.range(of: Data("accepted".utf8)) == nil, "HTML never reflects authorization code")
            break
        }
        let (code, _) = try await received
        expect(code == "accepted", "Validated callback returned")
    }

    static func cancelledCallback() async throws {
        let (ready, continuation) = AsyncStream<URL>.makeStream(bufferingPolicy: .bufferingNewest(1))
        defer { continuation.finish() }
        let task = Task {
            try await CaptureDriveAuthorization.receive(state: "cancel", timeout: .seconds(5)) {
                continuation.yield($0); return true
            }
        }
        for await _ in ready { break }
        let start = ContinuousClock.now
        task.cancel()
        do {
            _ = try await task.value; expect(false, "Cancelled authorization cannot return a code")
        } catch is CancellationError { }
        expect(start.duration(to: .now) < .seconds(2), "Cancel closes the authorization listener promptly")
    }

    static func signature() throws {
        var request = URLRequest(url: URL(string: "https://examplebucket.s3.amazonaws.com/test%24file.text")!)
        request.httpMethod = "PUT"
        request.setValue("Fri, 24 May 2013 00:00:00 GMT", forHTTPHeaderField: "Date")
        request.setValue("REDUCED_REDUNDANCY", forHTTPHeaderField: "x-amz-storage-class")
        try CaptureUploadSigner.sign(&request,
            hash: "44ce7dd67c959e0d3524ffac1771dfbba87d2b6b4b4e99e42034a8b803f8b072",
            date: Date(timeIntervalSince1970: 1_369_353_600), region: "us-east-1", accessKey: "AKIAIOSFODNN7EXAMPLE",
            secret: "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY")
        expect(request.value(forHTTPHeaderField: "Authorization")?.hasSuffix(
            "Signature=98ad721746da40c64f1a55b78f14c238d841ea1380cd77a1b5971af0ece108bd") == true,
            "AWS published PUT signing vector")
    }

    static func configuration() -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [UploadFixtureProtocol.self]
        return configuration
    }

    static func transport(file: URL) async throws {
        for path in ["success", "denied", "large"] {
            var request = URLRequest(url: URL(string: "https://upload.invalid/\(path)")!)
            request.httpMethod = "PUT"
            do {
                let (body, response) = try await CaptureUploadTransport { _ in }.upload(request, file: file,
                    configuration: configuration())
                expect(path != "large", "Response limit must stop upload task")
                expect(body == Data("ok".utf8), "Response bytes")
                expect(response.statusCode == (path == "denied" ? 403 : 200), "HTTP status retained")
            } catch CaptureUploadError.responseLimit { expect(path == "large", "Only oversized response rejected") }
        }
        let request = URLRequest(url: URL(string: "https://upload.invalid/waiting")!)
        let task = Task { try await CaptureUploadTransport { _ in }.upload(request, file: file, configuration: configuration()) }
        try await Task.sleep(for: .milliseconds(50))
        let start = ContinuousClock.now
        task.cancel()
        do { _ = try await task.value; expect(false, "Cancellation must throw") } catch is CancellationError { }
        expect(start.duration(to: .now) < .seconds(2), "Cancellation finishes promptly")
    }
}
