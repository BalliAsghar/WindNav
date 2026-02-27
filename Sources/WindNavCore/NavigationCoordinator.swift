import AppKit
import Foundation

@MainActor
final class NavigationCoordinator {
    private let cache: WindowStateCache
    private let focusedWindowProvider: FocusedWindowProvider
    private let focusPerformer: FocusPerformer
    private let appRingStateStore: AppRingStateStore
    private let appFocusMemoryStore: AppFocusMemoryStore
    private let hudController: CycleHUDController

    private var navigationConfig: NavigationConfig
    private var hudConfig: HUDConfig

    private enum PendingAction {
        case direction(Direction)
        case hudTriggerStep(Direction)
        case endCycleSessionOnModifierRelease
        case endHUDTriggerSessionOnModifierRelease(commit: Bool)
    }

    private struct HUDTriggerSession {
        let monitorID: NSNumber
        let groups: [AppRingGroup]
        var selectedIndex: Int
        var selectedWindowID: UInt32
    }

    private var pendingActions: [PendingAction] = []
    private var isProcessing = false
    private var hudTriggerSession: HUDTriggerSession?

    init(
        cache: WindowStateCache,
        focusedWindowProvider: FocusedWindowProvider,
        focusPerformer: FocusPerformer,
        appRingStateStore: AppRingStateStore,
        appFocusMemoryStore: AppFocusMemoryStore,
        hudController: CycleHUDController,
        navigationConfig: NavigationConfig,
        hudConfig: HUDConfig
    ) {
        self.cache = cache
        self.focusedWindowProvider = focusedWindowProvider
        self.focusPerformer = focusPerformer
        self.appRingStateStore = appRingStateStore
        self.appFocusMemoryStore = appFocusMemoryStore
        self.hudController = hudController
        self.navigationConfig = navigationConfig
        self.hudConfig = hudConfig
    }

    func updateConfig(navigation: NavigationConfig, hud: HUDConfig) {
        navigationConfig = navigation
        hudConfig = hud
        if !hud.enabled {
            hudTriggerSession = nil
            hudController.hide()
        }
        Logger.info(.navigation, "Updated navigation config")
    }

    func endCycleSessionOnModifierRelease() {
        pendingActions.append(.endCycleSessionOnModifierRelease)
        processQueueIfNeeded()
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
        pendingActions.append(.direction(direction))
        Logger.info(.navigation, "Enqueued direction \(direction.rawValue)")
        processQueueIfNeeded()
    }

    func enqueueHUDTriggerStep(direction: Direction) {
        pendingActions.append(.hudTriggerStep(direction))
        Logger.info(.navigation, "Enqueued hud-trigger step \(direction.rawValue)")
        processQueueIfNeeded()
    }

    func endHUDTriggerSessionOnModifierRelease(commit: Bool) {
        pendingActions.append(.endHUDTriggerSessionOnModifierRelease(commit: commit))
        processQueueIfNeeded()
    }

    private func processQueueIfNeeded() {
        guard !isProcessing else { return }
        isProcessing = true

        Task { @MainActor in
            while !pendingActions.isEmpty {
                let action = pendingActions.removeFirst()
                switch action {
                    case .direction(let direction):
                        await handle(direction)
                    case .hudTriggerStep(let direction):
                        await handleHUDTriggerStep(direction: direction)
                    case .endCycleSessionOnModifierRelease:
                        handleEndCycleSessionOnModifierRelease()
                    case .endHUDTriggerSessionOnModifierRelease(let commit):
                        await handleEndHUDTriggerSessionOnModifierRelease(commit: commit)
                }
            }
            isProcessing = false
        }
    }

    private func handle(_ direction: Direction) async {
        clearHUDTriggerSessionIfNeeded(reason: "directional hotkey")

        let snapshots = await cache.refreshAndGetSnapshot()
        guard !snapshots.isEmpty else {
            Logger.info(.navigation, "No windows available for navigation")
            hudController.hide()
            return
        }
        appFocusMemoryStore.prune(using: snapshots)

        guard let focusedID = await focusedWindowProvider.focusedWindowID() else {
            Logger.info(.navigation, "No focused window detected")
            return
        }
        guard let focused = snapshots.first(where: { $0.windowId == focusedID }) else {
            Logger.info(.navigation, "Focused window \(focusedID) is not in current snapshot")
            return
        }

        guard let focusedScreen = ScreenLocator.screenID(containing: focused.center) else {
            Logger.info(.navigation, "Focused window \(focused.windowId) is not on an active screen")
            return
        }

        let candidates = snapshots.filter {
            ScreenLocator.screenID(containing: $0.center) == focusedScreen
        }
        Logger.info(.navigation, "Direction=\(direction.rawValue) focused=\(focused.windowId) candidates=\(candidates.count)")
        appFocusMemoryStore.recordFocused(window: focused, monitorID: focusedScreen)
        await handleFixedAppRing(direction: direction, focused: focused, candidates: candidates, focusedScreen: focusedScreen)
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

    private func handleEndCycleSessionOnModifierRelease() {
        hudController.hide()
        Logger.info(.navigation, "Cycle session ended on modifier release")
    }

    private func handleHUDTriggerStep(direction: Direction) async {
        if var session = hudTriggerSession {
            guard !session.groups.isEmpty else {
                hudTriggerSession = nil
                hudController.hide()
                return
            }

            if session.groups.count > 1 {
                let delta = direction == .left ? -1 : 1
                session.selectedIndex = (session.selectedIndex + delta + session.groups.count) % session.groups.count
            }

            let selectedGroup = session.groups[session.selectedIndex]
            guard let selectedWindow = selectWindow(
                in: selectedGroup,
                monitorID: session.monitorID,
                direction: direction,
                focusedWindowID: session.selectedWindowID
            ) else {
                Logger.info(.navigation, "HUD trigger could not resolve a target window")
                return
            }

            session.selectedWindowID = selectedWindow.windowId
            hudTriggerSession = session
            showHUD(
                for: session.groups,
                selectedIndex: session.selectedIndex,
                selectedWindowID: session.selectedWindowID,
                monitorID: session.monitorID,
                timeoutMs: 0
            )
            Logger.info(.navigation, "HUD trigger moved selection direction=\(direction.rawValue) index=\(session.selectedIndex)")
            return
        }

        await startHUDTriggerSession()
    }

    private func startHUDTriggerSession() async {
        let snapshots = await cache.refreshAndGetSnapshot()
        guard !snapshots.isEmpty else {
            Logger.info(.navigation, "HUD trigger ignored: no windows available")
            hudController.hide()
            return
        }
        appFocusMemoryStore.prune(using: snapshots)

        guard let focusedID = await focusedWindowProvider.focusedWindowID() else {
            Logger.info(.navigation, "HUD trigger ignored: no focused window detected")
            return
        }
        guard let focused = snapshots.first(where: { $0.windowId == focusedID }) else {
            Logger.info(.navigation, "HUD trigger ignored: focused window \(focusedID) not in snapshot")
            return
        }
        guard let focusedScreen = ScreenLocator.screenID(containing: focused.center) else {
            Logger.info(.navigation, "HUD trigger ignored: focused window is not on an active screen")
            return
        }

        let candidates = snapshots.filter {
            ScreenLocator.screenID(containing: $0.center) == focusedScreen
        }
        let seeds = buildAppRingSeeds(from: candidates)
        let orderedGroups = appRingStateStore.orderedGroups(
            from: seeds,
            monitorID: focusedScreen,
            config: navigationConfig.fixedAppRing
        )

        guard !orderedGroups.isEmpty else {
            Logger.info(.navigation, "HUD trigger ignored: no app groups in fixed app ring")
            return
        }

        let focusedAppKey = AppRingKey(window: focused)
        guard let currentIndex = orderedGroups.firstIndex(where: { $0.key == focusedAppKey }) else {
            Logger.info(.navigation, "HUD trigger ignored: focused app not found in fixed app ring")
            return
        }

        let currentGroup = orderedGroups[currentIndex]
        let selectedWindow = currentGroup.windows.first(where: { $0.windowId == focused.windowId })
            ?? selectWindow(in: currentGroup, monitorID: focusedScreen, direction: .right, focusedWindowID: focused.windowId)
        guard let selectedWindow else {
            Logger.info(.navigation, "HUD trigger ignored: no selectable window in focused app group")
            return
        }

        appFocusMemoryStore.recordFocused(window: focused, monitorID: focusedScreen)
        hudTriggerSession = HUDTriggerSession(
            monitorID: focusedScreen,
            groups: orderedGroups,
            selectedIndex: currentIndex,
            selectedWindowID: selectedWindow.windowId
        )
        showHUD(
            for: orderedGroups,
            selectedIndex: currentIndex,
            selectedWindowID: selectedWindow.windowId,
            monitorID: focusedScreen,
            timeoutMs: 0
        )
        Logger.info(.navigation, "HUD trigger session started selected-app=\(orderedGroups[currentIndex].label)")
    }

    private func handleEndHUDTriggerSessionOnModifierRelease(commit: Bool) async {
        guard let session = hudTriggerSession else { return }
        hudTriggerSession = nil
        defer { hudController.hide() }

        guard commit else {
            Logger.info(.navigation, "HUD trigger session ended on modifier release (hide-only)")
            return
        }

        guard session.selectedIndex >= 0, session.selectedIndex < session.groups.count else {
            Logger.info(.navigation, "HUD trigger commit skipped: selection index out of range")
            return
        }

        let selectedGroup = session.groups[session.selectedIndex]
        guard let target = selectedGroup.windows.first(where: { $0.windowId == session.selectedWindowID }) else {
            Logger.info(.navigation, "HUD trigger commit skipped: selected window not found")
            return
        }

        do {
            try await focusPerformer.focus(windowId: target.windowId, pid: target.pid)
            appFocusMemoryStore.recordFocused(window: target, monitorID: session.monitorID)
            Logger.info(.navigation, "HUD trigger committed window \(target.windowId)")
        } catch {
            Logger.error(.navigation, "HUD trigger commit failed for window \(target.windowId): \(error.localizedDescription)")
        }
    }

    private func clearHUDTriggerSessionIfNeeded(reason: String) {
        guard hudTriggerSession != nil else { return }
        hudTriggerSession = nil
        hudController.hide()
        Logger.info(.navigation, "HUD trigger session cleared (\(reason))")
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
        if lhs.frame.minX != rhs.frame.minX { return lhs.frame.minX < rhs.frame.minX }
        if lhs.frame.minY != rhs.frame.minY { return lhs.frame.minY < rhs.frame.minY }
        return lhs.windowId < rhs.windowId
    }

    private func showHUD(
        for groups: [AppRingGroup],
        selectedIndex: Int,
        selectedWindowID: UInt32,
        monitorID: NSNumber,
        timeoutMs: Int? = nil
    ) {
        guard hudConfig.enabled else { return }

        let items = groups.enumerated().map { index, group in
            let representative = group.windows.first
            let orderedWindows = group.windows.sorted(by: spatialWindowSort)
            return CycleHUDItem(
                label: group.label,
                iconPID: representative?.pid ?? 0,
                iconBundleId: representative?.bundleId,
                isPinned: group.isPinned,
                isCurrent: index == selectedIndex,
                windowCount: orderedWindows.count,
                currentWindowIndex: index == selectedIndex
                    ? orderedWindows.firstIndex(where: { $0.windowId == selectedWindowID })
                    : nil
            )
        }
        let model = CycleHUDModel(items: items, selectedIndex: selectedIndex, monitorID: monitorID)
        hudController.show(model: model, config: hudConfig, timeoutMs: timeoutMs ?? navigationConfig.cycleTimeoutMs)
    }

    private func windowOrdinal(in group: AppRingGroup, windowID: UInt32) -> Int? {
        let orderedWindows = group.windows.sorted(by: spatialWindowSort)
        guard let index = orderedWindows.firstIndex(where: { $0.windowId == windowID }) else {
            return nil
        }
        return index + 1
    }
}
