import AppKit
import Foundation

@MainActor
final class NavigationCoordinator {
    private let shared: NavigationSharedContext
    private let focusPerformer: FocusPerformer

    private var navigationConfig: NavigationConfig
    private var hudConfig: HUDConfig

    private var pendingDirections: [Direction] = []
    private var isProcessing = false

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
        Logger.info(.navigation, "Updated navigation config")
    }

    func endCycleSessionOnModifierRelease() {
        shared.hideHUD()
        Logger.info(.navigation, "Cycle session ended on modifier release")
    }

    func recordCurrentSystemFocusIfAvailable() async {
        await shared.recordCurrentSystemFocusIfAvailable()
    }

    func enqueue(_ direction: Direction) {
        pendingDirections.append(direction)
        Logger.info(.navigation, "Enqueued direction \(direction.rawValue)")
        processQueueIfNeeded()
    }

    private func processQueueIfNeeded() {
        guard !isProcessing else { return }
        isProcessing = true

        Task { @MainActor in
            while !pendingDirections.isEmpty {
                let direction = pendingDirections.removeFirst()
                await handle(direction)
            }
            isProcessing = false
        }
    }

    private func handle(_ direction: Direction) async {
        let snapshots = await shared.refreshAndGetSnapshots()
        guard !snapshots.isEmpty else {
            Logger.info(.navigation, "No windows available for navigation")
            shared.hideHUD()
            return
        }

        if let focusedContext = await shared.resolveFocusedContext(from: snapshots) {
            Logger.info(
                .navigation,
                "Direction=\(direction.rawValue) focused=\(focusedContext.focused.windowId) candidates=\(focusedContext.candidates.count)"
            )
            shared.recordFocused(window: focusedContext.focused, monitorID: focusedContext.focusedScreen)
            await handleFixedAppRing(
                direction: direction,
                focused: focusedContext.focused,
                snapshots: snapshots,
                focusedScreen: focusedContext.focusedScreen
            )
            return
        }

        Logger.info(.navigation, "No focused window; entering desktop no-focus navigation")
        let monitorID = shared.resolveNoFocusMonitorID(from: snapshots)
        await handleNoFocusedWindow(direction: direction, snapshots: snapshots, preferredMonitorID: monitorID)
    }

    private func handleNoFocusedWindow(
        direction: Direction,
        snapshots: [WindowSnapshot],
        preferredMonitorID: NSNumber?
    ) async {
        let allowWindowless = (direction == .up || direction == .down)
        let resolved = shared.orderedGroupsForMonitor(
            snapshots: snapshots,
            preferredMonitorID: preferredMonitorID,
            config: navigationConfig.fixedAppRing,
            showWindowlessApps: navigationConfig.showWindowlessApps,
            allowWindowlessApps: allowWindowless
        )
        let orderedGroups = resolved.groups
        let monitorID = resolved.monitorID

        guard !orderedGroups.isEmpty else {
            Logger.info(.navigation, "Desktop no-focus has no candidate apps")
            shared.hideHUD()
            return
        }

        switch direction {
            case .up, .down, .windowUp, .windowDown:
                showHUD(for: orderedGroups, selectedIndex: nil, selectedWindowID: nil, monitorID: monitorID)
                Logger.info(.navigation, "Desktop no-focus preview HUD shown apps=\(orderedGroups.count)")
            case .right:
                await focusDesktopNoFocusGroup(
                    direction: direction,
                    orderedGroups: orderedGroups,
                    targetIndex: 0,
                    monitorID: monitorID
                )
            case .left:
                await focusDesktopNoFocusGroup(
                    direction: direction,
                    orderedGroups: orderedGroups,
                    targetIndex: orderedGroups.count - 1,
                    monitorID: monitorID
                )
        }
    }

    private func focusDesktopNoFocusGroup(
        direction: Direction,
        orderedGroups: [AppRingGroup],
        targetIndex: Int,
        monitorID: NSNumber
    ) async {
        let targetGroup = orderedGroups[targetIndex]
        guard let target = shared.selectWindow(
            in: targetGroup,
            monitorID: monitorID,
            direction: direction,
            focusedWindowID: 0,
            policy: navigationConfig.fixedAppRing.inAppWindow
        ) else {
            Logger.info(.navigation, "Desktop no-focus has no target window in app group \(targetGroup.key.rawValue)")
            return
        }

        showHUD(for: orderedGroups, selectedIndex: targetIndex, selectedWindowID: target.windowId, monitorID: monitorID)
        Logger.info(
            .navigation,
            "Desktop no-focus selected app direction=\(direction.rawValue) target-app=\(targetGroup.label) target-window=\(target.windowId)"
        )

        do {
            try await focusPerformer.focus(windowId: target.windowId, pid: target.pid)
            shared.recordFocused(window: target, monitorID: monitorID)
            Logger.info(.navigation, "Focused target window \(target.windowId)")
        } catch {
            Logger.error(.navigation, "Failed to focus window \(target.windowId): \(error.localizedDescription)")
        }
    }

    private func handleFixedAppRing(
        direction: Direction,
        focused: WindowSnapshot,
        snapshots: [WindowSnapshot],
        focusedScreen: NSNumber
    ) async {
        let allowWindowless = (direction == .up || direction == .down)
        let resolved = shared.orderedGroupsForMonitor(
            snapshots: snapshots,
            preferredMonitorID: focusedScreen,
            config: navigationConfig.fixedAppRing,
            showWindowlessApps: navigationConfig.showWindowlessApps,
            allowWindowlessApps: allowWindowless
        )
        let orderedGroups = resolved.groups

        guard !orderedGroups.isEmpty else {
            Logger.info(.navigation, "Standard mode has no candidate apps")
            return
        }

        let focusedAppKey = AppRingKey(window: focused)
        guard let currentIndex = orderedGroups.firstIndex(where: { $0.key == focusedAppKey }) else {
            Logger.info(.navigation, "Focused app \(focusedAppKey.rawValue) not found in standard mode app ring")
            return
        }

        let targetIndex: Int
        switch direction {
            case .right:
                guard orderedGroups.count > 1 else {
                    Logger.info(.navigation, "Standard mode has only one app group")
                    return
                }
                targetIndex = (currentIndex + 1) % orderedGroups.count
            case .left:
                guard orderedGroups.count > 1 else {
                    Logger.info(.navigation, "Standard mode has only one app group")
                    return
                }
                targetIndex = (currentIndex - 1 + orderedGroups.count) % orderedGroups.count
            case .up, .down, .windowUp, .windowDown:
                targetIndex = currentIndex
        }
        let targetGroup = orderedGroups[targetIndex]

        guard let target = shared.selectWindow(
            in: targetGroup,
            monitorID: focusedScreen,
            direction: direction,
            focusedWindowID: focused.windowId,
            policy: navigationConfig.fixedAppRing.inAppWindow
        ) else {
            Logger.info(.navigation, "No target window in app group \(targetGroup.key.rawValue)")
            return
        }

        if direction == .left || direction == .right {
            Logger.info(
                .navigation,
                "Standard mode direction=\(direction.rawValue) apps=\(orderedGroups.count) focused-app=\(orderedGroups[currentIndex].label) target-app=\(targetGroup.label)"
            )
        } else {
            Logger.info(
                .navigation,
                "Standard mode in-app cycle direction=\(direction.rawValue) app=\(targetGroup.label) windows=\(targetGroup.windows.count)"
            )
        }

        if let slot = shared.windowOrdinal(in: targetGroup, windowID: target.windowId) {
            Logger.info(
                .navigation,
                "Standard mode selected window \(target.windowId) slot=\(slot)/\(targetGroup.windows.count) policy=\(navigationConfig.fixedAppRing.inAppWindow.rawValue)"
            )
        } else {
            Logger.info(.navigation, "Standard mode selected window \(target.windowId) policy=\(navigationConfig.fixedAppRing.inAppWindow.rawValue)")
        }

        showHUD(for: orderedGroups, selectedIndex: targetIndex, selectedWindowID: target.windowId, monitorID: focusedScreen)

        do {
            try await focusPerformer.focus(windowId: target.windowId, pid: target.pid)
            shared.recordFocused(window: target, monitorID: focusedScreen)
            Logger.info(.navigation, "Focused target window \(target.windowId)")
        } catch {
            Logger.error(.navigation, "Failed to focus window \(target.windowId): \(error.localizedDescription)")
        }
    }

    private func showHUD(for groups: [AppRingGroup], selectedIndex: Int?, selectedWindowID: UInt32?, monitorID: NSNumber) {
        shared.showHUD(
            groups: groups,
            selectedIndex: selectedIndex,
            selectedWindowID: selectedWindowID,
            monitorID: monitorID,
            hudConfig: hudConfig,
            timeoutMs: navigationConfig.cycleTimeoutMs
        )
    }
}
