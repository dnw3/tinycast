import Foundation

@main
nonisolated enum TextRecognitionHelper {
    static func main() async {
        guard CommandLine.arguments.count == 3,
            ["image", "pdf", "capture", "foreground"].contains(CommandLine.arguments[1])
        else { exit(2) }
        do {
            if CommandLine.arguments[1] == "foreground" {
                _ = try await ForegroundExtractor.mask(at: URL(fileURLWithPath: CommandLine.arguments[2]))
                try FileHandle.standardOutput.write(contentsOf: Data("ok".utf8))
                return
            }
            if CommandLine.arguments[1] == "capture" {
                let result = try await TextRecognitionExtractor.capture(
                    at: URL(fileURLWithPath: CommandLine.arguments[2]))
                try FileHandle.standardOutput.write(contentsOf: JSONEncoder().encode(result))
                return
            }
            let text = try await TextRecognitionExtractor.extract(
                at: URL(fileURLWithPath: CommandLine.arguments[2]),
                isPDF: CommandLine.arguments[1] == "pdf")
            try FileHandle.standardOutput.write(contentsOf: Data(text.utf8))
        } catch {
            exit(1)
        }
    }
}
