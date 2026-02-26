import Foundation

@MainActor
final class MRUWindowOrderStore {
    private var order: [UInt32] = []

    func syncVisibleWindowIDs(_ windowIDs: [UInt32]) {
        let visibleSet = Set(windowIDs)
        order = order.filter { visibleSet.contains($0) }

        let existing = Set(order)
        let unseen = visibleSet.subtracting(existing).sorted()
        order.append(contentsOf: unseen)
    }

    func promote(_ windowID: UInt32) {
        order.removeAll { $0 == windowID }
        order.insert(windowID, at: 0)
    }

    func orderedIDs(within allowedIDs: Set<UInt32>) -> [UInt32] {
        order.filter { allowedIDs.contains($0) }
    }
}
