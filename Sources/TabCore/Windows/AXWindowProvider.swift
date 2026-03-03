import AppKit
import ApplicationServices
import Foundation

@MainActor
final class AXWindowProvider: WindowProvider, FocusedWindowProvider {
    private var config: TabConfig = .default

    func updateConfig(_ config: TabConfig) {
        self.config = config
    }

    func currentSnapshot() async throws -> [WindowSnapshot] {
        let cgLikelyWindowOwnerPIDs = CGWindowPresence.collectLikelyWindowOwnerPIDs()
        var snapshots: [WindowSnapshot] = []

        for app in NSWorkspace.shared.runningApplications where shouldConsider(app: app) {
            snapshots.append(contentsOf: snapshotsForApp(app, cgLikelyWindowOwnerPIDs: cgLikelyWindowOwnerPIDs))
        }

        return snapshots
    }

    func focusedWindowID() async -> UInt32? {
        guard let frontmost = NSWorkspace.shared.frontmostApplication else { return nil }
        let appElement = AXUIElementCreateApplication(frontmost.processIdentifier)
        guard let focusedRaw = appElement.tabCopyAttribute(kAXFocusedWindowAttribute as String) else { return nil }
        let focusedElement = focusedRaw as! AXUIElement
        return focusedElement.tabWindowID()
    }

    private func snapshotsForApp(
        _ app: NSRunningApplication,
        cgLikelyWindowOwnerPIDs: Set<pid_t>
    ) -> [WindowSnapshot] {
        let cgHasLikelyWindow = cgLikelyWindowOwnerPIDs.contains(app.processIdentifier)
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        guard let windows = appElement.tabCopyAttribute(kAXWindowsAttribute as String) as? [AnyObject] else {
            return fallbackSnapshotsForAXMiss(app: app, cgHasLikelyWindow: cgHasLikelyWindow)
        }

        if windows.isEmpty {
            return fallbackSnapshotsForAXMiss(app: app, cgHasLikelyWindow: cgHasLikelyWindow)
        }

        var snapshots: [WindowSnapshot] = []
        for raw in windows {
            let axWindow = raw as! AXUIElement
            guard let snapshot = makeSnapshot(from: axWindow, app: app) else { continue }
            snapshots.append(snapshot)
        }

        if snapshots.isEmpty {
            return fallbackSnapshotsForAXMiss(app: app, cgHasLikelyWindow: cgHasLikelyWindow)
        }

        return snapshots
    }

    private func fallbackSnapshotsForAXMiss(app: NSRunningApplication, cgHasLikelyWindow: Bool) -> [WindowSnapshot] {
        let fallbackKind = AXWindowFallbackClassifier.fallbackKind(
            bundleId: app.bundleIdentifier,
            showEmptyApps: config.visibility.showEmptyApps,
            cgHasLikelyWindow: cgHasLikelyWindow
        )

        switch fallbackKind {
            case .none:
                return []
            case .activationFallback:
                Logger.debug(.windows, "ax-miss pid=\(app.processIdentifier) cg-has-windows=true -> activation-fallback")
                guard let snapshot = makeSyntheticAppSnapshot(app: app, isWindowlessApp: false) else { return [] }
                return [snapshot]
            case .confirmedWindowless:
                Logger.debug(.windows, "ax-miss pid=\(app.processIdentifier) cg-has-windows=false -> confirmed-windowless")
                guard let snapshot = makeSyntheticAppSnapshot(app: app, isWindowlessApp: true) else { return [] }
                return [snapshot]
        }
    }

    private func makeSyntheticAppSnapshot(app: NSRunningApplication, isWindowlessApp: Bool) -> WindowSnapshot? {
        guard app.activationPolicy == .regular else { return nil }
        guard !app.isTerminated else { return nil }

        let syntheticWindowId = UInt32.max - UInt32(app.processIdentifier % Int32.max)
        return WindowSnapshot(
            windowId: syntheticWindowId,
            pid: app.processIdentifier,
            bundleId: app.bundleIdentifier,
            appName: app.localizedName,
            frame: .zero,
            isMinimized: false,
            appIsHidden: app.isHidden,
            isFullscreen: false,
            title: app.localizedName,
            isWindowlessApp: isWindowlessApp
        )
    }

    private func makeSnapshot(from window: AXUIElement, app: NSRunningApplication) -> WindowSnapshot? {
        guard let windowId = window.tabWindowID() else { return nil }

        let role = (window.tabCopyAttribute(kAXRoleAttribute as String) as? String) ?? ""
        guard role == (kAXWindowRole as String) else { return nil }

        let isFullscreen = (window.tabCopyAttribute("AXFullScreen") as? Bool) ?? false
        let subrole = (window.tabCopyAttribute(kAXSubroleAttribute as String) as? String) ?? ""
        guard AXWindowEligibility.acceptsSubrole(subrole, isFullscreen: isFullscreen) else { return nil }
        if subrole != (kAXStandardWindowSubrole as String) && isFullscreen {
            Logger.debug(.windows, "fullscreen-nonstandard-subrole accepted pid=\(app.processIdentifier) window=\(windowId)")
        }

        let isMinimized = (window.tabCopyAttribute(kAXMinimizedAttribute as String) as? Bool) ?? false

        guard let position = pointAttribute(window, key: kAXPositionAttribute as String) else { return nil }
        guard let size = sizeAttribute(window, key: kAXSizeAttribute as String) else { return nil }
        if size.width <= 1 || size.height <= 1 { return nil }

        let frame = CGRect(origin: position, size: size)
        let title = window.tabCopyAttribute(kAXTitleAttribute as String) as? String

        return WindowSnapshot(
            windowId: windowId,
            pid: app.processIdentifier,
            bundleId: app.bundleIdentifier,
            appName: app.localizedName,
            frame: frame,
            isMinimized: isMinimized,
            appIsHidden: app.isHidden,
            isFullscreen: isFullscreen,
            title: title
        )
    }

    private func pointAttribute(_ element: AXUIElement, key: String) -> CGPoint? {
        guard let raw = element.tabCopyAttribute(key) else { return nil }
        guard CFGetTypeID(raw) == AXValueGetTypeID() else { return nil }
        let value = raw as! AXValue
        guard AXValueGetType(value) == .cgPoint else { return nil }
        var point: CGPoint = .zero
        guard AXValueGetValue(value, .cgPoint, &point) else { return nil }
        return point
    }

    private func sizeAttribute(_ element: AXUIElement, key: String) -> CGSize? {
        guard let raw = element.tabCopyAttribute(key) else { return nil }
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
