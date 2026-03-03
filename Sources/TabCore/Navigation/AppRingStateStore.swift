import Foundation

@MainActor
final class AppRingStateStore {
    private var unpinnedFirstSeenOrder: [AppRingKey] = []

    func orderedGroups(
        from seeds: [AppRingGroupSeed],
        ordering: OrderingConfig,
        showEmptyApps: VisibilityConfig.ShowEmptyAppsPolicy
    ) -> [AppRingGroup] {
        guard !seeds.isEmpty else { return [] }

        let seedByKey = Dictionary(uniqueKeysWithValues: seeds.map { ($0.key, $0) })
        var usedKeys = Set<AppRingKey>()
        var pinnedGroups: [AppRingGroup] = []

        for bundleID in ordering.pinnedApps {
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
            policy: ordering.unpinnedApps
        )

        let merged = pinnedGroups + unpinnedGroups
        if showEmptyApps == .showAtEnd {
            let windowed = merged.filter { group in
                !group.windows.allSatisfy(\.isWindowlessApp)
            }
            let windowless = merged.filter { group in
                group.windows.allSatisfy(\.isWindowlessApp)
            }
            return windowed + windowless
        }

        return merged
    }

    private func orderedUnpinnedGroups(
        from seeds: [AppRingGroupSeed],
        seedByKey: [AppRingKey: AppRingGroupSeed],
        presentKeys: Set<AppRingKey>,
        policy: UnpinnedAppsPolicy
    ) -> [AppRingGroup] {
        switch policy {
            case .ignore:
                unpinnedFirstSeenOrder = []
                return []

            case .append:
                var order = unpinnedFirstSeenOrder
                order = order.filter { presentKeys.contains($0) }

                let existing = Set(order)
                let unseen = seeds
                    .map(\.key)
                    .filter { !existing.contains($0) }
                    .sorted { lhs, rhs in
                        let lhsSeed = seedByKey[lhs]!
                        let rhsSeed = seedByKey[rhs]!
                        return alphabeticalSeedSort(lhsSeed, rhsSeed)
                    }
                order.append(contentsOf: unseen)
                unpinnedFirstSeenOrder = order

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
