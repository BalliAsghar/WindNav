import Foundation

enum WindowSnapshotSupport {
    static func wrappedIndex(_ index: Int, count: Int) -> Int {
        guard count > 0 else { return 0 }
        let next = index % count
        return next < 0 ? next + count : next
    }

    static func snapshotSortOrder(lhs: WindowSnapshot, rhs: WindowSnapshot) -> Bool {
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

    static func applyFilters(
        _ snapshots: [WindowSnapshot],
        visibility: VisibilityConfig,
        filters: FiltersConfig
    ) -> [WindowSnapshot] {
        let excludedNames = Set(filters.excludeApps.map { $0.lowercased() })
        let excludedBundleIds = Set(filters.excludeBundleIds.map { $0.lowercased() })

        return snapshots.filter { snapshot in
            if !visibility.showMinimized && snapshot.isMinimized { return false }
            if !visibility.showHidden && snapshot.appIsHidden { return false }
            if !visibility.showFullscreen && snapshot.isFullscreen { return false }
            if snapshot.isWindowlessApp && snapshot.bundleId == "com.apple.finder" { return false }
            if visibility.showEmptyApps == .hide && snapshot.isWindowlessApp { return false }
            if let appName = snapshot.appName, excludedNames.contains(appName.lowercased()) { return false }
            if let bundleId = snapshot.bundleId, excludedBundleIds.contains(bundleId.lowercased()) { return false }
            return true
        }
    }

    static func applyWindowlessOrdering(
        _ snapshots: [WindowSnapshot],
        showEmptyApps: VisibilityConfig.ShowEmptyAppsPolicy
    ) -> [WindowSnapshot] {
        guard showEmptyApps == .showAtEnd else {
            return snapshots
        }

        let windowed = snapshots.filter { !$0.isWindowlessApp }
        let windowless = snapshots.filter(\.isWindowlessApp)
        return windowed + windowless
    }

    static func appLabel(for windows: [WindowSnapshot]) -> String {
        if let name = windows.first(where: { $0.appName != nil })?.appName {
            return name
        }
        if let bundle = windows.first(where: { $0.bundleId != nil })?.bundleId {
            return bundle
        }
        return "App"
    }
}
