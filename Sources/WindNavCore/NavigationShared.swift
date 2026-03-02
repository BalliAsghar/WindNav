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
        if isCurrent {
            if let selectedWindowID,
               let resolvedIndex = orderedWindows.firstIndex(where: { $0.windowId == selectedWindowID }) {
                currentWindowIndex = resolvedIndex
            } else if !orderedWindows.isEmpty {
                let selectedWindowText = selectedWindowID.map(String.init) ?? "nil"
                Logger.info(
                    .navigation,
                    "HUD window-index fallback selected-app=\(group.label) key=\(group.key.rawValue) selected-window=\(selectedWindowText) window-count=\(orderedWindows.count)"
                )
                currentWindowIndex = 0
            } else {
                currentWindowIndex = nil
            }
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
            currentWindowIndex: currentWindowIndex,
            isWindowlessApp: representative?.isWindowlessApp ?? false
        )
    }
}

struct FocusedNavigationContext {
    let focused: WindowSnapshot
    let focusedScreen: NSNumber
    let candidates: [WindowSnapshot]
}

struct BrowseSeedContext {
    let groups: [AppRingGroup]
    let monitorID: NSNumber
    let focusedAppKey: AppRingKey?
}

@MainActor
final class NavigationSharedContext {
    private let cache: WindowStateCache
    private let focusedWindowProvider: FocusedWindowProvider
    private let appRingStateStore: AppRingStateStore
    private let appFocusMemoryStore: AppFocusMemoryStore
    private let hudController: any CycleHUDControlling
    private let mouseLocationProvider: @MainActor () -> CGPoint

    init(
        cache: WindowStateCache,
        focusedWindowProvider: FocusedWindowProvider,
        appRingStateStore: AppRingStateStore,
        appFocusMemoryStore: AppFocusMemoryStore,
        hudController: any CycleHUDControlling,
        mouseLocationProvider: @escaping @MainActor () -> CGPoint
    ) {
        self.cache = cache
        self.focusedWindowProvider = focusedWindowProvider
        self.appRingStateStore = appRingStateStore
        self.appFocusMemoryStore = appFocusMemoryStore
        self.hudController = hudController
        self.mouseLocationProvider = mouseLocationProvider
    }

    func refreshAndGetSnapshots() async -> [WindowSnapshot] {
        let snapshots = await cache.refreshAndGetSnapshot()
        appFocusMemoryStore.prune(using: snapshots)
        return snapshots
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

    func resolveFocusedContext(from snapshots: [WindowSnapshot]) async -> FocusedNavigationContext? {
        guard let focusedID = await focusedWindowProvider.focusedWindowID(),
              let focused = snapshots.first(where: { $0.windowId == focusedID }),
              let focusedScreen = ScreenLocator.screenID(containing: focused.center) else {
            return nil
        }
        let candidates = snapshots.filter {
            ScreenLocator.screenID(containing: $0.center) == focusedScreen
        }
        return FocusedNavigationContext(focused: focused, focusedScreen: focusedScreen, candidates: candidates)
    }

    func resolveNoFocusMonitorID(from snapshots: [WindowSnapshot]) -> NSNumber? {
        if let mouseMonitor = ScreenLocator.screenID(containing: mouseLocationProvider()) {
            return mouseMonitor
        }
        return snapshots.compactMap { ScreenLocator.screenID(containing: $0.center) }.first
    }

    func orderedGroupsForMonitor(
        snapshots: [WindowSnapshot],
        preferredMonitorID: NSNumber?,
        config: FixedAppRingConfig,
        showWindowlessApps: ShowWindowlessAppsPolicy,
        allowWindowlessApps: Bool = true
    ) -> (groups: [AppRingGroup], monitorID: NSNumber) {
        let monitorID = preferredMonitorID
            ?? snapshots.compactMap { ScreenLocator.screenID(containing: $0.center) }.first
            ?? NSNumber(value: 0)

        let filteredSnapshots = allowWindowlessApps ? snapshots : snapshots.filter { !$0.isWindowlessApp }
        let allSeeds = buildAppRingSeeds(from: filteredSnapshots)
        let seeds: [AppRingGroupSeed]
        if let preferredMonitorID {
            let eligibleAppKeys = Set(
                filteredSnapshots.compactMap { snapshot -> AppRingKey? in
                    guard ScreenLocator.screenID(containing: snapshot.center) == preferredMonitorID else { return nil }
                    return AppRingKey(window: snapshot)
                }
            )
            if eligibleAppKeys.isEmpty {
                seeds = allSeeds
            } else {
                seeds = allSeeds.filter { eligibleAppKeys.contains($0.key) }
            }
        } else {
            seeds = allSeeds
        }

        let groups = appRingStateStore.orderedGroups(
            from: seeds,
            monitorID: monitorID,
            config: config,
            showWindowlessApps: showWindowlessApps
        )
        return (groups: groups, monitorID: monitorID)
    }

    func resolveBrowseSeedContext(
        from snapshots: [WindowSnapshot],
        config: FixedAppRingConfig,
        showWindowlessApps: ShowWindowlessAppsPolicy
    ) async -> BrowseSeedContext? {
        if let focusedContext = await resolveFocusedContext(from: snapshots) {
            let resolved = orderedGroupsForMonitor(
                snapshots: snapshots,
                preferredMonitorID: focusedContext.focusedScreen,
                config: config,
                showWindowlessApps: showWindowlessApps,
                allowWindowlessApps: true
            )
            if !resolved.groups.isEmpty {
                return BrowseSeedContext(
                    groups: resolved.groups,
                    monitorID: resolved.monitorID,
                    focusedAppKey: AppRingKey(window: focusedContext.focused)
                )
            }
        }

        let preferredMonitorID = resolveNoFocusMonitorID(from: snapshots)
        let resolved = orderedGroupsForMonitor(
            snapshots: snapshots,
            preferredMonitorID: preferredMonitorID,
            config: config,
            showWindowlessApps: showWindowlessApps,
            allowWindowlessApps: true
        )
        guard !resolved.groups.isEmpty else { return nil }
        return BrowseSeedContext(groups: resolved.groups, monitorID: resolved.monitorID, focusedAppKey: nil)
    }

    func selectWindow(
        in group: AppRingGroup,
        monitorID: NSNumber,
        direction: Direction,
        focusedWindowID: UInt32,
        policy: InAppWindowSelectionPolicy
    ) -> WindowSnapshot? {
        let orderedWindows = group.windows.sorted(by: cycleHUDWindowSort)
        guard !orderedWindows.isEmpty else { return nil }

        if direction == .up || direction == .down {
            guard orderedWindows.count > 1 else { return orderedWindows.first }

            let preferredID = appFocusMemoryStore.preferredWindowID(
                appKey: group.key,
                candidateWindows: orderedWindows,
                monitorID: monitorID,
                policy: policy
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
            policy: policy
        ), let match = orderedWindows.first(where: { $0.windowId == preferredID }) {
            return match
        }

        if let monitorMatch = orderedWindows.first(where: {
            ScreenLocator.screenID(containing: $0.center) == monitorID
        }) {
            return monitorMatch
        }

        return orderedWindows.first
    }

    func showHUD(
        groups: [AppRingGroup],
        selectedIndex: Int?,
        selectedWindowID: UInt32?,
        monitorID: NSNumber,
        hudConfig: HUDConfig,
        timeoutMs: Int
    ) {
        guard hudConfig.enabled else { return }
        let items = buildCycleHUDItems(
            groups: groups,
            selectedIndex: selectedIndex,
            selectedWindowID: selectedWindowID
        )
        let model = CycleHUDModel(items: items, selectedIndex: selectedIndex, monitorID: monitorID)
        hudController.show(model: model, config: hudConfig, timeoutMs: timeoutMs)
    }

    func hideHUD() {
        hudController.hide()
    }

    func recordFocused(window: WindowSnapshot, monitorID: NSNumber) {
        appFocusMemoryStore.recordFocused(window: window, monitorID: monitorID)
    }

    func windowOrdinal(in group: AppRingGroup, windowID: UInt32) -> Int? {
        let orderedWindows = group.windows.sorted(by: cycleHUDWindowSort)
        guard let index = orderedWindows.firstIndex(where: { $0.windowId == windowID }) else {
            return nil
        }
        return index + 1
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
}
