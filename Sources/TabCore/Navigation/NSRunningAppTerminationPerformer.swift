import AppKit
import Foundation

@MainActor
protocol AppTerminationPerformer: AnyObject {
    func terminate(pid: pid_t)
    func forceTerminate(pid: pid_t)
    func bundleIdentifier(pid: pid_t) -> String?
}

@MainActor
final class NSRunningAppTerminationPerformer: AppTerminationPerformer {
    func terminate(pid: pid_t) {
        NSRunningApplication(processIdentifier: pid)?.terminate()
    }

    func forceTerminate(pid: pid_t) {
        NSRunningApplication(processIdentifier: pid)?.forceTerminate()
    }

    func bundleIdentifier(pid: pid_t) -> String? {
        NSRunningApplication(processIdentifier: pid)?.bundleIdentifier
    }
}
