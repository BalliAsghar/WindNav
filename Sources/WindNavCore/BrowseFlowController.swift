import AppKit
import Foundation

private struct BrowseSessionState {
    let monitorID: NSNumber
    let orderedGroups: [AppRingGroup]
    let focusedAppKey: AppRingKey?
    var selectedIndex: Int?
    var selectedWindowID: UInt32?
}

@MainActor
final class BrowseFlowController {
    private let shared: NavigationSharedContext
    private let focusPerformer: FocusPerformer

    private var navigationConfig: NavigationConfig
    private var hudConfig: HUDConfig

    private var session: BrowseSessionState?
    private var isStartingSession = false
    private var pendingDirections: [Direction] = []
    private var sessionGeneration: UInt64 = 0

    init(
        cache: WindowStateCache,
        focusedWindowProvider: FocusedWindowProvider,
        focusPerformer: FocusPerformer,
        appRingStateStore: AppRingStateStore,
        appFocusMemoryStore: AppFocusMemoryStore,
        hudController: any CycleHUDControlling,
        navigationConfig: NavigationConfig,
        hudConfig: HUDConfig,
        mouseLocationProvider: @escaping @MainActor () -> CGPoint = { NSEvent.mouseLocation }
    ) {
        shared = NavigationSharedContext(
            cache: cache,
            focusedWindowProvider: focusedWindowProvider,
            appRingStateStore: appRingStateStore,
            appFocusMemoryStore: appFocusMemoryStore,
            hudController: hudController,
            mouseLocationProvider: mouseLocationProvider
        )
        self.focusPerformer = focusPerformer
        self.navigationConfig = navigationConfig
        self.hudConfig = hudConfig
    }

    func updateConfig(navigation: NavigationConfig, hud: HUDConfig) {
        navigationConfig = navigation
        hudConfig = hud
        if !hud.enabled {
            shared.hideHUD()
        }
    }

    var isSessionActive: Bool {
        isStartingSession || session != nil
    }

    func startSessionIfNeeded() {
        guard !isSessionActive else { return }
        isStartingSession = true
        pendingDirections = []
        sessionGeneration &+= 1
        let generation = sessionGeneration
        Logger.info(.navigation, "[flow=browse] starting session")

        Task { @MainActor in
            await initializeSession(generation: generation)
        }
    }

    func handleDirection(_ direction: Direction) {
        if isStartingSession {
            pendingDirections.append(direction)
            Logger.info(.navigation, "[flow=browse] queued direction while session initializes direction=\(direction.rawValue)")
            return
        }

        guard session != nil else { return }
        applyDirection(direction)
    }

    func commitSessionOnModifierRelease() {
        if isStartingSession {
            Logger.info(.navigation, "[flow=browse] session ended before initialization finished")
            clearSession(hideHUD: true, invalidatePendingStart: true)
            return
        }

        guard let session else { return }
        guard let selectedIndex = session.selectedIndex else {
            Logger.info(.navigation, "[flow=browse] session ended with no selection")
            clearSession(hideHUD: true, invalidatePendingStart: true)
            return
        }
        guard session.orderedGroups.indices.contains(selectedIndex) else {
            Logger.info(.navigation, "[flow=browse] session ended with invalid selection index=\(selectedIndex)")
            clearSession(hideHUD: true, invalidatePendingStart: true)
            return
        }

        let selectedGroup = session.orderedGroups[selectedIndex]
        let selectedWindowID = session.selectedWindowID
        let preferredMonitorID = session.monitorID
        clearSession(hideHUD: true, invalidatePendingStart: true)

        Task { @MainActor in
            await commitSelection(
                selectedAppKey: selectedGroup.key,
                selectedAppLabel: selectedGroup.label,
                selectedWindowID: selectedWindowID,
                preferredMonitorID: preferredMonitorID
            )
        }
    }

    func cancelSessionWithoutCommit() {
        guard isSessionActive else { return }
        Logger.info(.navigation, "[flow=browse] session cancelled")
        clearSession(hideHUD: true, invalidatePendingStart: true)
    }
    
    func selectedAppPid() -> pid_t? {
        guard let session, let selectedIndex = session.selectedIndex else { return nil }
        guard session.orderedGroups.indices.contains(selectedIndex) else { return nil }
        let selectedGroup = session.orderedGroups[selectedIndex]
        return selectedGroup.windows.first?.pid
    }

    private func initializeSession(generation: UInt64) async {
        let snapshots = await shared.refreshAndGetSnapshots()
        guard sessionGeneration == generation, isStartingSession else { return }

        guard !snapshots.isEmpty else {
            Logger.info(.navigation, "[flow=browse] start aborted: no windows available")
            clearSession(hideHUD: true, invalidatePendingStart: false)
            return
        }

        guard let seed = await shared.resolveBrowseSeedContext(
            from: snapshots,
            config: navigationConfig.fixedAppRing,
            showWindowlessApps: navigationConfig.showWindowlessApps
        ) else {
            Logger.info(.navigation, "[flow=browse] start aborted: no candidate apps")
            clearSession(hideHUD: true, invalidatePendingStart: false)
            return
        }

        let created = BrowseSessionState(
            monitorID: seed.monitorID,
            orderedGroups: seed.groups,
            focusedAppKey: seed.focusedAppKey,
            selectedIndex: nil,
            selectedWindowID: nil
        )
        session = created
        isStartingSession = false
        showHUD(for: created)
        Logger.info(.navigation, "[flow=browse] session started apps=\(seed.groups.count)")

        let queued = pendingDirections
        pendingDirections = []
        for direction in queued {
            applyDirection(direction)
        }
    }

    private func applyDirection(_ direction: Direction) {
        guard var session else { return }
        guard !session.orderedGroups.isEmpty else { return }

        let browseDirection: Direction = (direction == .right || direction == .up) ? .right : .left
        
        let count = session.orderedGroups.count
        let targetIndex: Int
        if let currentIndex = session.selectedIndex {
            let step = browseDirection == .right ? 1 : -1
            targetIndex = (currentIndex + step + count) % count
        } else {
            targetIndex = browseDirection == .right ? 0 : (count - 1)
        }

        session.selectedIndex = targetIndex
        let targetGroup = session.orderedGroups[targetIndex]
        let selectedWindowID = shared.selectWindow(
            in: targetGroup,
            monitorID: session.monitorID,
            direction: browseDirection,
            focusedWindowID: session.selectedWindowID ?? 0,
            policy: navigationConfig.fixedAppRing.inAppWindow
        )?.windowId
        session.selectedWindowID = selectedWindowID
        self.session = session
        showHUD(for: session)
        Logger.info(
            .navigation,
            "[flow=browse] app selection moved direction=\(browseDirection.rawValue) selected-app=\(targetGroup.label) selected-index=\(targetIndex)"
        )
    }

    private func commitSelection(
        selectedAppKey: AppRingKey,
        selectedAppLabel: String,
        selectedWindowID: UInt32?,
        preferredMonitorID: NSNumber
    ) async {
        let snapshots = await shared.refreshAndGetSnapshots()
        guard !snapshots.isEmpty else {
            Logger.info(.navigation, "[flow=browse] commit skipped: no windows available")
            return
        }

        let resolved = shared.orderedGroupsForMonitor(
            snapshots: snapshots,
            preferredMonitorID: preferredMonitorID,
            config: navigationConfig.fixedAppRing,
            showWindowlessApps: navigationConfig.showWindowlessApps,
            allowWindowlessApps: true
        )
        guard !resolved.groups.isEmpty else {
            Logger.info(.navigation, "[flow=browse] commit skipped: no candidate apps")
            return
        }

        guard let targetIndex = resolved.groups.firstIndex(where: { $0.key == selectedAppKey }) else {
            Logger.info(
                .navigation,
                "[flow=browse] commit skipped: selected app missing selected-app=\(selectedAppLabel) key=\(selectedAppKey.rawValue)"
            )
            return
        }

        let targetGroup = resolved.groups[targetIndex]
        let target = targetGroup.windows.first(where: { $0.windowId == selectedWindowID })
            ?? shared.selectWindow(
                in: targetGroup,
                monitorID: resolved.monitorID,
                direction: .right,
                focusedWindowID: 0,
                policy: navigationConfig.fixedAppRing.inAppWindow
            )

        guard let target else {
            Logger.info(.navigation, "[flow=browse] commit skipped: selected app has no target window selected-app=\(targetGroup.label)")
            return
        }

        Logger.info(
            .navigation,
            "[flow=browse] commit on modifier release target-app=\(targetGroup.label) target-window=\(target.windowId)"
        )
        do {
            try await focusPerformer.focus(windowId: target.windowId, pid: target.pid)
            shared.recordFocused(window: target, monitorID: resolved.monitorID)
            Logger.info(.navigation, "Focused target window \(target.windowId)")
        } catch {
            Logger.error(.navigation, "Failed to focus window \(target.windowId): \(error.localizedDescription)")
        }
    }

    private func clearSession(hideHUD: Bool, invalidatePendingStart: Bool) {
        if invalidatePendingStart {
            sessionGeneration &+= 1
        }
        session = nil
        isStartingSession = false
        pendingDirections = []
        if hideHUD {
            shared.hideHUD()
        }
    }

    private func showHUD(for session: BrowseSessionState) {
        shared.showHUD(
            groups: session.orderedGroups,
            selectedIndex: session.selectedIndex,
            selectedWindowID: session.selectedWindowID,
            monitorID: session.monitorID,
            hudConfig: hudConfig,
            timeoutMs: 0
        )
    }
}
