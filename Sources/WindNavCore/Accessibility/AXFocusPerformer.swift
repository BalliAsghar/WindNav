import AppKit
import ApplicationServices
import Foundation

@MainActor
final class AXFocusPerformer: FocusPerformer {
    func focus(windowId: UInt32, pid: pid_t) async throws {
        if isWindowlessAppId(windowId, pid: pid) {
            guard let app = NSRunningApplication(processIdentifier: pid) else { return }
            if app.isHidden { _ = app.unhide() }
            if let bundleUrl = app.bundleURL {
                NSWorkspace.shared.openApplication(at: bundleUrl, configuration: NSWorkspace.OpenConfiguration()) { runningApp, error in
                    if let error = error {
                        _ = app.activate(options: .activateAllWindows)
                        Logger.info(.navigation, "Activated windowless app (launch failed): \(app.localizedName ?? "unknown") error=\(error.localizedDescription)")
                    } else {
                        Logger.info(.navigation, "Launched windowless app via bundleURL: \(app.localizedName ?? "unknown")")
                    }
                }
            } else {
                _ = app.activate(options: .activateAllWindows)
                Logger.info(.navigation, "Activated windowless app (no bundleURL): \(app.localizedName ?? "unknown")")
            }
            return
        }
        guard let window = findWindowElement(windowId: windowId, pid: pid) else {
            return
        }
        if let isMinimized = window.windNavCopyAttribute(kAXMinimizedAttribute as String) as? Bool, isMinimized {
            _ = window.windNavSetAttribute(kAXMinimizedAttribute as String, kCFBooleanFalse)
        }
        if let app = NSRunningApplication(processIdentifier: pid), app.isHidden {
            _ = app.unhide()
        }
        _ = window.windNavSetAttribute(kAXMainAttribute as String, kCFBooleanTrue)
        _ = AXUIElementPerformAction(window, kAXRaiseAction as CFString)
        if let app = NSRunningApplication(processIdentifier: pid) {
            _ = app.activate(options: [.activateIgnoringOtherApps])
        }
    }

    private func isWindowlessAppId(_ windowId: UInt32, pid: pid_t) -> Bool {
        let expectedSyntheticId = UInt32.max - UInt32(pid % Int32.max)
        return windowId == expectedSyntheticId
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
