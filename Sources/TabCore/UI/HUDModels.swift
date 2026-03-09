import Foundation

public enum CaptureMode: String, Sendable {
    case still
    case live
}

public enum ThumbnailState: String, Equatable, Sendable {
    case placeholder
    case stale
    case freshStill = "fresh-still"
    case liveSurface = "live-surface"
    case unavailable
}

struct HUDItem: Equatable, Identifiable, Sendable {
    let id: String
    let label: String
    let title: String
    let pid: pid_t
    let snapshot: WindowSnapshot
    let isSelected: Bool
    let isWindowlessApp: Bool
    let windowIndexInApp: Int?
    let thumbnailState: ThumbnailState

    init(
        id: String,
        label: String,
        title: String,
        pid: pid_t,
        snapshot: WindowSnapshot,
        isSelected: Bool,
        isWindowlessApp: Bool = false,
        windowIndexInApp: Int? = nil,
        thumbnailState: ThumbnailState
    ) {
        self.id = id
        self.label = label
        self.title = title
        self.pid = pid
        self.snapshot = snapshot
        self.isSelected = isSelected
        self.isWindowlessApp = isWindowlessApp
        self.windowIndexInApp = windowIndexInApp
        self.thumbnailState = thumbnailState
    }
}

struct HUDModel: Equatable, Sendable {
    let items: [HUDItem]
    let selectedIndex: Int?
}

@MainActor
protocol HUDControlling: AnyObject {
    func show(model: HUDModel, appearance: AppearanceConfig)
    func hide()
}
