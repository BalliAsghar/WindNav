import Foundation

@MainActor
final class NavigationCoordinator {
    private struct CycleSession {
        let ordered: [WindowSnapshot]
        var selectedIndex: Int
        let startedAt: DispatchTime
    }

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

    func hasActiveCycleSession() -> Bool {
        cycleSession != nil
    }

    func startOrAdvanceCycle(direction: Direction, hotkeyTimestamp: DispatchTime) async {
        let normalizedDirection = direction == .left ? Direction.left : Direction.right

        if var session = cycleSession {
            guard !session.ordered.isEmpty else {
                cancelCycleSession()
                return
            }

            let step = normalizedDirection == .left ? -1 : 1
            session.selectedIndex = WindowSnapshotSupport.wrappedIndex(
                session.selectedIndex + step,
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
                Logger.error(
                    .navigation,
                    "Failed to focus window \(resolvedTarget.windowId) on commit: \(error.localizedDescription)"
                )
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

        await refreshSessionAfterMutation(previousSession: session, logTag: "quit-selected-app")
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

        await refreshSessionAfterMutation(previousSession: session, logTag: "close-selected-window")
    }

    private func refreshSessionAfterMutation(previousSession: CycleSession, logTag: String) async {
        do {
            let snapshots = try await windowProvider.currentSnapshot()
            let filtered = applyFilters(snapshots)
            guard !filtered.isEmpty else {
                cancelCycleSession()
                return
            }

            let reconciled = reconcileSessionOrder(previous: previousSession.ordered, filtered: filtered)
            guard !reconciled.isEmpty else {
                cancelCycleSession()
                return
            }

            let nextIndex = nextSelectionIndexAfterSessionRefresh(
                previousSession: previousSession,
                refreshed: reconciled
            )
            let refreshedSession = CycleSession(
                ordered: reconciled,
                selectedIndex: nextIndex,
                startedAt: previousSession.startedAt
            )
            cycleSession = refreshedSession
            showHUD(for: refreshedSession)
            Logger.info(.navigation, "\(logTag) session-updated remaining=\(reconciled.count) selected-index=\(nextIndex)")
        } catch {
            Logger.error(.windows, "Failed to refresh snapshot after \(logTag) request: \(error.localizedDescription)")
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
        hudController.show(
            model: HUDModelFactory.makeModel(
                windows: session.ordered,
                selectedIndex: session.selectedIndex,
                appearance: config.appearance
            ),
            appearance: config.appearance
        )
    }

    private func nextSelectionIndexAfterSessionRefresh(previousSession: CycleSession, refreshed: [WindowSnapshot]) -> Int {
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
            .sorted(by: WindowSnapshotSupport.snapshotSortOrder(lhs:rhs:))
        ordered.append(contentsOf: remaining)
        return WindowSnapshotSupport.applyWindowlessOrdering(
            ordered,
            showEmptyApps: config.visibility.showEmptyApps
        )
    }

    private func applyFilters(_ snapshots: [WindowSnapshot]) -> [WindowSnapshot] {
        let filtered = WindowSnapshotSupport.applyFilters(
            snapshots,
            visibility: config.visibility,
            filters: config.filters
        )
        return WindowSnapshotSupport.applyWindowlessOrdering(
            filtered,
            showEmptyApps: config.visibility.showEmptyApps
        )
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
            .sorted(by: WindowSnapshotSupport.snapshotSortOrder(lhs:rhs:))
        ordered.append(contentsOf: remaining)
        return WindowSnapshotSupport.applyWindowlessOrdering(
            ordered,
            showEmptyApps: config.visibility.showEmptyApps
        )
    }

    private func initialSelectionIndex(direction: Direction, ordered: [WindowSnapshot], focusedWindowID: UInt32?) -> Int {
        let focusedIndex = focusedWindowID.flatMap { id in
            ordered.firstIndex { $0.windowId == id }
        }

        if direction == .left {
            if let focusedIndex {
                return WindowSnapshotSupport.wrappedIndex(focusedIndex - 1, count: ordered.count)
            }
            return ordered.count - 1
        }

        if let focusedIndex {
            return WindowSnapshotSupport.wrappedIndex(focusedIndex + 1, count: ordered.count)
        }
        return 0
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
