import AppKit
import ApplicationServices
import Foundation

@MainActor
final class AXWindowProvider: WindowProvider, FocusedWindowProvider {
    private var includeMinimized = NavigationConfig.default.includeMinimized
    private var includeHiddenApps = NavigationConfig.default.includeHiddenApps

    func updateNavigationConfig(_ config: NavigationConfig) {
        includeMinimized = config.includeMinimized
        includeHiddenApps = config.includeHiddenApps
    }

    func currentSnapshot() async throws -> [WindowSnapshot] {
        var snapshots: [WindowSnapshot] = []

        for app in NSWorkspace.shared.runningApplications where shouldConsider(app: app) {
            snapshots.append(contentsOf: snapshotsForApp(app))
        }

        return snapshots
    }

    func focusedWindowID() async -> UInt32? {
        guard let frontmost = NSWorkspace.shared.frontmostApplication else { return nil }
        let appElement = AXUIElementCreateApplication(frontmost.processIdentifier)
        guard let focusedRaw = appElement.windNavCopyAttribute(kAXFocusedWindowAttribute as String) else { return nil }
        let focusedElement = focusedRaw as! AXUIElement
        return focusedElement.windNavWindowID()
    }

    func windowIDsAndElements(for app: NSRunningApplication) -> [(UInt32, AXUIElement)] {
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        guard let windows = appElement.windNavCopyAttribute(kAXWindowsAttribute as String) as? [AnyObject] else {
            return []
        }

        var result: [(UInt32, AXUIElement)] = []
        for raw in windows {
            let axWindow = raw as! AXUIElement
            guard let id = axWindow.windNavWindowID() else { continue }
            result.append((id, axWindow))
        }
        return result
    }

    private func snapshotsForApp(_ app: NSRunningApplication) -> [WindowSnapshot] {
        if app.isHidden && !includeHiddenApps {
            return []
        }

        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        guard let windows = appElement.windNavCopyAttribute(kAXWindowsAttribute as String) as? [AnyObject] else {
            return []
        }

        var snapshots: [WindowSnapshot] = []
        for raw in windows {
            let axWindow = raw as! AXUIElement
            guard let snapshot = makeSnapshot(from: axWindow, app: app) else { continue }
            snapshots.append(snapshot)
        }

        return snapshots
    }

    private func makeSnapshot(from window: AXUIElement, app: NSRunningApplication) -> WindowSnapshot? {
        guard let windowId = window.windNavWindowID() else { return nil }

        let role = (window.windNavCopyAttribute(kAXRoleAttribute as String) as? String) ?? ""
        guard role == (kAXWindowRole as String) else { return nil }

        let subrole = (window.windNavCopyAttribute(kAXSubroleAttribute as String) as? String) ?? ""
        guard subrole == (kAXStandardWindowSubrole as String) else { return nil }

        let isMinimized = (window.windNavCopyAttribute(kAXMinimizedAttribute as String) as? Bool) ?? false
        if isMinimized && !includeMinimized { return nil }

        guard let position = pointAttribute(window, key: kAXPositionAttribute as String) else { return nil }
        guard let size = sizeAttribute(window, key: kAXSizeAttribute as String) else { return nil }
        if size.width <= 1 || size.height <= 1 { return nil }

        let frame = CGRect(origin: position, size: size)
        let title = window.windNavCopyAttribute(kAXTitleAttribute as String) as? String

        return WindowSnapshot(
            windowId: windowId,
            pid: app.processIdentifier,
            bundleId: app.bundleIdentifier,
            frame: frame,
            isMinimized: isMinimized,
            appIsHidden: app.isHidden,
            title: title
        )
    }

    private func pointAttribute(_ element: AXUIElement, key: String) -> CGPoint? {
        guard let raw = element.windNavCopyAttribute(key) else { return nil }
        guard CFGetTypeID(raw) == AXValueGetTypeID() else { return nil }
        let value = raw as! AXValue
        guard AXValueGetType(value) == .cgPoint else { return nil }
        var point: CGPoint = .zero
        guard AXValueGetValue(value, .cgPoint, &point) else { return nil }
        return point
    }

    private func sizeAttribute(_ element: AXUIElement, key: String) -> CGSize? {
        guard let raw = element.windNavCopyAttribute(key) else { return nil }
        guard CFGetTypeID(raw) == AXValueGetTypeID() else { return nil }
        let value = raw as! AXValue
        guard AXValueGetType(value) == .cgSize else { return nil }
        var size: CGSize = .zero
        guard AXValueGetValue(value, .cgSize, &size) else { return nil }
        return size
    }

    private func shouldConsider(app: NSRunningApplication) -> Bool {
        guard app.activationPolicy == .regular else { return false }
        guard app.processIdentifier != getpid() else { return false }
        return !app.isTerminated
    }
}
