import Foundation

struct AppRingKey: Sendable, Hashable, Equatable, CustomStringConvertible {
    let rawValue: String
    let bundleId: String?
    let representativePID: pid_t

    init(bundleId: String?, pid: pid_t) {
        self.bundleId = bundleId
        representativePID = pid
        if let bundleId, !bundleId.isEmpty {
            rawValue = "bundle:\(bundleId)"
        } else {
            rawValue = "pid:\(pid)"
        }
    }

    init(window: WindowSnapshot) {
        self.init(bundleId: window.bundleId, pid: window.pid)
    }

    var description: String { rawValue }

    func hash(into hasher: inout Hasher) {
        hasher.combine(rawValue)
    }

    static func == (lhs: AppRingKey, rhs: AppRingKey) -> Bool {
        lhs.rawValue == rhs.rawValue
    }
}

struct AppRingGroupSeed: Sendable {
    let key: AppRingKey
    let label: String
    let windows: [WindowSnapshot]
}

struct AppRingGroup: Sendable {
    let key: AppRingKey
    let label: String
    let windows: [WindowSnapshot]
    let isPinned: Bool
}
