import Foundation

@main
struct LocalizationTests {
    static func main() throws {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let scratch = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: scratch) }
        let compiler = Process()
        compiler.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        compiler.arguments = [
            "xcstringstool", "compile", root.appendingPathComponent("Tinycast/Resources/Localizable.xcstrings").path,
            "--output-directory", scratch.path
        ]
        try compiler.run()
        compiler.waitUntilExit()
        precondition(compiler.terminationStatus == 0, "String Catalog must compile")
        let chinese = Bundle(url: scratch.appendingPathComponent("zh-Hans.lproj"))!
        let english = Bundle(url: scratch.appendingPathComponent("en.lproj"))!
        precondition(chinese.localizedString(forKey: "Save As…", value: nil, table: nil) == "另存为…")
        precondition(chinese.localizedString(forKey: "Scroll Capture", value: nil, table: nil) == "长截图")
        let userText = "My note 保存 Original.png"
        precondition(chinese.localizedString(forKey: userText, value: nil, table: nil) == userText)
        let count = 2
        let one = 1
        precondition(String(localized: "\(count) items", bundle: chinese, locale: Locale(identifier: "zh-Hans")) == "2 项")
        precondition(String(localized: "\(one) items", bundle: english, locale: Locale(identifier: "en")) == "1 item")
        precondition(String(localized: "\(count) items", bundle: english, locale: Locale(identifier: "en")) == "2 items")
        precondition(String(localized: "Imported \(one) extensions.", bundle: english,
            locale: Locale(identifier: "en")) == "Imported 1 extension.")
        let owner = "author"
        let repository = "sample"
        let folder = "src"
        let branch = "main"
        precondition(String(localized: "\(owner)/\(repository) has no \(folder) folder at \(branch).",
            bundle: chinese, locale: Locale(identifier: "zh-Hans")) == "author/sample 在 main 中没有 src 文件夹。")
        precondition(CalcFailure.incompatibleConversion(first: "Length", second: "Currency")
            .description(in: chinese) == "无法将长度转换为货币。")
        let invalidConfiguration = SettingsFileJSON.object([.init(key: "User Name 保存", value: .bool(false))])
        let configuration = LauncherFileFormat.records(from: invalidConfiguration,
            locale: Locale(identifier: "zh-Hans"), bundle: .atURL(chinese.bundleURL), current: { _ in .init() })!
        precondition(String(localized: configuration.problems[0]) == "“User Name 保存”需要对象")
        let chineseResults = SettingsSearchCatalog.results(for: "截图", bundle: chinese)
        precondition(chineseResults.contains { $0.tab == .capture }, "Chinese Settings search must find Capture")
        let title = "Enable Capture"
        let translated = SettingsSearchCatalog.results(for: "启用截图", bundle: chinese)
        precondition(translated.contains { $0.target == .row(.captureCapture, title) })
        precondition(SettingsSearchCatalog.results(for: title, bundle: chinese).contains {
            $0.target == .row(.captureCapture, title)
        }, "English search must still find the same stable target")
        print("PASS: compiled Chinese/English resources, plural rules, fallback and stable bilingual search")
    }
}
