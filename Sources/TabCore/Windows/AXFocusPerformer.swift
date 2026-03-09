import AppKit
import ApplicationServices
import Foundation

protocol FocusPerformer: AnyObject {
    @MainActor
    func focus(windowId: UInt32, pid: pid_t) async throws
}

@MainActor
final class AXFocusPerformer: FocusPerformer {
    func focus(windowId: UInt32, pid: pid_t) async throws {
        if SyntheticWindowID.matches(windowId: windowId, pid: pid) {
            guard let app = NSRunningApplication(processIdentifier: pid) else { return }
            if app.isHidden {
                _ = app.unhide()
            }
            if let bundleURL = app.bundleURL {
                NSWorkspace.shared.openApplication(at: bundleURL, configuration: NSWorkspace.OpenConfiguration()) { _, _ in }
            } else {
                _ = app.activate(options: .activateAllWindows)
            }
            return
        }

        guard let window = findWindowElement(windowId: windowId, pid: pid) else { return }

        if let isMinimized = window.tabCopyAttribute(kAXMinimizedAttribute as String) as? Bool, isMinimized {
            _ = window.tabSetAttribute(kAXMinimizedAttribute as String, kCFBooleanFalse)
        }
        if let app = NSRunningApplication(processIdentifier: pid), app.isHidden {
            _ = app.unhide()
        }

        _ = window.tabSetAttribute(kAXMainAttribute as String, kCFBooleanTrue)
        _ = AXUIElementPerformAction(window, kAXRaiseAction as CFString)
        if let app = NSRunningApplication(processIdentifier: pid) {
            _ = app.activate(options: [.activateAllWindows])
        }
    }

    private func findWindowElement(windowId: UInt32, pid: pid_t) -> AXUIElement? {
        let appElement = AXUIElementCreateApplication(pid)
        guard let windows = appElement.tabCopyAttribute(kAXWindowsAttribute as String) as? [AnyObject] else {
            return nil
        }

        for raw in windows {
            let window = raw as! AXUIElement
            if window.tabWindowID() == windowId {
                return window
            }
        }
        return nil
    }
}
