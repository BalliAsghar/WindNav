import Foundation

private struct AppMonitorMemoryKey: Hashable {
    let appKey: AppRingKey
    let monitorID: NSNumber
}

@MainActor
final class AppFocusMemoryStore {
    private var lastFocusedWindowByApp: [AppRingKey: UInt32] = [:]
    private var lastFocusedWindowByAppMonitor: [AppMonitorMemoryKey: UInt32] = [:]

    func recordFocused(window: WindowSnapshot, monitorID: NSNumber) {
        let appKey = AppRingKey(window: window)
        lastFocusedWindowByApp[appKey] = window.windowId
        lastFocusedWindowByAppMonitor[AppMonitorMemoryKey(appKey: appKey, monitorID: monitorID)] = window.windowId
    }

    func preferredWindowID(
        appKey: AppRingKey,
        candidateWindows: [WindowSnapshot],
        monitorID: NSNumber,
        policy: InAppWindowSelectionPolicy
    ) -> UInt32? {
        guard !candidateWindows.isEmpty else { return nil }
        let candidateIDs = Set(candidateWindows.map(\WindowSnapshot.windowId))

        switch policy {
            case .lastFocused:
                if let id = lastFocusedWindowByApp[appKey], candidateIDs.contains(id) {
                    return id
                }
                return nil

            case .lastFocusedOnMonitor:
                let monitorKey = AppMonitorMemoryKey(appKey: appKey, monitorID: monitorID)
                if let id = lastFocusedWindowByAppMonitor[monitorKey], candidateIDs.contains(id) {
                    return id
                }
                if let id = lastFocusedWindowByApp[appKey], candidateIDs.contains(id) {
                    return id
                }
                return nil

            case .spatial:
                return nil
        }
    }

    func prune(using snapshots: [WindowSnapshot]) {
        let visibleWindowIDs = Set(snapshots.map(\WindowSnapshot.windowId))
        let visibleAppKeys = Set(snapshots.map(AppRingKey.init(window:)))

        lastFocusedWindowByApp = lastFocusedWindowByApp.filter { key, windowID in
            visibleAppKeys.contains(key) && visibleWindowIDs.contains(windowID)
        }

        lastFocusedWindowByAppMonitor = lastFocusedWindowByAppMonitor.filter { key, windowID in
            visibleAppKeys.contains(key.appKey) && visibleWindowIDs.contains(windowID)
        }
    }
}
