import SwiftUI

struct CapturePresentationPresets: View {
    let state: CaptureEditorState
    @Environment(CaptureCoordinator.self) private var coordinator
    @Environment(\.metrics) private var metrics
    @State private var naming = false
    @State private var name = ""

    private var style: CapturePresentation { state.document.edit.presentation ?? .init() }

    var body: some View {
        Menu("Presets") {
            ForEach(CapturePresentationPreset.BuiltIn.allCases, id: \.self) { preset in
                Button(preset.title) { apply(preset.presentation) }
            }
            if !coordinator.settings.presentationPresets.isEmpty {
                Divider()
                ForEach(coordinator.settings.presentationPresets) { preset in
                    Menu(preset.name) {
                        Button("Apply") { apply(preset.presentation) }
                        Button("Replace with Current Style") { save(name: preset.name, replacing: preset.id) }
                        Button("Delete Preset", role: .destructive) {
                            coordinator.settings.removePresentationPreset(preset.id)
                        }
                    }
                }
            }
            Divider()
            Button("Save Current Style…") { naming = true }
        }.fixedSize().focusable(false).accessibilityLabel(String(localized: "Styling Presets"))
        if naming {
            TextField("Preset Name", text: $name)
                .frame(width: metrics.scaled(Theme.Size.capturePropertyField * 3))
                .captureField(metrics)
                .onSubmit { save(name: name) }.accessibilityLabel(String(localized: "Preset Name"))
            CaptureIconButton(title: String(localized: "Save Preset"), symbol: "plus") { save(name: name) }
            CaptureIconButton(title: String(localized: "Cancel Preset"), symbol: "xmark") {
                naming = false; name = ""
            }
        }
    }

    private func apply(_ presentation: CapturePresentation) {
        state.finishEditing()
        state.setPresentation(presentation)
    }

    private func save(name: String, replacing id: UUID? = nil) {
        state.finishEditing()
        do {
            try coordinator.settings.savePresentationPreset(name: name, presentation: style, replacing: id)
            naming = false
            self.name = ""
            state.notice =
                id == nil ? String(localized: "Preset saved.") : String(localized: "Preset replaced.")
        } catch {
            state.notice = Bundle.main.localizedString(
                forKey: error.localizedDescription, value: nil, table: nil)
        }
    }
}
