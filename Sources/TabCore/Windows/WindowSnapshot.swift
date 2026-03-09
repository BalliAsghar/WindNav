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
    public let isOnCurrentSpace: Bool
    public let isOnCurrentDisplay: Bool
    public let canCaptureThumbnail: Bool
    public let revision: UInt64

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
        isWindowlessApp: Bool = false,
        isOnCurrentSpace: Bool? = nil,
        isOnCurrentDisplay: Bool? = nil,
        canCaptureThumbnail: Bool? = nil,
        revision: UInt64 = 0
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
        self.isOnCurrentSpace = isOnCurrentSpace ?? Self.defaultIsOnCurrentSpace(
            isMinimized: isMinimized,
            appIsHidden: appIsHidden
        )
        self.isOnCurrentDisplay = isOnCurrentDisplay ?? Self.defaultIsOnCurrentDisplay(
            frame: frame,
            isMinimized: isMinimized
        )
        self.canCaptureThumbnail = canCaptureThumbnail ?? Self.defaultCanCaptureThumbnail(
            windowId: windowId,
            pid: pid,
            frame: frame,
            isWindowlessApp: isWindowlessApp
        )
        self.revision = revision
    }

    func withTrackingMetadata(
        isOnCurrentSpace: Bool,
        isOnCurrentDisplay: Bool,
        canCaptureThumbnail: Bool,
        revision: UInt64
    ) -> WindowSnapshot {
        WindowSnapshot(
            windowId: windowId,
            pid: pid,
            bundleId: bundleId,
            appName: appName,
            frame: frame,
            isMinimized: isMinimized,
            appIsHidden: appIsHidden,
            isFullscreen: isFullscreen,
            title: title,
            isWindowlessApp: isWindowlessApp,
            isOnCurrentSpace: isOnCurrentSpace,
            isOnCurrentDisplay: isOnCurrentDisplay,
            canCaptureThumbnail: canCaptureThumbnail,
            revision: revision
        )
    }

    private static func defaultIsOnCurrentSpace(
        isMinimized: Bool,
        appIsHidden: Bool
    ) -> Bool {
        !isMinimized && !appIsHidden
    }

    private static func defaultIsOnCurrentDisplay(
        frame: CGRect,
        isMinimized: Bool
    ) -> Bool {
        guard !isMinimized, !frame.isEmpty else { return false }
        return CGDisplayBounds(CGMainDisplayID()).intersects(frame)
    }

    private static func defaultCanCaptureThumbnail(
        windowId: UInt32,
        pid: pid_t,
        frame: CGRect,
        isWindowlessApp: Bool
    ) -> Bool {
        guard !isWindowlessApp else { return false }
        guard !SyntheticWindowID.matches(windowId: windowId, pid: pid) else { return false }
        return frame.width > 1 && frame.height > 1
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
