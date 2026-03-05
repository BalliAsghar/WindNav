import Foundation

@MainActor
final class DirectionalCoordinator {
    private enum Flow: Sendable {
        case navigation
        case browse
    }

    private struct SessionState {
        var flow: Flow
        var orderedWindows: [WindowSnapshot]
        var selectedIndex: Int
        var needsCommitOnRelease: Bool
        var startedAt: DispatchTime
    }

    private struct AppRingKey: Sendable, Hashable, Equatable {
        let rawValue: String
        let bundleId: String?

        init(bundleId: String?, pid: pid_t) {
            self.bundleId = bundleId
            if let bundleId, !bundleId.isEmpty {
                rawValue = "bundle:\(bundleId)"
            } else {
                rawValue = "pid:\(pid)"
            }
        }

        init(window: WindowSnapshot) {
            self.init(bundleId: window.bundleId, pid: window.pid)
        }

        func hash(into hasher: inout Hasher) {
            hasher.combine(rawValue)
        }

        static func == (lhs: AppRingKey, rhs: AppRingKey) -> Bool {
            lhs.rawValue == rhs.rawValue
        }
    }

    private struct AppRingGroupSeed: Sendable {
        let key: AppRingKey
        let label: String
        let windows: [WindowSnapshot]
    }

    private struct AppRingGroup: Sendable {
        let key: AppRingKey
        let label: String
        let windows: [WindowSnapshot]
    }

    private final class AppRingStateStore {
        private var unpinnedFirstSeenOrder: [AppRingKey] = []

        func orderedGroups(
            from seeds: [AppRingGroupSeed],
            ordering: OrderingConfig,
            showEmptyApps: VisibilityConfig.ShowEmptyAppsPolicy
        ) -> [AppRingGroup] {
            guard !seeds.isEmpty else { return [] }

            let seedByKey = Dictionary(uniqueKeysWithValues: seeds.map { ($0.key, $0) })
            var usedKeys = Set<AppRingKey>()
            var ordered: [AppRingGroup] = []

            for bundleID in ordering.pinnedApps {
                if let seed = seeds.first(where: { $0.key.bundleId == bundleID && !usedKeys.contains($0.key) }) {
                    ordered.append(AppRingGroup(key: seed.key, label: seed.label, windows: seed.windows))
                    usedKeys.insert(seed.key)
                }
            }

            let unpinnedSeeds = seeds.filter { !usedKeys.contains($0.key) }
            ordered.append(contentsOf: orderedUnpinnedGroups(from: unpinnedSeeds, seedByKey: seedByKey, policy: ordering.unpinnedApps))

            guard showEmptyApps == .showAtEnd else {
                return ordered
            }

            let windowed = ordered.filter { !$0.windows.allSatisfy(\.isWindowlessApp) }
            let windowless = ordered.filter { $0.windows.allSatisfy(\.isWindowlessApp) }
            return windowed + windowless
        }

        private func orderedUnpinnedGroups(
            from seeds: [AppRingGroupSeed],
            seedByKey: [AppRingKey: AppRingGroupSeed],
            policy: UnpinnedAppsPolicy
        ) -> [AppRingGroup] {
            switch policy {
                case .ignore:
                    unpinnedFirstSeenOrder = []
                    return []

                case .append:
                    let presentKeys = Set(seeds.map(\.key))
                    var order = unpinnedFirstSeenOrder.filter { presentKeys.contains($0) }
                    let existing = Set(order)
                    let unseen = seeds
                        .map(\.key)
                        .filter { !existing.contains($0) }
                        .sorted { lhs, rhs in
                            let lhsSeed = seedByKey[lhs]!
                            let rhsSeed = seedByKey[rhs]!
                            let lhsLabel = lhsSeed.label.localizedCaseInsensitiveCompare(rhsSeed.label)
                            if lhsLabel != .orderedSame {
                                return lhsLabel == .orderedAscending
                            }
                            return lhs.rawValue < rhs.rawValue
                        }
                    order.append(contentsOf: unseen)
                    unpinnedFirstSeenOrder = order

                    return order.compactMap { key in
                        guard let seed = seedByKey[key] else { return nil }
                        return AppRingGroup(key: seed.key, label: seed.label, windows: seed.windows)
                    }
            }
        }
    }

    private final class AppFocusMemoryStore {
        private var lastFocusedWindowByApp: [AppRingKey: UInt32] = [:]

        func recordFocused(window: WindowSnapshot) {
            lastFocusedWindowByApp[AppRingKey(window: window)] = window.windowId
        }

        func preferredWindowID(appKey: AppRingKey, candidateWindows: [WindowSnapshot]) -> UInt32? {
            guard !candidateWindows.isEmpty else { return nil }
            let candidateIDs = Set(candidateWindows.map(\.windowId))
            if let remembered = lastFocusedWindowByApp[appKey], candidateIDs.contains(remembered) {
                return remembered
            }
            return nil
        }

        func prune(using snapshots: [WindowSnapshot]) {
            let visibleWindowIDs = Set(snapshots.map(\.windowId))
            let visibleAppKeys = Set(snapshots.map(AppRingKey.init(window:)))
            lastFocusedWindowByApp = lastFocusedWindowByApp.filter { appKey, windowID in
                visibleAppKeys.contains(appKey) && visibleWindowIDs.contains(windowID)
            }
        }
    }

    private let windowProvider: WindowProvider
    private let focusedWindowProvider: FocusedWindowProvider
    private let focusPerformer: FocusPerformer
    private let appTerminationPerformer: any AppTerminationPerformer
    private let windowClosePerformer: any WindowClosePerformer
    private let hudController: any HUDControlling
    private let thumbnailService: any WindowThumbnailProviding
    private let appRingStateStore: AppRingStateStore
    private let appFocusMemoryStore: AppFocusMemoryStore

    private var config: TabConfig
    private var session: SessionState?
    private var quitRequestedPIDs = Set<pid_t>()
    private var scheduledThumbnailRefresh: DispatchWorkItem?

    init(
        windowProvider: WindowProvider,
        focusedWindowProvider: FocusedWindowProvider,
        focusPerformer: FocusPerformer,
        appTerminationPerformer: any AppTerminationPerformer = NSRunningAppTerminationPerformer(),
        windowClosePerformer: any WindowClosePerformer = AXWindowClosePerformer(),
        hudController: any HUDControlling,
        thumbnailService: any WindowThumbnailProviding = WindowThumbnailService(),
        config: TabConfig
    ) {
        self.windowProvider = windowProvider
        self.focusedWindowProvider = focusedWindowProvider
        self.focusPerformer = focusPerformer
        self.appTerminationPerformer = appTerminationPerformer
        self.windowClosePerformer = windowClosePerformer
        self.hudController = hudController
        self.thumbnailService = thumbnailService
        self.appRingStateStore = AppRingStateStore()
        self.appFocusMemoryStore = AppFocusMemoryStore()
        self.config = config
    }

    func hasActiveSession() -> Bool {
        session != nil
    }

    func handleHotkey(direction: Direction, hotkeyTimestamp: DispatchTime) async {
        switch direction {
            case .left, .right:
                if session?.flow == .browse {
                    await advanceBrowse(direction: direction, hotkeyTimestamp: hotkeyTimestamp)
                } else {
                    await advanceNavigation(direction: direction, hotkeyTimestamp: hotkeyTimestamp)
                }
            case .up, .down:
                await advanceBrowse(direction: direction, hotkeyTimestamp: hotkeyTimestamp)
        }
    }

    func commitOrEndSessionOnModifierRelease(commitTimestamp: DispatchTime) async {
        guard let current = session else { return }
        defer {
            hudController.hide()
            session = nil
            quitRequestedPIDs.removeAll()
            cancelScheduledThumbnailRefresh()
        }

        guard current.flow == .browse else { return }
        guard config.directional.commitOnModifierRelease else { return }
        guard current.needsCommitOnRelease else { return }
        guard current.orderedWindows.indices.contains(current.selectedIndex) else { return }

        let selected = current.orderedWindows[current.selectedIndex]
        do {
            try await focusPerformer.focus(windowId: selected.windowId, pid: selected.pid)
            appFocusMemoryStore.recordFocused(window: selected)
            Logger.info(.navigation, "commit-focus-latency-ms=\(msSince(commitTimestamp)) target=\(selected.windowId)")
        } catch {
            Logger.error(.navigation, "Failed to focus directional selection on release: \(error.localizedDescription)")
        }
    }

    func cancelSession() {
        session = nil
        quitRequestedPIDs.removeAll()
        cancelScheduledThumbnailRefresh()
        hudController.hide()
    }

    func requestQuitSelectedAppInSession() async {
        guard let selected = selectedSnapshot(in: session) else { return }

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
        Logger.info(.navigation, "directional-input=quit-selected-app pid=\(selected.pid) action=\(action)")

        await refreshAfterMutation()
    }

    func requestCloseSelectedWindowInSession() async {
        guard let selected = selectedSnapshot(in: session) else { return }

        let dispatched = windowClosePerformer.close(windowId: selected.windowId, pid: selected.pid)
        Logger.info(
            .navigation,
            "directional-input=close-selected-window window=\(selected.windowId) pid=\(selected.pid) dispatched=\(dispatched)"
        )

        await refreshAfterMutation()
    }

    private func advanceNavigation(direction: Direction, hotkeyTimestamp: DispatchTime) async {
        do {
            let windows = try await orderedWindows(includeWindowless: false)
            guard !windows.isEmpty else {
                cancelSession()
                return
            }

            let currentIndex: Int?
            if let current = session,
               current.flow == .navigation {
                currentIndex = current.selectedIndex
            } else {
                currentIndex = await focusedWindowIndex(in: windows)
            }

            let step = direction == .left ? -1 : 1
            let nextIndex: Int
            if let currentIndex {
                nextIndex = wrappedIndex(currentIndex + step, count: windows.count)
            } else {
                nextIndex = direction == .left ? windows.count - 1 : 0
            }

            let target = windows[nextIndex]
            showHUD(windows: windows, selectedIndex: nextIndex)
            Logger.info(.ui, "hud-selection-latency-ms=\(msSince(hotkeyTimestamp))")

            do {
                try await focusPerformer.focus(windowId: target.windowId, pid: target.pid)
                appFocusMemoryStore.recordFocused(window: target)
            } catch {
                Logger.error(.navigation, "Failed to focus directional target \(target.windowId): \(error.localizedDescription)")
            }

            session = SessionState(
                flow: .navigation,
                orderedWindows: windows,
                selectedIndex: nextIndex,
                needsCommitOnRelease: false,
                startedAt: hotkeyTimestamp
            )
            quitRequestedPIDs.removeAll()
        } catch {
            Logger.error(.windows, "Failed to build directional navigation snapshot: \(error.localizedDescription)")
            cancelSession()
        }
    }

    private func advanceBrowse(direction: Direction, hotkeyTimestamp: DispatchTime) async {
        do {
            let windows = try await orderedWindows(includeWindowless: true)
            guard !windows.isEmpty else {
                cancelSession()
                return
            }

            let previous = session
            let currentIndex: Int?
            if let previous,
               previous.flow == .browse {
                currentIndex = previous.selectedIndex
            } else {
                currentIndex = nil
            }

            let goesForward = direction == .right || direction == .up
            let step = goesForward ? 1 : -1
            let nextIndex: Int
            if let currentIndex {
                nextIndex = wrappedIndex(currentIndex + step, count: windows.count)
            } else {
                nextIndex = goesForward ? 0 : windows.count - 1
            }

            let target = windows[nextIndex]
            showHUD(windows: windows, selectedIndex: nextIndex)
            Logger.info(.ui, "hud-selection-latency-ms=\(msSince(hotkeyTimestamp))")

            let shouldFocusNow = shouldFocusImmediatelyInBrowse(for: direction)
            var needsCommitOnRelease = config.directional.commitOnModifierRelease

            if shouldFocusNow {
                do {
                    try await focusPerformer.focus(windowId: target.windowId, pid: target.pid)
                    appFocusMemoryStore.recordFocused(window: target)
                    needsCommitOnRelease = false
                } catch {
                    Logger.error(.navigation, "Failed to focus browse target \(target.windowId): \(error.localizedDescription)")
                    needsCommitOnRelease = config.directional.commitOnModifierRelease
                }
            }

            session = SessionState(
                flow: .browse,
                orderedWindows: windows,
                selectedIndex: nextIndex,
                needsCommitOnRelease: needsCommitOnRelease,
                startedAt: hotkeyTimestamp
            )
            quitRequestedPIDs.removeAll()
        } catch {
            Logger.error(.windows, "Failed to build directional browse snapshot: \(error.localizedDescription)")
            cancelSession()
        }
    }

    private func refreshAfterMutation() async {
        guard let previous = session else { return }

        let includeWindowless = previous.flow == .browse
        do {
            let windows = try await orderedWindows(includeWindowless: includeWindowless)
            guard !windows.isEmpty else {
                cancelSession()
                return
            }

            let previousSelectedWindowID = previous.orderedWindows[previous.selectedIndex].windowId

            let nextIndex: Int
            if let idx = windows.firstIndex(where: { $0.windowId == previousSelectedWindowID }) {
                nextIndex = idx
            } else {
                nextIndex = min(max(previous.selectedIndex, 0), windows.count - 1)
            }

            session = SessionState(
                flow: previous.flow,
                orderedWindows: windows,
                selectedIndex: nextIndex,
                needsCommitOnRelease: previous.needsCommitOnRelease,
                startedAt: previous.startedAt
            )

            showHUD(windows: windows, selectedIndex: nextIndex)
        } catch {
            Logger.error(.windows, "Failed to refresh directional session: \(error.localizedDescription)")
        }
    }

    private func shouldFocusImmediatelyInBrowse(for direction: Direction) -> Bool {
        if !config.directional.commitOnModifierRelease {
            return true
        }
        if direction == .left || direction == .right {
            return config.directional.browseLeftRightMode == .immediate
        }
        return false
    }

    private func selectedSnapshot(in state: SessionState?) -> WindowSnapshot? {
        guard let state,
              state.orderedWindows.indices.contains(state.selectedIndex)
        else {
            return nil
        }
        return state.orderedWindows[state.selectedIndex]
    }

    private func showHUD(windows: [WindowSnapshot], selectedIndex: Int) {
        let thumbnails = thumbnailService.cachedThumbnails(for: windows.map(\.windowId))
        let windowTotalsByPID = Dictionary(grouping: windows, by: \.pid).mapValues(\.count)
        var nextWindowIndexByPID: [pid_t: Int] = [:]

        let items = windows.enumerated().map { index, window in
            let totalForPID = windowTotalsByPID[window.pid] ?? 1
            let windowIndex = (nextWindowIndexByPID[window.pid] ?? 0) + 1
            nextWindowIndexByPID[window.pid] = windowIndex

            return HUDItem(
                id: "\(window.windowId)",
                label: window.appName ?? window.bundleId ?? "App",
                pid: window.pid,
                isSelected: index == selectedIndex,
                isWindowlessApp: window.isWindowlessApp,
                windowIndexInApp: config.appearance.showWindowCount && totalForPID > 1 ? windowIndex : nil,
                thumbnail: thumbnails[window.windowId]
            )
        }

        hudController.show(
            model: HUDModel(items: items, selectedIndex: selectedIndex),
            appearance: config.appearance
        )

        guard config.appearance.showThumbnails else { return }
        thumbnailService.requestThumbnails(
            for: windows,
            thumbnailWidth: config.appearance.thumbnailWidth
        ) { [weak self] windowID, _ in
            guard let self, let active = self.session else { return }
            guard active.orderedWindows.contains(where: { $0.windowId == windowID }) else { return }
            self.scheduleThumbnailRefresh()
        }
    }

    private func scheduleThumbnailRefresh() {
        guard scheduledThumbnailRefresh == nil else { return }
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.scheduledThumbnailRefresh = nil
            guard let active = self.session else { return }
            self.showHUD(windows: active.orderedWindows, selectedIndex: active.selectedIndex)
        }
        scheduledThumbnailRefresh = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + (1.0 / 60.0), execute: workItem)
    }

    private func cancelScheduledThumbnailRefresh() {
        scheduledThumbnailRefresh?.cancel()
        scheduledThumbnailRefresh = nil
    }

    private func focusedWindowIndex(in windows: [WindowSnapshot]) async -> Int? {
        guard let focusedWindowID = await focusedWindowProvider.focusedWindowID() else { return nil }
        return windows.firstIndex(where: { $0.windowId == focusedWindowID })
    }

    private func orderedWindows(includeWindowless: Bool) async throws -> [WindowSnapshot] {
        let snapshots = try await windowProvider.currentSnapshot()
        appFocusMemoryStore.prune(using: snapshots)

        let filtered = applyFilters(snapshots)
        let candidates = includeWindowless ? filtered : filtered.filter { !$0.isWindowlessApp }
        guard !candidates.isEmpty else { return [] }

        let groups = appGroups(from: candidates)
        let windows = groups.flatMap { group in
            group.windows.sorted(by: snapshotSortOrder(lhs:rhs:))
        }

        return windows
    }

    private func appGroups(from candidates: [WindowSnapshot]) -> [AppRingGroup] {
        let seeds = buildAppRingSeeds(from: candidates)
        return appRingStateStore.orderedGroups(
            from: seeds,
            ordering: config.ordering,
            showEmptyApps: config.visibility.showEmptyApps
        )
    }

    private func buildAppRingSeeds(from candidates: [WindowSnapshot]) -> [AppRingGroupSeed] {
        let grouped = Dictionary(grouping: candidates) { AppRingKey(window: $0) }
        return grouped.keys.sorted { lhs, rhs in
            let lhsSeed = grouped[lhs]!
            let rhsSeed = grouped[rhs]!
            let lhsLabel = appLabel(for: lhsSeed)
            let rhsLabel = appLabel(for: rhsSeed)
            let cmp = lhsLabel.localizedCaseInsensitiveCompare(rhsLabel)
            if cmp != .orderedSame {
                return cmp == .orderedAscending
            }
            return lhs.rawValue < rhs.rawValue
        }.map { key in
            let windows = grouped[key]!
            return AppRingGroupSeed(key: key, label: appLabel(for: windows), windows: windows)
        }
    }

    private func appLabel(for windows: [WindowSnapshot]) -> String {
        if let name = windows.first(where: { $0.appName != nil })?.appName {
            return name
        }
        if let bundle = windows.first(where: { $0.bundleId != nil })?.bundleId {
            return bundle
        }
        return "App"
    }

    private func applyFilters(_ snapshots: [WindowSnapshot]) -> [WindowSnapshot] {
        let excludedNames = Set(config.filters.excludeApps.map { $0.lowercased() })
        let excludedBundleIds = Set(config.filters.excludeBundleIds.map { $0.lowercased() })

        return snapshots.filter { snapshot in
            if !config.visibility.showMinimized && snapshot.isMinimized { return false }
            if !config.visibility.showHidden && snapshot.appIsHidden { return false }
            if !config.visibility.showFullscreen && snapshot.isFullscreen { return false }
            if snapshot.isWindowlessApp && snapshot.bundleId == "com.apple.finder" { return false }
            if config.visibility.showEmptyApps == .hide && snapshot.isWindowlessApp { return false }
            if let appName = snapshot.appName, excludedNames.contains(appName.lowercased()) { return false }
            if let bundleId = snapshot.bundleId, excludedBundleIds.contains(bundleId.lowercased()) { return false }
            return true
        }
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

    private func wrappedIndex(_ index: Int, count: Int) -> Int {
        guard count > 0 else { return 0 }
        let next = index % count
        return next < 0 ? next + count : next
    }

    private func msSince(_ start: DispatchTime) -> Int {
        let now = DispatchTime.now().uptimeNanoseconds
        let elapsed = now - start.uptimeNanoseconds
        return Int(elapsed / 1_000_000)
    }
}
