import SwiftUI

struct CaptureToolbarMenuStyle: MenuStyle {
    var selected = false
    var fitsContent = false

    func makeBody(configuration: Configuration) -> some View {
        Menu(configuration)
            .menuStyle(.button).menuIndicator(.hidden)
            .buttonStyle(CaptureToolbarButtonStyle(selected: selected, fitsContent: fitsContent))
    }
}
