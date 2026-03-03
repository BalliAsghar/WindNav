import Foundation

struct HUDItem: Equatable, Identifiable {
    let id: String
    let label: String
    let pid: pid_t
    let isSelected: Bool
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
