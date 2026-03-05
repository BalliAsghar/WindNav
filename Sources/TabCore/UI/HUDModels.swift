import CoreGraphics
import Foundation

struct HUDItem: Equatable, Identifiable {
    let id: String
    let label: String
    let pid: pid_t
    let isSelected: Bool
    let isWindowlessApp: Bool
    let windowIndexInApp: Int?
    let thumbnail: CGImage?

    init(
        id: String,
        label: String,
        pid: pid_t,
        isSelected: Bool,
        isWindowlessApp: Bool = false,
        windowIndexInApp: Int? = nil,
        thumbnail: CGImage? = nil
    ) {
        self.id = id
        self.label = label
        self.pid = pid
        self.isSelected = isSelected
        self.isWindowlessApp = isWindowlessApp
        self.windowIndexInApp = windowIndexInApp
        self.thumbnail = thumbnail
    }
}

struct HUDModel: Equatable {
    let items: [HUDItem]
    let selectedIndex: Int?
}

@MainActor
protocol HUDControlling: AnyObject {
    func show(model: HUDModel, appearance: AppearanceConfig)
    func hide()
}
