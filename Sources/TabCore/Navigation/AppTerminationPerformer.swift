import Foundation

@MainActor
protocol AppTerminationPerformer: AnyObject {
    func terminate(pid: pid_t)
    func forceTerminate(pid: pid_t)
    func bundleIdentifier(pid: pid_t) -> String?
}
