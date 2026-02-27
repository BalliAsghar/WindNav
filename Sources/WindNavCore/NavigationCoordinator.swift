import AppKit
import Foundation

func cycleHUDWindowSort(_ lhs: WindowSnapshot, _ rhs: WindowSnapshot) -> Bool {
    if lhs.frame.minX != rhs.frame.minX { return lhs.frame.minX < rhs.frame.minX }
    if lhs.frame.minY != rhs.frame.minY { return lhs.frame.minY < rhs.frame.minY }
    return lhs.windowId < rhs.windowId
}

func buildCycleHUDItems(
    groups: [AppRingGroup],
    selectedIndex: Int?,
    selectedWindowID: UInt32?
) -> [CycleHUDItem] {
    groups.enumerated().map { index, group in
        let representative = group.windows.first
        let orderedWindows = group.windows.sorted(by: cycleHUDWindowSort)
        let isCurrent = selectedIndex == index
        let currentWindowIndex: Int?
        if isCurrent, let selectedWindowID {
            currentWindowIndex = orderedWindows.firstIndex(where: { $0.windowId == selectedWindowID })
        } else {
            currentWindowIndex = nil
        }
        return CycleHUDItem(
            id: group.key.rawValue,
            label: group.label,
            iconPID: representative?.pid ?? 0,
            iconBundleId: representative?.bundleId,
            isPinned: group.isPinned,
            isCurrent: isCurrent,
            windowCount: orderedWindows.count,
            currentWindowIndex: currentWindowIndex
        )
    }
}

@MainActor
final class NavigationCoordinator {
    private let cache: WindowStateCache
    private let focusedWindowProvider: FocusedWindowProvider
    private let focusPerformer: FocusPerformer
    private let appRingStateStore: AppRingStateStore
    private let appFocusMemoryStore: AppFocusMemoryStore
    private let hudController: any CycleHUDControlling
    private let mouseLocationProvider: @MainActor () -> CGPoint

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
        self.cache = cache
        self.focusedWindowProvider = focusedWindowProvider
        self.focusPerformer = focusPerformer
        self.appRingStateStore = appRingStateStore
        self.appFocusMemoryStore = appFocusMemoryStore
        self.hudController = hudController
        self.navigationConfig = navigationConfig
        self.hudConfig = hudConfig
        self.mouseLocationProvider = mouseLocationProvider
    }

    func updateConfig(navigation: NavigationConfig, hud: HUDConfig) {
        navigationConfig = navigation
        hudConfig = hud
        if !hud.enabled {
            hudController.hide()
        }
        Logger.info(.navigation, "Updated navigation config")
    }

    func endCycleSessionOnModifierRelease() {
        hudController.hide()
        Logger.info(.navigation, "Cycle session ended on modifier release")
    }

    func recordCurrentSystemFocusIfAvailable() async {
        let snapshots = cache.snapshot
        guard !snapshots.isEmpty else { return }
        appFocusMemoryStore.prune(using: snapshots)

        guard let focusedID = await focusedWindowProvider.focusedWindowID() else { return }
        guard let focused = snapshots.first(where: { $0.windowId == focusedID }) else { return }
        guard let focusedScreen = ScreenLocator.screenID(containing: focused.center) else { return }
        appFocusMemoryStore.recordFocused(window: focused, monitorID: focusedScreen)
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
        let snapshots = await cache.refreshAndGetSnapshot()
        guard !snapshots.isEmpty else {
            Logger.info(.navigation, "No windows available for navigation")
            hudController.hide()
            return
        }
        appFocusMemoryStore.prune(using: snapshots)

        let focusedID = await focusedWindowProvider.focusedWindowID()
        if let focusedID,
           let focused = snapshots.first(where: { $0.windowId == focusedID }),
           let focusedScreen = ScreenLocator.screenID(containing: focused.center) {
            let candidates = snapshots.filter {
                ScreenLocator.screenID(containing: $0.center) == focusedScreen
            }
            Logger.info(.navigation, "Direction=\(direction.rawValue) focused=\(focused.windowId) candidates=\(candidates.count)")
            appFocusMemoryStore.recordFocused(window: focused, monitorID: focusedScreen)
            await handleFixedAppRing(direction: direction, focused: focused, candidates: candidates, focusedScreen: focusedScreen)
            return
        }

        if let focusedID {
            if snapshots.contains(where: { $0.windowId == focusedID }) {
                Logger.info(.navigation, "Focused window \(focusedID) is not on an active screen; entering desktop no-focus navigation")
            } else {
                Logger.info(.navigation, "Focused window \(focusedID) is not in current snapshot; entering desktop no-focus navigation")
            }
        } else {
            Logger.info(.navigation, "No focused window; entering desktop no-focus navigation")
        }

        let monitorID = resolveNoFocusMonitorID(from: snapshots)
        await handleNoFocusedWindow(direction: direction, snapshots: snapshots, preferredMonitorID: monitorID)
    }

    private func handleNoFocusedWindow(
        direction: Direction,
        snapshots: [WindowSnapshot],
        preferredMonitorID: NSNumber?
    ) async {
        let monitorCandidates: [WindowSnapshot]
        if let preferredMonitorID {
            let candidates = snapshots.filter {
                ScreenLocator.screenID(containing: $0.center) == preferredMonitorID
            }
            monitorCandidates = candidates.isEmpty ? snapshots : candidates
        } else {
            monitorCandidates = snapshots
        }

        let monitorID = preferredMonitorID
            ?? monitorCandidates.compactMap { ScreenLocator.screenID(containing: $0.center) }.first
            ?? NSNumber(value: 0)

        let seeds = buildAppRingSeeds(from: monitorCandidates)
        let orderedGroups = appRingStateStore.orderedGroups(
            from: seeds,
            monitorID: monitorID,
            config: navigationConfig.fixedAppRing
        )

        guard !orderedGroups.isEmpty else {
            Logger.info(.navigation, "Desktop no-focus has no candidate apps")
            hudController.hide()
            return
        }

        switch direction {
            case .up, .down:
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
        guard let target = selectWindow(
            in: targetGroup,
            monitorID: monitorID,
            direction: direction,
            focusedWindowID: 0
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
            appFocusMemoryStore.recordFocused(window: target, monitorID: monitorID)
            Logger.info(.navigation, "Focused target window \(target.windowId)")
        } catch {
            Logger.error(.navigation, "Failed to focus window \(target.windowId): \(error.localizedDescription)")
        }
    }

    private func handleFixedAppRing(
        direction: Direction,
        focused: WindowSnapshot,
        candidates: [WindowSnapshot],
        focusedScreen: NSNumber
    ) async {
        let seeds = buildAppRingSeeds(from: candidates)
        let orderedGroups = appRingStateStore.orderedGroups(
            from: seeds,
            monitorID: focusedScreen,
            config: navigationConfig.fixedAppRing
        )

        guard !orderedGroups.isEmpty else {
            Logger.info(.navigation, "Fixed app ring has no candidate apps")
            return
        }

        let focusedAppKey = AppRingKey(window: focused)
        guard let currentIndex = orderedGroups.firstIndex(where: { $0.key == focusedAppKey }) else {
            Logger.info(.navigation, "Focused app \(focusedAppKey.rawValue) not found in fixed app ring")
            return
        }

        let targetIndex: Int
        switch direction {
            case .right:
                guard orderedGroups.count > 1 else {
                    Logger.info(.navigation, "Fixed app ring has only one app group")
                    return
                }
                targetIndex = (currentIndex + 1) % orderedGroups.count
            case .left:
                guard orderedGroups.count > 1 else {
                    Logger.info(.navigation, "Fixed app ring has only one app group")
                    return
                }
                targetIndex = (currentIndex - 1 + orderedGroups.count) % orderedGroups.count
            case .up, .down:
                targetIndex = currentIndex
        }
        let targetGroup = orderedGroups[targetIndex]

        guard let target = selectWindow(
            in: targetGroup,
            monitorID: focusedScreen,
            direction: direction,
            focusedWindowID: focused.windowId
        ) else {
            Logger.info(.navigation, "No target window in app group \(targetGroup.key.rawValue)")
            return
        }

        if direction == .left || direction == .right {
            Logger.info(
                .navigation,
                "Fixed app ring direction=\(direction.rawValue) apps=\(orderedGroups.count) focused-app=\(orderedGroups[currentIndex].label) target-app=\(targetGroup.label)"
            )
        } else {
            Logger.info(
                .navigation,
                "Fixed app ring in-app cycle direction=\(direction.rawValue) app=\(targetGroup.label) windows=\(targetGroup.windows.count)"
            )
        }

        if let slot = windowOrdinal(in: targetGroup, windowID: target.windowId) {
            Logger.info(
                .navigation,
                "Fixed app ring selected window \(target.windowId) slot=\(slot)/\(targetGroup.windows.count) policy=\(navigationConfig.fixedAppRing.inAppWindow.rawValue)"
            )
        } else {
            Logger.info(.navigation, "Fixed app ring selected window \(target.windowId) policy=\(navigationConfig.fixedAppRing.inAppWindow.rawValue)")
        }

        showHUD(for: orderedGroups, selectedIndex: targetIndex, selectedWindowID: target.windowId, monitorID: focusedScreen)

        do {
            try await focusPerformer.focus(windowId: target.windowId, pid: target.pid)
            appFocusMemoryStore.recordFocused(window: target, monitorID: focusedScreen)
            Logger.info(.navigation, "Focused target window \(target.windowId)")
        } catch {
            Logger.error(.navigation, "Failed to focus window \(target.windowId): \(error.localizedDescription)")
        }
    }

    private func buildAppRingSeeds(from candidates: [WindowSnapshot]) -> [AppRingGroupSeed] {
        var windowsByKey: [AppRingKey: [WindowSnapshot]] = [:]
        for window in candidates {
            let key = AppRingKey(window: window)
            windowsByKey[key, default: []].append(window)
        }

        return windowsByKey.map { key, windows in
            AppRingGroupSeed(key: key, label: appLabel(for: key, windows: windows), windows: windows)
        }
    }

    private func appLabel(for key: AppRingKey, windows: [WindowSnapshot]) -> String {
        if let pid = windows.first?.pid,
           let app = NSRunningApplication(processIdentifier: pid),
           let name = app.localizedName,
           !name.isEmpty {
            return name
        }
        if let bundleId = key.bundleId, !bundleId.isEmpty {
            return bundleId
        }
        return "pid:\(key.representativePID)"
    }

    private func selectWindow(
        in group: AppRingGroup,
        monitorID: NSNumber,
        direction: Direction,
        focusedWindowID: UInt32
    ) -> WindowSnapshot? {
        let orderedWindows = group.windows.sorted(by: spatialWindowSort)
        guard !orderedWindows.isEmpty else { return nil }

        if direction == .up || direction == .down {
            guard orderedWindows.count > 1 else { return orderedWindows.first }

            let preferredID = appFocusMemoryStore.preferredWindowID(
                appKey: group.key,
                candidateWindows: orderedWindows,
                monitorID: monitorID,
                policy: navigationConfig.fixedAppRing.inAppWindow
            )
            let baseID = orderedWindows.contains(where: { $0.windowId == focusedWindowID })
                ? focusedWindowID
                : (preferredID ?? orderedWindows[0].windowId)
            let baseIndex = orderedWindows.firstIndex(where: { $0.windowId == baseID }) ?? 0
            let step = direction == .up ? 1 : -1
            let nextIndex = (baseIndex + step + orderedWindows.count) % orderedWindows.count
            return orderedWindows[nextIndex]
        }

        if let preferredID = appFocusMemoryStore.preferredWindowID(
            appKey: group.key,
            candidateWindows: orderedWindows,
            monitorID: monitorID,
            policy: navigationConfig.fixedAppRing.inAppWindow
        ), let match = orderedWindows.first(where: { $0.windowId == preferredID }) {
            return match
        }

        return orderedWindows.first
    }

    private func spatialWindowSort(_ lhs: WindowSnapshot, _ rhs: WindowSnapshot) -> Bool {
        cycleHUDWindowSort(lhs, rhs)
    }

    private func showHUD(for groups: [AppRingGroup], selectedIndex: Int?, selectedWindowID: UInt32?, monitorID: NSNumber) {
        guard hudConfig.enabled else { return }

        let items = buildCycleHUDItems(
            groups: groups,
            selectedIndex: selectedIndex,
            selectedWindowID: selectedWindowID
        )
        let model = CycleHUDModel(items: items, selectedIndex: selectedIndex, monitorID: monitorID)
        hudController.show(model: model, config: hudConfig, timeoutMs: navigationConfig.cycleTimeoutMs)
    }

    private func resolveNoFocusMonitorID(from snapshots: [WindowSnapshot]) -> NSNumber? {
        if let mouseMonitor = ScreenLocator.screenID(containing: mouseLocationProvider()) {
            return mouseMonitor
        }
        return snapshots.compactMap { ScreenLocator.screenID(containing: $0.center) }.first
    }

    private func windowOrdinal(in group: AppRingGroup, windowID: UInt32) -> Int? {
        let orderedWindows = group.windows.sorted(by: spatialWindowSort)
        guard let index = orderedWindows.firstIndex(where: { $0.windowId == windowID }) else {
            return nil
        }
        return index + 1
    }
}
