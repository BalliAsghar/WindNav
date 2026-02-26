import AppKit
import ApplicationServices
import Foundation

@MainActor
final class AXFocusPerformer: FocusPerformer {
    func focus(windowId: UInt32, pid: pid_t) async throws {
        guard let window = findWindowElement(windowId: windowId, pid: pid) else {
            return
        }

        _ = window.windNavSetAttribute(kAXMainAttribute as String, kCFBooleanTrue)
        _ = AXUIElementPerformAction(window, kAXRaiseAction as CFString)

        if let app = NSRunningApplication(processIdentifier: pid) {
            _ = app.activate(options: [.activateIgnoringOtherApps])
        }
    }

    private func findWindowElement(windowId: UInt32, pid: pid_t) -> AXUIElement? {
        let appElement = AXUIElementCreateApplication(pid)
        guard let windows = appElement.windNavCopyAttribute(kAXWindowsAttribute as String) as? [AnyObject] else {
            return nil
        }

        for raw in windows {
            let window = raw as! AXUIElement
            if window.windNavWindowID() == windowId {
                return window
            }
        }

        return nil
    }
}
