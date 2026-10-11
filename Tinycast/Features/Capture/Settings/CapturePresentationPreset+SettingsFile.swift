import Foundation

extension CapturePresentationPreset: SettingsFileValue {
    init?(settingsJSON json: SettingsFileJSON) {
        guard let id = json["id"]?.string.flatMap(UUID.init(uuidString:)), let name = json["name"]?.string,
            let style = json["style"], let background = style["background"]?.string,
            let kind = CapturePresentation.Background(rawValue: background),
            let color = style["color"]?.string.flatMap(CaptureColor.init(hex:)),
            let secondary = style["secondary"]?.string.flatMap(CaptureColor.init(hex:)),
            let padding = style["padding"]?.number, let radius = style["radius"]?.number,
            let shadow = style["shadow"]?.number, let windowFrame = style["windowFrame"]?.bool
        else { return nil }
        self.init(id: id, name: name, presentation: .init(background: kind, color: color, secondary: secondary,
            padding: padding, radius: radius, shadow: shadow, windowFrame: windowFrame))
        guard isValid else { return nil }
    }

    var settingsJSON: SettingsFileJSON {
        .object([
            "id": .string(id.uuidString), "name": .string(name),
            "style": .object([
                "background": .string(presentation.background.rawValue), "color": .string(presentation.color.hex),
                "secondary": .string(presentation.secondary.hex), "padding": .number(presentation.padding),
                "radius": .number(presentation.radius), "shadow": .number(presentation.shadow),
                "windowFrame": .bool(presentation.windowFrame)
            ])
        ])
    }
}

extension CaptureSettingsStore {
    var presentationPresetsBinding: SettingsFileBinding {
        SettingsFileBinding(.capturePresentationPresets, read: { self.presentationPresets.settingsJSON }, write: { json in
            guard let count = json.items?.count, count <= 20,
                let presets = [CapturePresentationPreset](settingsJSON: json), self.replacePresentationPresets(presets)
            else { return [.invalidValue(.capturePresentationPresets)] }
            return []
        })
    }
}
