import AppKit

extension CaptureCoordinator {
    func captureAfterDelay(_ seconds: Int) {
        guard [3, 5, 10].contains(seconds), let workspace, !workspace.busy, editor?.busy != true else { return }
        let request = workspace.request
        let region = editor.flatMap { workspace.frame(for: $0.document) }
        let windowID = editor?.document.pieces.first.flatMap { workspace.sourceWindows[$0.raster] }
        let displayID = workspace.target.display.displayID
        run { [weak self] in
            guard let self, await self.mayClose() else { return }
            self.countdown = seconds
            self.observeSession()
            self.countdownPanel.show(self, frame: workspace.target.screenFrame)
            self.restoreFocus()
            defer {
                self.countdownPanel.close()
                self.countdown = nil
                if self.workspace == nil { self.sessionObserver = nil }
            }
            let deadline = ContinuousClock.now.advanced(by: .seconds(seconds))
            for remaining in stride(from: seconds, through: 1, by: -1) {
                self.countdown = remaining
                try await Task.sleep(until: deadline.advanced(by: .seconds(1 - remaining)), clock: .continuous)
            }
            self.countdownPanel.close()
            try Task.checkCancellation()
            guard let screen = NSScreen.screens.first(where: {
                $0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID == displayID
            }) else { throw CaptureScreenService.Failure.displayChanged }
            try await self.prepare(screen: screen, request: CaptureRequest(mode: request.mode, scope: request.scope))
            if let windowID, let current = self.workspace {
                guard let window = current.target.windows.first(where: { $0.windowID == windowID }) else {
                    throw CaptureScreenService.Failure.unavailable
                }
                try await self.captureWindow(window, workspace: current)
            } else if request.scope == .region, let region {
                self.selectRegion(region)
            }
            if request.action != .edit {
                if self.editor != nil {
                    try await self.recognizeCurrent(translate: request.action == .translate)
                } else { self.workspace?.request.action = request.action }
            }
        }
    }
}
