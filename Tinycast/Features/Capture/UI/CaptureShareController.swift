import AppKit

@MainActor
final class CaptureShareController: NSObject, @MainActor NSSharingServicePickerDelegate, NSSharingServiceDelegate {
    private var picker: NSSharingServicePicker?
    private var completion: ((Error?) -> Void)?

    func show(_ url: URL, from view: NSView, completion: @escaping (Error?) -> Void) {
        guard picker == nil else { completion(Failure.inProgress); return }
        self.completion = completion
        let picker = NSSharingServicePicker(items: [url])
        picker.delegate = self
        self.picker = picker
        picker.show(relativeTo: CGRect(x: view.bounds.maxX - 1, y: view.bounds.maxY - 1, width: 1, height: 1),
            of: view, preferredEdge: .minY)
    }

    func sharingServicePicker(
        _ sharingServicePicker: NSSharingServicePicker, delegateFor sharingService: NSSharingService
    ) -> (any NSSharingServiceDelegate)? { self }

    func sharingServicePicker(_ sharingServicePicker: NSSharingServicePicker, didChoose service: NSSharingService?) {
        if service == nil { finish(nil) }
    }

    func sharingService(_ sharingService: NSSharingService, didShareItems items: [Any]) { finish(nil) }

    func sharingService(_ sharingService: NSSharingService, didFailToShareItems items: [Any], error: Error) { finish(error) }

    private func finish(_ error: Error?) {
        let completion = completion
        self.completion = nil
        picker = nil
        completion?(error)
    }

    enum Failure: LocalizedError {
        case windowUnavailable, inProgress
        var errorDescription: String? {
            switch self {
            case .windowUnavailable: "Reopen the capture editor and try sharing again."
            case .inProgress: "Finish or cancel the current share before starting another."
            }
        }
    }
}
