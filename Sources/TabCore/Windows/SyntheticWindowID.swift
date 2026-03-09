import Foundation

enum SyntheticWindowID {
    static func make(pid: pid_t) -> UInt32 {
        UInt32.max - UInt32(pid % Int32.max)
    }

    static func matches(windowId: UInt32, pid: pid_t) -> Bool {
        windowId == make(pid: pid)
    }
}
