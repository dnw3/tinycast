import Foundation

@main
nonisolated enum CaptureWebPHelper {
    static func main() {
        guard CommandLine.arguments.count == 3 else { exit(2) }
        do {
            let (request, image) = try CaptureWebPInput.read(from: URL(fileURLWithPath: CommandLine.arguments[1]))
            try CaptureWebPEncoder.write(image, to: URL(fileURLWithPath: CommandLine.arguments[2]),
                quality: request.quality, lossless: request.lossless)
        } catch { exit(1) }
    }
}
