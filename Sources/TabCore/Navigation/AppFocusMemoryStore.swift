import Foundation

@MainActor
final class AppFocusMemoryStore {
    private var lastFocusedWindowByApp: [AppRingKey: UInt32] = [:]

    func recordFocused(window: WindowSnapshot) {
        let appKey = AppRingKey(window: window)
        lastFocusedWindowByApp[appKey] = window.windowId
    }

    func preferredWindowID(
        appKey: AppRingKey,
        candidateWindows: [WindowSnapshot]
    ) -> UInt32? {
        guard !candidateWindows.isEmpty else { return nil }
        let candidateIDs = Set(candidateWindows.map(\.windowId))
        if let id = lastFocusedWindowByApp[appKey], candidateIDs.contains(id) {
            return id
        }
        return nil
    }

    func prune(using snapshots: [WindowSnapshot]) {
        let visibleWindowIDs = Set(snapshots.map(\.windowId))
        let visibleAppKeys = Set(snapshots.map(AppRingKey.init(window:)))
        lastFocusedWindowByApp = lastFocusedWindowByApp.filter { key, windowID in
            visibleAppKeys.contains(key) && visibleWindowIDs.contains(windowID)
        }
    }
}
