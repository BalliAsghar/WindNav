import Foundation

struct HUDItem: Equatable, Identifiable {
    let id: String
    let label: String
    let pid: pid_t
    let isSelected: Bool
    let windowIndexInApp: Int?

    init(id: String, label: String, pid: pid_t, isSelected: Bool, windowIndexInApp: Int? = nil) {
        self.id = id
        self.label = label
        self.pid = pid
        self.isSelected = isSelected
        self.windowIndexInApp = windowIndexInApp
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
