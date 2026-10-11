import Foundation

@main
struct CaptureSelectionPreparationTests {
    static func main() {
        let first = CaptureSelectionPreparation.Selection.region(CGRect(x: 1, y: 2, width: 30, height: 40), .region)
        let last = CaptureSelectionPreparation.Selection.region(CGRect(x: 3, y: 4, width: 50, height: 60), .screen)
        var pending = CaptureSelectionPreparation()
        precondition(pending.deferSelection(first))
        precondition(pending.deferSelection(last))
        precondition(pending.pending == last && !pending.ready)
        precondition(pending.finish() == last && pending.ready && pending.pending == nil)
        precondition(!pending.deferSelection(first))
        precondition(pending.finish() == nil)
        var cancelled = CaptureSelectionPreparation()
        precondition(cancelled.deferSelection(first))
        cancelled.cancel()
        precondition(cancelled.finish() == nil && !cancelled.ready)
        precondition(cancelled.deferSelection(last) && cancelled.pending == nil)
        var window = CaptureSelectionPreparation()
        precondition(window.deferSelection(.window(42)))
        precondition(window.finish() == .window(42))
        var displays = CaptureSelectionPreparation()
        let across = CaptureSelectionPreparation.Selection.displays(CGRect(x: -100, y: 0, width: 400, height: 300))
        precondition(displays.deferSelection(across))
        precondition(displays.finish() == across)
        var switched = CaptureSelectionPreparation()
        precondition(switched.deferSelection(first))
        switched.discardSelection()
        precondition(switched.finish() == nil)
        print("Selection before source readiness: last region, window, scope change and cancellation passed")
    }
}
