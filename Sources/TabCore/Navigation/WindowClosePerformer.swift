import Foundation

@MainActor
protocol WindowClosePerformer: AnyObject {
    func close(windowId: UInt32, pid: pid_t) -> Bool
}
