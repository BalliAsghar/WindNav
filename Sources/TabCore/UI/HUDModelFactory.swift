import Foundation

enum HUDModelFactory {
    static func makeModel(
        windows: [WindowSnapshot],
        selectedIndex: Int,
        appearance: AppearanceConfig
    ) -> HUDModel {
        let windowTotalsByPID = Dictionary(grouping: windows, by: \.pid).mapValues(\.count)
        var nextWindowIndexByPID: [pid_t: Int] = [:]

        let items = windows.enumerated().map { index, window in
            let totalForPID = windowTotalsByPID[window.pid] ?? 1
            let windowIndex = (nextWindowIndexByPID[window.pid] ?? 0) + 1
            nextWindowIndexByPID[window.pid] = windowIndex

            return HUDItem(
                id: "\(window.windowId)",
                label: WindowSnapshotSupport.appLabel(for: [window]),
                pid: window.pid,
                isSelected: index == selectedIndex,
                isWindowlessApp: window.isWindowlessApp,
                windowIndexInApp: appearance.showWindowCount && totalForPID > 1 ? windowIndex : nil
            )
        }

        return HUDModel(items: items, selectedIndex: selectedIndex)
    }
}
