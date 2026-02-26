import AppKit
import Foundation

public enum Direction: String, CaseIterable, Sendable {
    case left
    case right
}

public enum NavigationScope: String, Sendable {
    case currentMonitor = "current-monitor"
}

public enum NavigationPolicy: String, Sendable {
    case mruCycle = "mru-cycle"
}

public enum NoCandidateBehavior: String, Sendable {
    case noop
}

public enum FilteringMode: String, Sendable {
    case conservative
}

public struct WindowSnapshot: Equatable, Sendable {
    public let windowId: UInt32
    public let pid: pid_t
    public let bundleId: String?
    public let frame: CGRect
    public let isMinimized: Bool
    public let appIsHidden: Bool
    public let title: String?

    public init(
        windowId: UInt32,
        pid: pid_t,
        bundleId: String?,
        frame: CGRect,
        isMinimized: Bool,
        appIsHidden: Bool,
        title: String?
    ) {
        self.windowId = windowId
        self.pid = pid
        self.bundleId = bundleId
        self.frame = frame
        self.isMinimized = isMinimized
        self.appIsHidden = appIsHidden
        self.title = title
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
