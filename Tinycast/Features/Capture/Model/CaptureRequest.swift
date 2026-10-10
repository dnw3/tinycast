import Foundation

struct CaptureRequest: Equatable, Sendable {
    enum Mode: Sendable { case screenshot, scrolling, recording }
    enum Scope: Sendable { case region, window, screen }
    enum Action: Sendable { case edit, text, translate }

    var mode: Mode = .screenshot
    var scope: Scope = .region
    var action: Action = .edit
}
