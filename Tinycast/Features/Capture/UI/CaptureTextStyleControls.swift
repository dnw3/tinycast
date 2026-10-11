import SwiftUI

struct CaptureTextStyleControls: View {
    let state: CaptureEditorState

    var body: some View {
        Toggle("Bold", isOn: Binding(get: { state.textStyle.bold }, set: { state.changeText(.bold($0)) }))
        Toggle("Italic", isOn: Binding(get: { state.textStyle.italic }, set: { state.changeText(.italic($0)) }))
        Toggle("Underline", isOn: Binding(get: { state.textStyle.underline }, set: { state.changeText(.underline($0)) }))
        Toggle("Strikethrough", isOn: Binding(get: { state.textStyle.strikethrough }, set: {
            state.changeText(.strikethrough($0))
        }))
        Picker("Alignment", selection: Binding(get: { state.textStyle.alignment }, set: { state.changeText(.alignment($0)) })) {
            ForEach(CaptureTextStyle.Alignment.allCases, id: \.self) { Text(LocalizedStringKey($0.title)).tag($0) }
        }
        Menu("Text Background") {
            Button("None") { state.changeText(.background(nil)) }
            Button("Yellow") { state.changeText(.background(CaptureColor(red: 255, green: 230, blue: 80))) }
            Button("White") { state.changeText(.background(CaptureColor(red: 255, green: 255, blue: 255))) }
            Button("Black") { state.changeText(.background(CaptureColor(red: 0, green: 0, blue: 0))) }
        }
        Menu("Text Outline") {
            Button("None") { state.changeText(.outline(nil)) }
            Button("White") { state.changeText(.outline(CaptureColor(red: 255, green: 255, blue: 255))) }
            Button("Black") { state.changeText(.outline(CaptureColor(red: 0, green: 0, blue: 0))) }
        }
    }
}
