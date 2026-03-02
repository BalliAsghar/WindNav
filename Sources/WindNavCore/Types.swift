import AppKit
import Foundation

public enum Direction: String, CaseIterable, Sendable {
    case left
    case right
    case up
    case down
}

public enum NavigationMode: String, Sendable {
    case standard = "standard"
}

public enum UnpinnedAppsPolicy: String, Sendable {
    case append
    case ignore
}

public enum InAppWindowSelectionPolicy: String, Sendable {
    case lastFocused = "last-focused"
    case lastFocusedOnMonitor = "last-focused-on-monitor"
    case spatial
}

public enum GroupingMode: String, Sendable {
    case oneStopPerApp = "one-stop-per-app"
}

public enum HUDPosition: String, Sendable {
    case topCenter = "top-center"
    case middleCenter = "middle-center"
    case bottomCenter = "bottom-center"
}

public enum ShowWindowlessAppsPolicy: String, Sendable {
    case hide
    case show
    case showAtEnd = "show-at-end"
}

public struct WindowSnapshot: Equatable, Sendable {
    public let windowId: UInt32
    public let pid: pid_t
    public let bundleId: String?
    public let frame: CGRect
    public let isMinimized: Bool
    public let appIsHidden: Bool
    public let title: String?
    public let isWindowlessApp: Bool

    public init(
        windowId: UInt32,
        pid: pid_t,
        bundleId: String?,
        frame: CGRect,
        isMinimized: Bool,
        appIsHidden: Bool,
        title: String?,
        isWindowlessApp: Bool = false
    ) {
        self.windowId = windowId
        self.pid = pid
        self.bundleId = bundleId
        self.frame = frame
        self.isMinimized = isMinimized
        self.appIsHidden = appIsHidden
        self.title = title
        self.isWindowlessApp = isWindowlessApp
    }
}

public protocol WindowProvider: AnyObject {
    @MainActor
    func currentSnapshot() async throws -> [WindowSnapshot]
}

public protocol FocusPerformer: AnyObject {
    @MainActor
    func focus(windowId: UInt32, pid: pid_t) async throws
}

protocol FocusedWindowProvider: AnyObject {
    @MainActor
    func focusedWindowID() async -> UInt32?
}

extension WindowSnapshot {
    var center: CGPoint {
        CGPoint(x: frame.midX, y: frame.midY)
    }
}

@MainActor
enum ScreenLocator {
    static func screenID(containing point: CGPoint) -> NSNumber? {
        for screen in NSScreen.screens where screen.frame.contains(point) {
            return screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
        }
        return nil
    }
}
