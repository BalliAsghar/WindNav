import Foundation

struct CycleSession {
    let ordered: [WindowSnapshot]
    var selectedIndex: Int
    let startedAt: DispatchTime
}
