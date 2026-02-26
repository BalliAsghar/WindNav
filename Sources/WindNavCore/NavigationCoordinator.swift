import AppKit
import Foundation

@MainActor
final class NavigationCoordinator {
    private let cache: WindowStateCache
    private let focusedWindowProvider: FocusedWindowProvider
    private let focusPerformer: FocusPerformer
    private let navigator: LogicalCycleNavigator
    private let mruOrderStore: MRUWindowOrderStore
    private let appRingStateStore: AppRingStateStore
    private let appFocusMemoryStore: AppFocusMemoryStore
    private let hudController: CycleHUDController

    private var navigationConfig: NavigationConfig
    private var hudConfig: HUDConfig
    private var cycleSession: CycleSessionState?

    private var pendingDirections: [Direction] = []
    private var isProcessing = false

    init(
        cache: WindowStateCache,
        focusedWindowProvider: FocusedWindowProvider,
        focusPerformer: FocusPerformer,
        navigator: LogicalCycleNavigator,
        mruOrderStore: MRUWindowOrderStore,
        appRingStateStore: AppRingStateStore,
        appFocusMemoryStore: AppFocusMemoryStore,
        hudController: CycleHUDController,
        navigationConfig: NavigationConfig,
        hudConfig: HUDConfig
    ) {
        self.cache = cache
        self.focusedWindowProvider = focusedWindowProvider
        self.focusPerformer = focusPerformer
        self.navigator = navigator
        self.mruOrderStore = mruOrderStore
        self.appRingStateStore = appRingStateStore
        self.appFocusMemoryStore = appFocusMemoryStore
        self.hudController = hudController
        self.navigationConfig = navigationConfig
        self.hudConfig = hudConfig
    }

    func updateConfig(navigation: NavigationConfig, hud: HUDConfig) {
        navigationConfig = navigation
        hudConfig = hud
        cycleSession = nil
        if !hud.enabled {
            hudController.hide()
        }
        Logger.info(.navigation, "Updated navigation config")
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
        mruOrderStore.syncVisibleWindowIDs(snapshots.map(\.windowId))

        guard let focusedID = await focusedWindowProvider.focusedWindowID() else {
            Logger.info(.navigation, "No focused window detected")
            return
        }
        guard let focused = snapshots.first(where: { $0.windowId == focusedID }) else {
            Logger.info(.navigation, "Focused window \(focusedID) is not in current snapshot")
            return
        }
        mruOrderStore.promote(focused.windowId)

        guard let focusedScreen = ScreenLocator.screenID(containing: focused.center) else {
            Logger.info(.navigation, "Focused window \(focused.windowId) is not on an active screen")
            return
        }

        let candidates = snapshots.filter {
            ScreenLocator.screenID(containing: $0.center) == focusedScreen
        }
        Logger.info(.navigation, "Direction=\(direction.rawValue) focused=\(focused.windowId) candidates=\(candidates.count)")
        appFocusMemoryStore.recordFocused(window: focused, monitorID: focusedScreen)

        switch navigationConfig.policy {
            case .mruCycle:
                hudController.hide()
                await handleMRUCycle(direction: direction, focused: focused, candidates: candidates, focusedScreen: focusedScreen)
            case .fixedAppRing:
                cycleSession = nil
                await handleFixedAppRing(direction: direction, focused: focused, candidates: candidates, focusedScreen: focusedScreen)
        }
    }

    private func handleMRUCycle(
        direction: Direction,
        focused: WindowSnapshot,
        candidates: [WindowSnapshot],
        focusedScreen: NSNumber
    ) async {
        let candidateSet = Set(candidates.map(\.windowId))
        let freshOrderedIDs = mruOrderStore.orderedIDs(within: candidateSet)
        let now = Date()
        let resolution = CycleSessionResolver.resolve(
            existing: cycleSession,
            monitorID: focusedScreen,
            candidateSet: candidateSet,
            now: now,
            timeoutMs: navigationConfig.cycleTimeoutMs,
            freshOrderedWindowIDs: freshOrderedIDs
        )
        cycleSession = resolution.state

        if let reason = resolution.resetReason {
            Logger.info(.navigation, "Cycle session reset reason=\(reason.rawValue)")
        } else if resolution.reusedSession {
            Logger.info(.navigation, "Cycle session reused")
        } else {
            Logger.info(.navigation, "Cycle session started")
        }
        Logger.info(.navigation, "Ordered candidate count=\(resolution.orderedWindowIDs.count)")

        let candidateByID = Dictionary(uniqueKeysWithValues: candidates.map { ($0.windowId, $0) })
        let orderedCandidates = resolution.orderedWindowIDs.compactMap { candidateByID[$0] }

        guard let target = navigator.target(from: focused, direction: direction, orderedCandidates: orderedCandidates) else {
            Logger.info(.navigation, "No target window in direction \(direction.rawValue)")
            return
        }
        Logger.info(.navigation, "Selected target window \(target.windowId)")

        do {
            try await focusPerformer.focus(windowId: target.windowId, pid: target.pid)
            mruOrderStore.promote(target.windowId)
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

        guard orderedGroups.count > 1 else {
            Logger.info(.navigation, "Fixed app ring has only one app group")
            return
        }

        let focusedAppKey = AppRingKey(window: focused)
        guard let currentIndex = orderedGroups.firstIndex(where: { $0.key == focusedAppKey }) else {
            Logger.info(.navigation, "Focused app \(focusedAppKey.rawValue) not found in fixed app ring")
            return
        }

        let step = direction == .right ? 1 : -1
        let targetIndex = (currentIndex + step + orderedGroups.count) % orderedGroups.count
        let targetGroup = orderedGroups[targetIndex]

        guard let target = selectWindow(in: targetGroup, monitorID: focusedScreen) else {
            Logger.info(.navigation, "No target window in app group \(targetGroup.key.rawValue)")
            return
        }

        Logger.info(
            .navigation,
            "Fixed app ring direction=\(direction.rawValue) apps=\(orderedGroups.count) focused-app=\(orderedGroups[currentIndex].label) target-app=\(targetGroup.label)"
        )
        Logger.info(.navigation, "Fixed app ring selected window \(target.windowId) policy=\(navigationConfig.fixedAppRing.inAppWindow.rawValue)")

        showHUD(for: orderedGroups, selectedIndex: targetIndex, monitorID: focusedScreen)

        do {
            try await focusPerformer.focus(windowId: target.windowId, pid: target.pid)
            mruOrderStore.promote(target.windowId)
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

    private func selectWindow(in group: AppRingGroup, monitorID: NSNumber) -> WindowSnapshot? {
        if let preferredID = appFocusMemoryStore.preferredWindowID(
            appKey: group.key,
            candidateWindows: group.windows,
            monitorID: monitorID,
            policy: navigationConfig.fixedAppRing.inAppWindow
        ), let match = group.windows.first(where: { $0.windowId == preferredID }) {
            return match
        }

        return group.windows.sorted(by: spatialWindowSort).first
    }

    private func spatialWindowSort(_ lhs: WindowSnapshot, _ rhs: WindowSnapshot) -> Bool {
        if lhs.frame.minX != rhs.frame.minX { return lhs.frame.minX < rhs.frame.minX }
        if lhs.frame.minY != rhs.frame.minY { return lhs.frame.minY < rhs.frame.minY }
        return lhs.windowId < rhs.windowId
    }

    private func showHUD(for groups: [AppRingGroup], selectedIndex: Int, monitorID: NSNumber) {
        guard hudConfig.enabled else { return }

        let items = groups.enumerated().map { index, group in
            let representative = group.windows.first
            return CycleHUDItem(
                label: group.label,
                iconPID: representative?.pid ?? 0,
                iconBundleId: representative?.bundleId,
                isPinned: group.isPinned,
                isCurrent: index == selectedIndex
            )
        }
        let model = CycleHUDModel(items: items, selectedIndex: selectedIndex, monitorID: monitorID)
        let hideDelayMs = hudConfig.hideDelayMs ?? navigationConfig.cycleTimeoutMs
        hudController.show(model: model, config: hudConfig, timeoutMs: hideDelayMs)
    }
}
