import AppKit
import Observation
import SwiftUI
import UniformTypeIdentifiers

@MainActor
@Observable
final class CaptureExportState: NSObject, NSOpenSavePanelDelegate {
    var options: CaptureExportOptions
    private let document: CaptureDocument

    init(options: CaptureExportOptions, document: CaptureDocument) {
        self.options = options
        self.document = document
    }

    func panel(_ sender: Any, userEnteredFilename filename: String, confirmed: Bool) -> String? {
        guard confirmed else { return filename }
        return (try? options.validatedDimensions(for: document)) != nil ? filename : nil
    }

    func update(_ panel: NSSavePanel) {
        panel.allowedContentTypes = [UTType(options.format.identifier)!]
        let stem = (panel.nameFieldStringValue as NSString).deletingPathExtension
        panel.nameFieldStringValue = "\(stem).\(options.format.rawValue)"
    }
}

struct CaptureExportControls: View {
    @Bindable var state: CaptureExportState
    let document: CaptureDocument
    let panel: NSSavePanel
    @Environment(\.metrics) private var metrics

    var body: some View {
        Form {
            Picker("Format", selection: $state.options.format) {
                ForEach(CaptureRenderer.exportFormats, id: \.self) { Text($0.title).tag($0) }
            }
            Picker("Size", selection: $state.options.scale) {
                ForEach(CaptureExportOptions.Scale.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            if let size = try? state.options.dimensions(for: document) {
                LabeledContent("Pixels", value: "\(size.width) × \(size.height)")
            }
            if state.options.format == .webp {
                Picker("Compression", selection: $state.options.webPCompression) {
                    ForEach(CaptureExportOptions.WebPCompression.allCases, id: \.self) { Text($0.title).tag($0) }
                }
            }
            if state.options.showsQuality {
                Slider(value: $state.options.quality, in: 0.1...1) {
                    Text("Quality \(Int(state.options.quality * 100))%")
                }
            }
            Picker("Color", selection: $state.options.profile) {
                ForEach(CaptureExportOptions.Profile.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            if let message = validationMessage {
                Text(message).foregroundStyle(Theme.Colors.textSecondary)
            }
        }
        .formStyle(.columns)
        .padding(metrics.spacing.xl)
        .frame(width: metrics.size.dialogWidth)
        .onChange(of: state.options.format) { state.update(panel) }
    }

    private var validationMessage: String? {
        do { _ = try state.options.validatedDimensions(for: document); return nil } catch { return error.localizedDescription }
    }
}
