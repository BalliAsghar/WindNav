import Foundation

protocol FocusPerformer: AnyObject {
    @MainActor
    func focus(windowId: UInt32, pid: pid_t) async throws
}
