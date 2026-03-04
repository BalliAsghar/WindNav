import Foundation

@MainActor
final class DirectionalCoordinator {
    private enum Flow: Sendable {
        case navigation
        case browse
    }

    private struct SessionState {
        var flow: Flow
        var orderedGroups: [AppRingGroup]
        var selectedIndex: Int?
        var selectedWindowID: UInt32?
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
    private let appRingStateStore: AppRingStateStore
    private let appFocusMemoryStore: AppFocusMemoryStore

    private var config: TabConfig
    private var session: SessionState?
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
        }

        guard current.flow == .browse else { return }
        guard config.directional.commitOnModifierRelease else { return }
        guard current.needsCommitOnRelease else { return }
        guard let selected = await resolveCommitTarget(from: current) else { return }

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
            let groups = try await appGroups(includeWindowless: false)
            guard !groups.isEmpty else {
                cancelSession()
                return
            }

            let currentIndex: Int?
            if let current = session,
               current.flow == .navigation,
               let selectedIndex = current.selectedIndex,
               current.orderedGroups.indices.contains(selectedIndex),
               let idx = groups.firstIndex(where: { $0.key == current.orderedGroups[selectedIndex].key }) {
                currentIndex = idx
            } else {
                currentIndex = await focusedGroupIndex(in: groups)
            }

            let step = direction == .left ? -1 : 1
            let nextIndex: Int
            if let currentIndex {
                nextIndex = wrappedIndex(currentIndex + step, count: groups.count)
            } else {
                nextIndex = direction == .left ? groups.count - 1 : 0
            }

            guard let target = selectWindow(in: groups[nextIndex]) else {
                cancelSession()
                return
            }

            showHUD(groups: groups, selectedIndex: nextIndex)
            Logger.info(.ui, "hud-selection-latency-ms=\(msSince(hotkeyTimestamp))")

            do {
                try await focusPerformer.focus(windowId: target.windowId, pid: target.pid)
                appFocusMemoryStore.recordFocused(window: target)
            } catch {
                Logger.error(.navigation, "Failed to focus directional target \(target.windowId): \(error.localizedDescription)")
            }

            session = SessionState(
                flow: .navigation,
                orderedGroups: groups,
                selectedIndex: nextIndex,
                selectedWindowID: target.windowId,
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
            let groups = try await appGroups(includeWindowless: true)
            guard !groups.isEmpty else {
                cancelSession()
                return
            }

            let previous = session
            var currentIndex: Int?
            if let previous,
               previous.flow == .browse,
               let selectedIndex = previous.selectedIndex,
               previous.orderedGroups.indices.contains(selectedIndex),
               let idx = groups.firstIndex(where: { $0.key == previous.orderedGroups[selectedIndex].key }) {
                currentIndex = idx
            }

            let goesForward = direction == .right || direction == .up
            let step = goesForward ? 1 : -1
            let nextIndex: Int
            if let currentIndex {
                nextIndex = wrappedIndex(currentIndex + step, count: groups.count)
            } else {
                nextIndex = goesForward ? 0 : groups.count - 1
            }

            guard let target = selectWindow(in: groups[nextIndex]) else {
                cancelSession()
                return
            }

            showHUD(groups: groups, selectedIndex: nextIndex)
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
                orderedGroups: groups,
                selectedIndex: nextIndex,
                selectedWindowID: target.windowId,
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
            let groups = try await appGroups(includeWindowless: includeWindowless)
            guard !groups.isEmpty else {
                cancelSession()
                return
            }

            let previousSelectedKey: AppRingKey? = {
                guard let index = previous.selectedIndex, previous.orderedGroups.indices.contains(index) else {
                    return nil
                }
                return previous.orderedGroups[index].key
            }()

            let nextIndex: Int
            if let previousSelectedKey, let idx = groups.firstIndex(where: { $0.key == previousSelectedKey }) {
                nextIndex = idx
            } else if let oldIndex = previous.selectedIndex {
                nextIndex = min(max(oldIndex, 0), groups.count - 1)
            } else {
                nextIndex = 0
            }

            let selectedWindow = selectWindow(in: groups[nextIndex])
            session = SessionState(
                flow: previous.flow,
                orderedGroups: groups,
                selectedIndex: nextIndex,
                selectedWindowID: selectedWindow?.windowId,
                needsCommitOnRelease: previous.needsCommitOnRelease,
                startedAt: previous.startedAt
            )

            showHUD(groups: groups, selectedIndex: nextIndex)
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
              let selectedIndex = state.selectedIndex,
              state.orderedGroups.indices.contains(selectedIndex)
        else {
            return nil
        }

        let group = state.orderedGroups[selectedIndex]
        if let selectedWindowID = state.selectedWindowID,
           let match = group.windows.first(where: { $0.windowId == selectedWindowID }) {
            return match
        }
        return selectWindow(in: group)
    }

    private func resolveCommitTarget(from state: SessionState) async -> WindowSnapshot? {
        let selectedKey: AppRingKey? = {
            guard let selectedIndex = state.selectedIndex, state.orderedGroups.indices.contains(selectedIndex) else {
                return nil
            }
            return state.orderedGroups[selectedIndex].key
        }()

        guard let selectedKey else {
            return selectedSnapshot(in: state)
        }

        guard let groups = try? await appGroups(includeWindowless: true),
              let group = groups.first(where: { $0.key == selectedKey }) else {
            return nil
        }

        if let selectedWindowID = state.selectedWindowID,
           let exact = group.windows.first(where: { $0.windowId == selectedWindowID }) {
            return exact
        }
        return selectWindow(in: group)
    }

    private func showHUD(groups: [AppRingGroup], selectedIndex: Int?) {
        let items = groups.enumerated().map { index, group in
            let representative = group.windows.sorted(by: snapshotSortOrder(lhs:rhs:)).first
            return HUDItem(
                id: group.key.rawValue,
                label: group.label,
                pid: representative?.pid ?? 0,
                isSelected: index == selectedIndex,
                isWindowlessApp: group.windows.allSatisfy(\.isWindowlessApp),
                windowIndexInApp: nil
            )
        }

        hudController.show(
            model: HUDModel(items: items, selectedIndex: selectedIndex),
            appearance: config.appearance
        )
    }

    private func selectWindow(in group: AppRingGroup) -> WindowSnapshot? {
        let ordered = group.windows.sorted(by: snapshotSortOrder(lhs:rhs:))
        guard !ordered.isEmpty else { return nil }

        if let preferredID = appFocusMemoryStore.preferredWindowID(appKey: group.key, candidateWindows: ordered),
           let preferred = ordered.first(where: { $0.windowId == preferredID }) {
            return preferred
        }

        return ordered.first
    }

    private func focusedGroupIndex(in groups: [AppRingGroup]) async -> Int? {
        guard let focusedWindowID = await focusedWindowProvider.focusedWindowID() else { return nil }
        return groups.firstIndex { group in
            group.windows.contains(where: { $0.windowId == focusedWindowID })
        }
    }

    private func appGroups(includeWindowless: Bool) async throws -> [AppRingGroup] {
        let snapshots = try await windowProvider.currentSnapshot()
        appFocusMemoryStore.prune(using: snapshots)

        let filtered = applyFilters(snapshots)
        let candidates = includeWindowless ? filtered : filtered.filter { !$0.isWindowlessApp }
        guard !candidates.isEmpty else { return [] }

        let seeds = buildAppRingSeeds(from: candidates)
        var groups = appRingStateStore.orderedGroups(
            from: seeds,
            ordering: config.ordering,
            showEmptyApps: config.visibility.showEmptyApps
        )

        if !includeWindowless {
            groups = groups.filter { !$0.windows.allSatisfy(\.isWindowlessApp) }
        }
        return groups
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
