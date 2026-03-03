import CoreGraphics
import Foundation

public struct WindowSnapshot: Equatable, Sendable {
    public let windowId: UInt32
    public let pid: pid_t
    public let bundleId: String?
    public let appName: String?
    public let frame: CGRect
    public let isMinimized: Bool
    public let appIsHidden: Bool
    public let isFullscreen: Bool
    public let title: String?
    public let isWindowlessApp: Bool

    public init(
        windowId: UInt32,
        pid: pid_t,
        bundleId: String?,
        appName: String?,
        frame: CGRect,
        isMinimized: Bool,
        appIsHidden: Bool,
        isFullscreen: Bool,
        title: String?,
        isWindowlessApp: Bool = false
    ) {
        self.windowId = windowId
        self.pid = pid
        self.bundleId = bundleId
        self.appName = appName
        self.frame = frame
        self.isMinimized = isMinimized
        self.appIsHidden = appIsHidden
        self.isFullscreen = isFullscreen
        self.title = title
        self.isWindowlessApp = isWindowlessApp
    }
}

protocol WindowProvider: AnyObject {
    @MainActor
    func currentSnapshot() async throws -> [WindowSnapshot]
}

protocol FocusedWindowProvider: AnyObject {
    @MainActor
    func focusedWindowID() async -> UInt32?
}
