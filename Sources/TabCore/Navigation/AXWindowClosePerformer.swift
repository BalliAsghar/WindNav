import ApplicationServices
import Foundation

@MainActor
final class AXWindowClosePerformer: WindowClosePerformer {
    func close(windowId: UInt32, pid: pid_t) -> Bool {
        guard !isWindowlessAppId(windowId, pid: pid) else { return false }
        guard let window = findWindowElement(windowId: windowId, pid: pid) else { return false }

        if AXUIElementPerformAction(window, "AXClose" as CFString) == .success {
            return true
        }

        guard
            let closeButtonRaw = window.tabCopyAttribute(kAXCloseButtonAttribute as String),
            CFGetTypeID(closeButtonRaw) == AXUIElementGetTypeID()
        else {
            return false
        }

        let closeButton = closeButtonRaw as! AXUIElement
        return AXUIElementPerformAction(closeButton, kAXPressAction as CFString) == .success
    }

    private func isWindowlessAppId(_ windowId: UInt32, pid: pid_t) -> Bool {
        let expectedSyntheticId = UInt32.max - UInt32(pid % Int32.max)
        return windowId == expectedSyntheticId
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
