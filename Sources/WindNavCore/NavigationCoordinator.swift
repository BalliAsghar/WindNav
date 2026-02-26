import Foundation

@MainActor
final class NavigationCoordinator {
    private let cache: WindowStateCache
    private let focusedWindowProvider: FocusedWindowProvider
    private let focusPerformer: FocusPerformer
    private let navigator: LogicalCycleNavigator
    private let mruOrderStore: MRUWindowOrderStore

    private var navigationConfig: NavigationConfig
    private var cycleSession: CycleSessionState?

    private var pendingDirections: [Direction] = []
    private var isProcessing = false

    init(
        cache: WindowStateCache,
        focusedWindowProvider: FocusedWindowProvider,
        focusPerformer: FocusPerformer,
        navigator: LogicalCycleNavigator,
        mruOrderStore: MRUWindowOrderStore,
        navigationConfig: NavigationConfig
    ) {
        self.cache = cache
        self.focusedWindowProvider = focusedWindowProvider
        self.focusPerformer = focusPerformer
        self.navigator = navigator
        self.mruOrderStore = mruOrderStore
        self.navigationConfig = navigationConfig
    }

    func updateConfig(_ config: NavigationConfig) {
        navigationConfig = config
        cycleSession = nil
        Logger.info(.navigation, "Updated navigation config")
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
            return
        }
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
            switch navigationConfig.noCandidate {
                case .noop:
                    Logger.info(.navigation, "No target window in direction \(direction.rawValue)")
                    return
            }
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
}
