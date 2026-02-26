import Foundation

struct AppRingKey: Sendable, Hashable, Equatable, CustomStringConvertible {
    let rawValue: String
    let bundleId: String?
    let representativePID: pid_t

    init(bundleId: String?, pid: pid_t) {
        self.bundleId = bundleId
        representativePID = pid
        if let bundleId, !bundleId.isEmpty {
            rawValue = "bundle:\(bundleId)"
        } else {
            rawValue = "pid:\(pid)"
        }
    }

    init(window: WindowSnapshot) {
        self.init(bundleId: window.bundleId, pid: window.pid)
    }

    var description: String { rawValue }

    func hash(into hasher: inout Hasher) {
        hasher.combine(rawValue)
    }

    static func == (lhs: AppRingKey, rhs: AppRingKey) -> Bool {
        lhs.rawValue == rhs.rawValue
    }
}

struct AppRingGroupSeed: Sendable {
    let key: AppRingKey
    let label: String
    let windows: [WindowSnapshot]
}

struct AppRingGroup: Sendable {
    let key: AppRingKey
    let label: String
    let windows: [WindowSnapshot]
    let isPinned: Bool
}

@MainActor
final class AppRingStateStore {
    private var unpinnedFirstSeenOrderByMonitor: [NSNumber: [AppRingKey]] = [:]

    func orderedGroups(
        from seeds: [AppRingGroupSeed],
        monitorID: NSNumber,
        config: FixedAppRingConfig
    ) -> [AppRingGroup] {
        guard !seeds.isEmpty else { return [] }

        let seedByKey = Dictionary(uniqueKeysWithValues: seeds.map { ($0.key, $0) })
        let pinnedBundleIDs = config.pinnedApps
        var pinnedGroups: [AppRingGroup] = []
        var usedKeys: Set<AppRingKey> = []

        for bundleID in pinnedBundleIDs {
            if let seed = seeds.first(where: { $0.key.bundleId == bundleID && !usedKeys.contains($0.key) }) {
                pinnedGroups.append(AppRingGroup(key: seed.key, label: seed.label, windows: seed.windows, isPinned: true))
                usedKeys.insert(seed.key)
            }
        }

        let unpinnedSeeds = seeds.filter { !usedKeys.contains($0.key) }
        let unpinnedPresentKeys = Set(unpinnedSeeds.map(\.key))
        let unpinnedGroups = orderedUnpinnedGroups(
            from: unpinnedSeeds,
            seedByKey: seedByKey,
            presentKeys: unpinnedPresentKeys,
            monitorID: monitorID,
            policy: config.unpinnedApps
        )

        return pinnedGroups + unpinnedGroups
    }

    private func orderedUnpinnedGroups(
        from seeds: [AppRingGroupSeed],
        seedByKey: [AppRingKey: AppRingGroupSeed],
        presentKeys: Set<AppRingKey>,
        monitorID: NSNumber,
        policy: UnpinnedAppsPolicy
    ) -> [AppRingGroup] {
        switch policy {
            case .ignore:
                unpinnedFirstSeenOrderByMonitor[monitorID] = []
                return []

            case .alphabeticalTail:
                return seeds
                    .sorted(by: alphabeticalSeedSort)
                    .map { AppRingGroup(key: $0.key, label: $0.label, windows: $0.windows, isPinned: false) }

            case .append:
                var order = unpinnedFirstSeenOrderByMonitor[monitorID] ?? []
                order = order.filter { presentKeys.contains($0) }

                let existing = Set(order)
                let unseen = seeds
                    .map(\AppRingGroupSeed.key)
                    .filter { !existing.contains($0) }
                    .sorted { lhs, rhs in
                        let lhsSeed = seedByKey[lhs]
                        let rhsSeed = seedByKey[rhs]
                        return alphabeticalSeedSort(lhsSeed!, rhsSeed!)
                    }
                order.append(contentsOf: unseen)
                unpinnedFirstSeenOrderByMonitor[monitorID] = order

                return order.compactMap { key in
                    guard let seed = seedByKey[key] else { return nil }
                    return AppRingGroup(key: seed.key, label: seed.label, windows: seed.windows, isPinned: false)
                }
        }
    }

    private func alphabeticalSeedSort(_ lhs: AppRingGroupSeed, _ rhs: AppRingGroupSeed) -> Bool {
        let lhsLabel = lhs.label.localizedCaseInsensitiveCompare(rhs.label)
        if lhsLabel != .orderedSame {
            return lhsLabel == .orderedAscending
        }
        return lhs.key.rawValue < rhs.key.rawValue
    }
}
