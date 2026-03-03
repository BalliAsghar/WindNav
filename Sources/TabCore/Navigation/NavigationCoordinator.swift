import Foundation

@MainActor
final class NavigationCoordinator {
    private let windowProvider: WindowProvider
    private let focusedWindowProvider: FocusedWindowProvider
    private let focusPerformer: FocusPerformer
    private let appTerminationPerformer: any AppTerminationPerformer
    private let windowClosePerformer: any WindowClosePerformer
    private let hudController: any HUDControlling

    private var config: TabConfig
    private var focusHistory: [UInt32] = []
    private var cycleSession: CycleSession?
    private var quitRequestedPIDs = Set<pid_t>()

    init(
        windowProvider: WindowProvider,
        focusedWindowProvider: FocusedWindowProvider,
        focusPerformer: FocusPerformer,
        appTerminationPerformer: any AppTerminationPerformer = NSRunningAppTerminationPerformer(),
        windowClosePerformer: any WindowClosePerformer = AXWindowClosePerformer(),
        hudController: any HUDControlling,
        config: TabConfig
    ) {
        self.windowProvider = windowProvider
        self.focusedWindowProvider = focusedWindowProvider
        self.focusPerformer = focusPerformer
        self.appTerminationPerformer = appTerminationPerformer
        self.windowClosePerformer = windowClosePerformer
        self.hudController = hudController
        self.config = config
    }

    func updateConfig(_ config: TabConfig) {
        self.config = config
    }

    func hasActiveCycleSession() -> Bool {
        cycleSession != nil
    }

    func startOrAdvanceCycle(direction: Direction, hotkeyTimestamp: DispatchTime) async {
        let normalizedDirection = normalizeCycleDirection(direction)

        if var session = cycleSession {
            guard !session.ordered.isEmpty else {
                cancelCycleSession()
                return
            }
            session.selectedIndex = wrappedIndex(
                session.selectedIndex + (normalizedDirection == .left ? -1 : 1),
                count: session.ordered.count
            )
            cycleSession = session
            showHUD(for: session)
            Logger.info(.ui, "hud-selection-latency-ms=\(msSince(hotkeyTimestamp))")
            return
        }

        do {
            let snapshots = try await windowProvider.currentSnapshot()
            let filtered = applyFilters(snapshots)
            guard !filtered.isEmpty else {
                cancelCycleSession()
                return
            }

            let focusedWindowID = await focusedWindowProvider.focusedWindowID()
            let ordered = orderByMostRecent(filtered, focusedWindowID: focusedWindowID)
            guard !ordered.isEmpty else {
                cancelCycleSession()
                return
            }

            let selectedIndex = initialSelectionIndex(
                direction: normalizedDirection,
                ordered: ordered,
                focusedWindowID: focusedWindowID
            )

            let session = CycleSession(
                ordered: ordered,
                selectedIndex: selectedIndex,
                startedAt: hotkeyTimestamp
            )
            cycleSession = session
            quitRequestedPIDs.removeAll()
            showHUD(for: session)
            Logger.info(.ui, "hud-selection-latency-ms=\(msSince(hotkeyTimestamp))")
        } catch {
            Logger.error(.windows, "Failed to fetch snapshot for cycle start: \(error.localizedDescription)")
            cancelCycleSession()
        }
    }

    func commitCycleOnModifierRelease(commitTimestamp: DispatchTime) async {
        guard let session = cycleSession else { return }
        defer {
            hudController.hide()
            cycleSession = nil
            quitRequestedPIDs.removeAll()
        }

        guard session.ordered.indices.contains(session.selectedIndex) else { return }
        let selected = session.ordered[session.selectedIndex]

        do {
            let snapshots = try await windowProvider.currentSnapshot()
            let filtered = applyFilters(snapshots)
            guard !filtered.isEmpty else { return }

            guard let resolvedTarget = resolveCommitTarget(selected: selected, from: filtered) else {
                Logger.info(.navigation, "Commit skipped: selected target disappeared")
                return
            }

            do {
                try await focusPerformer.focus(windowId: resolvedTarget.windowId, pid: resolvedTarget.pid)
                updateHistory(resolvedTarget.windowId)
                Logger.info(.navigation, "commit-focus-latency-ms=\(msSince(commitTimestamp)) target=\(resolvedTarget.windowId)")
            } catch {
                Logger.error(.navigation, "Failed to focus window \(resolvedTarget.windowId) on commit: \(error.localizedDescription)")
            }
        } catch {
            Logger.error(.windows, "Failed to fetch snapshot for commit: \(error.localizedDescription)")
        }
    }

    func cancelCycleSession() {
        cycleSession = nil
        quitRequestedPIDs.removeAll()
        hudController.hide()
    }

    func requestQuitSelectedAppInCycle() async {
        guard let session = cycleSession else { return }
        guard session.ordered.indices.contains(session.selectedIndex) else {
            cancelCycleSession()
            return
        }

        let selected = session.ordered[session.selectedIndex]
        let bundleID = appTerminationPerformer.bundleIdentifier(pid: selected.pid) ?? selected.bundleId
        if bundleID == "com.apple.finder" {
            Logger.info(.navigation, "quit-selected-app skipped finder pid=\(selected.pid)")
            return
        }

        let action: String
        if quitRequestedPIDs.contains(selected.pid) {
            action = "force"
            appTerminationPerformer.forceTerminate(pid: selected.pid)
        } else {
            action = "terminate"
            appTerminationPerformer.terminate(pid: selected.pid)
            quitRequestedPIDs.insert(selected.pid)
        }
        Logger.info(.navigation, "cycle-input=quit-selected-app pid=\(selected.pid) action=\(action)")

        do {
            let snapshots = try await windowProvider.currentSnapshot()
            let filtered = applyFilters(snapshots)
            guard !filtered.isEmpty else {
                cancelCycleSession()
                return
            }

            let reconciled = reconcileSessionOrder(previous: session.ordered, filtered: filtered)
            guard !reconciled.isEmpty else {
                cancelCycleSession()
                return
            }

            let nextIndex = nextSelectionIndexAfterSessionRefresh(
                previousSession: session,
                refreshed: reconciled
            )
            let refreshedSession = CycleSession(
                ordered: reconciled,
                selectedIndex: nextIndex,
                startedAt: session.startedAt
            )
            cycleSession = refreshedSession
            showHUD(for: refreshedSession)
            Logger.info(.navigation, "quit-selected-app session-updated remaining=\(reconciled.count) selected-index=\(nextIndex)")
        } catch {
            Logger.error(.windows, "Failed to refresh snapshot after quit request: \(error.localizedDescription)")
        }
    }

    func requestCloseSelectedWindowInCycle() async {
        guard let session = cycleSession else { return }
        guard session.ordered.indices.contains(session.selectedIndex) else {
            cancelCycleSession()
            return
        }

        let selected = session.ordered[session.selectedIndex]
        let dispatched = windowClosePerformer.close(windowId: selected.windowId, pid: selected.pid)
        Logger.info(
            .navigation,
            "cycle-input=close-selected-window window=\(selected.windowId) pid=\(selected.pid) dispatched=\(dispatched)"
        )

        do {
            let snapshots = try await windowProvider.currentSnapshot()
            let filtered = applyFilters(snapshots)
            guard !filtered.isEmpty else {
                cancelCycleSession()
                return
            }

            let reconciled = reconcileSessionOrder(previous: session.ordered, filtered: filtered)
            guard !reconciled.isEmpty else {
                cancelCycleSession()
                return
            }

            let nextIndex = nextSelectionIndexAfterSessionRefresh(
                previousSession: session,
                refreshed: reconciled
            )
            let refreshedSession = CycleSession(
                ordered: reconciled,
                selectedIndex: nextIndex,
                startedAt: session.startedAt
            )
            cycleSession = refreshedSession
            showHUD(for: refreshedSession)
            Logger.info(
                .navigation,
                "close-selected-window session-updated remaining=\(reconciled.count) selected-index=\(nextIndex)"
            )
        } catch {
            Logger.error(.windows, "Failed to refresh snapshot after close request: \(error.localizedDescription)")
        }
    }

    private func resolveCommitTarget(selected: WindowSnapshot, from filtered: [WindowSnapshot]) -> WindowSnapshot? {
        if let exact = filtered.first(where: { $0.windowId == selected.windowId }) {
            return exact
        }
        if let pidMatch = filtered.first(where: { $0.pid == selected.pid }) {
            return pidMatch
        }
        return nil
    }

    private func showHUD(for session: CycleSession) {
        let windowTotalsByPID = Dictionary(grouping: session.ordered, by: \.pid).mapValues(\.count)
        var nextWindowIndexByPID: [pid_t: Int] = [:]
        let items = session.ordered.enumerated().map { entry in
            let (index, snapshot) = entry
            let totalForPID = windowTotalsByPID[snapshot.pid] ?? 1
            let windowIndex = (nextWindowIndexByPID[snapshot.pid] ?? 0) + 1
            nextWindowIndexByPID[snapshot.pid] = windowIndex
            return HUDItem(
                id: "\(snapshot.windowId)",
                label: snapshot.appName ?? snapshot.bundleId ?? "App",
                pid: snapshot.pid,
                isSelected: index == session.selectedIndex,
                windowIndexInApp: config.appearance.showWindowCount && totalForPID > 1 ? windowIndex : nil
            )
        }
        hudController.show(
            model: HUDModel(items: items, selectedIndex: session.selectedIndex),
            appearance: config.appearance
        )
    }

    private func nextSelectionIndexAfterSessionRefresh(
        previousSession: CycleSession,
        refreshed: [WindowSnapshot]
    ) -> Int {
        let currentSelectedID = previousSession.ordered[previousSession.selectedIndex].windowId
        if let sameWindow = refreshed.firstIndex(where: { $0.windowId == currentSelectedID }) {
            return sameWindow
        }

        if refreshed.isEmpty {
            return 0
        }
        let preferred = previousSession.selectedIndex
        if preferred >= refreshed.count {
            return refreshed.count - 1
        }
        return max(0, preferred)
    }

    private func reconcileSessionOrder(previous: [WindowSnapshot], filtered: [WindowSnapshot]) -> [WindowSnapshot] {
        var byWindowID: [UInt32: WindowSnapshot] = [:]
        for snapshot in filtered {
            byWindowID[snapshot.windowId] = snapshot
        }

        var ordered: [WindowSnapshot] = []
        var used = Set<UInt32>()

        for snapshot in previous {
            if let current = byWindowID[snapshot.windowId] {
                ordered.append(current)
                used.insert(current.windowId)
            }
        }

        let remaining = filtered
            .filter { !used.contains($0.windowId) }
            .sorted(by: snapshotSortOrder(lhs:rhs:))
        ordered.append(contentsOf: remaining)
        return ordered
    }

    private func snapshotSortOrder(lhs: WindowSnapshot, rhs: WindowSnapshot) -> Bool {
        let lhsName = lhs.appName ?? lhs.bundleId ?? ""
        let rhsName = rhs.appName ?? rhs.bundleId ?? ""
        let cmp = lhsName.localizedCaseInsensitiveCompare(rhsName)
        if cmp != .orderedSame {
            return cmp == .orderedAscending
        }
        let lhsTitle = lhs.title ?? ""
        let rhsTitle = rhs.title ?? ""
        let titleCmp = lhsTitle.localizedCaseInsensitiveCompare(rhsTitle)
        if titleCmp != .orderedSame {
            return titleCmp == .orderedAscending
        }
        return lhs.windowId < rhs.windowId
    }

    private func applyFilters(_ snapshots: [WindowSnapshot]) -> [WindowSnapshot] {
        let excludedNames = Set(config.filters.excludeApps.map { $0.lowercased() })
        let excludedBundleIds = Set(config.filters.excludeBundleIds.map { $0.lowercased() })

        return snapshots.filter { snapshot in
            if !config.visibility.showMinimized && snapshot.isMinimized { return false }
            if !config.visibility.showHidden && snapshot.appIsHidden { return false }
            if !config.visibility.showFullscreen && snapshot.isFullscreen { return false }
            if !config.visibility.showEmptyApps && snapshot.isWindowlessApp { return false }
            if let appName = snapshot.appName, excludedNames.contains(appName.lowercased()) { return false }
            if let bundleId = snapshot.bundleId, excludedBundleIds.contains(bundleId.lowercased()) { return false }
            return true
        }
    }

    private func orderByMostRecent(_ snapshots: [WindowSnapshot], focusedWindowID: UInt32?) -> [WindowSnapshot] {
        var byWindowID: [UInt32: WindowSnapshot] = [:]
        for snapshot in snapshots {
            byWindowID[snapshot.windowId] = snapshot
        }

        var ordered: [WindowSnapshot] = []
        var used = Set<UInt32>()

        if let focusedWindowID, let focused = byWindowID[focusedWindowID] {
            ordered.append(focused)
            used.insert(focused.windowId)
        }

        for id in focusHistory {
            if let snapshot = byWindowID[id], !used.contains(id) {
                ordered.append(snapshot)
                used.insert(id)
            }
        }

        let remaining = snapshots
            .filter { !used.contains($0.windowId) }
            .sorted(by: snapshotSortOrder(lhs:rhs:))

        ordered.append(contentsOf: remaining)
        return ordered
    }

    private func initialSelectionIndex(direction: Direction, ordered: [WindowSnapshot], focusedWindowID: UInt32?) -> Int {
        let focusedIndex = focusedWindowID.flatMap { id in
            ordered.firstIndex { $0.windowId == id }
        }

        switch direction {
            case .left:
                if let focusedIndex {
                    return wrappedIndex(focusedIndex - 1, count: ordered.count)
                }
                return ordered.count - 1
            case .right, .up, .down, .windowUp, .windowDown:
                if let focusedIndex {
                    return wrappedIndex(focusedIndex + 1, count: ordered.count)
                }
                return 0
        }
    }

    private func normalizeCycleDirection(_ direction: Direction) -> Direction {
        direction == .left ? .left : .right
    }

    private func wrappedIndex(_ index: Int, count: Int) -> Int {
        guard count > 0 else { return 0 }
        let next = index % count
        return next < 0 ? next + count : next
    }

    private func updateHistory(_ windowId: UInt32) {
        focusHistory.removeAll { $0 == windowId }
        focusHistory.insert(windowId, at: 0)
        if focusHistory.count > 512 {
            focusHistory.removeLast(focusHistory.count - 512)
        }
    }

    private func msSince(_ start: DispatchTime) -> Int {
        let now = DispatchTime.now().uptimeNanoseconds
        let elapsed = now - start.uptimeNanoseconds
        return Int(elapsed / 1_000_000)
    }
}
