import Foundation

enum HUDModelFactory {
    static func makeModel(
        windows: [WindowSnapshot],
        selectedIndex: Int,
        appearance: AppearanceConfig,
        hud: HUDConfig
    ) -> HUDModel {
        let windowTotalsByPID = Dictionary(grouping: windows, by: \.pid).mapValues(\.count)
        var nextWindowIndexByPID: [pid_t: Int] = [:]

        let items = windows.enumerated().map { index, window in
            let totalForPID = windowTotalsByPID[window.pid] ?? 1
            let windowIndex = (nextWindowIndexByPID[window.pid] ?? 0) + 1
            nextWindowIndexByPID[window.pid] = windowIndex
            let metadata = HUDMetadataFormatter.lines(for: window)

            return HUDItem(
                id: "\(window.windowId)",
                label: metadata.secondary,
                title: metadata.primary,
                pid: window.pid,
                snapshot: window,
                isSelected: index == selectedIndex,
                isWindowlessApp: window.isWindowlessApp,
                windowIndexInApp: appearance.showWindowCount && totalForPID > 1 ? windowIndex : nil,
                thumbnailState: hud.thumbnails && window.canCaptureThumbnail ? .placeholder : .unavailable
            )
        }

        return HUDModel(items: items, selectedIndex: selectedIndex)
    }
}
