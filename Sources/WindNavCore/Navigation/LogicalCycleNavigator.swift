import Foundation

@MainActor
final class LogicalCycleNavigator {
    func target(
        from focused: WindowSnapshot,
        direction: Direction,
        orderedCandidates: [WindowSnapshot]
    ) -> WindowSnapshot? {
        guard orderedCandidates.count > 1 else {
            return nil
        }

        guard let currentIndex = orderedCandidates.firstIndex(where: { $0.windowId == focused.windowId }) else {
            return nil
        }

        let step = direction == .right ? 1 : -1
        let targetIndex = (currentIndex + step + orderedCandidates.count) % orderedCandidates.count
        return orderedCandidates[targetIndex]
    }
}

enum CycleSessionResetReason: String {
    case timeout
    case candidateSetChanged = "candidate-set-changed"
    case monitorChanged = "monitor-changed"
}

struct CycleSessionState: Equatable {
    let monitorID: NSNumber
    let candidateSet: Set<UInt32>
    let orderedWindowIDs: [UInt32]
    let lastEventAt: Date
}

struct CycleOrderResolution: Equatable {
    let state: CycleSessionState
    let orderedWindowIDs: [UInt32]
    let resetReason: CycleSessionResetReason?
    let reusedSession: Bool
}

enum CycleSessionResolver {
    static func resolve(
        existing: CycleSessionState?,
        monitorID: NSNumber,
        candidateSet: Set<UInt32>,
        now: Date,
        timeoutMs: Int,
        freshOrderedWindowIDs: [UInt32]
    ) -> CycleOrderResolution {
        guard let existing else {
            let state = CycleSessionState(
                monitorID: monitorID,
                candidateSet: candidateSet,
                orderedWindowIDs: freshOrderedWindowIDs,
                lastEventAt: now
            )
            return CycleOrderResolution(
                state: state,
                orderedWindowIDs: freshOrderedWindowIDs,
                resetReason: nil,
                reusedSession: false
            )
        }

        let elapsedMs = now.timeIntervalSince(existing.lastEventAt) * 1000
        let reason: CycleSessionResetReason?
        if existing.monitorID != monitorID {
            reason = .monitorChanged
        } else if existing.candidateSet != candidateSet {
            reason = .candidateSetChanged
        } else if timeoutMs > 0, elapsedMs > Double(timeoutMs) {
            reason = .timeout
        } else {
            reason = nil
        }

        if let reason {
            let state = CycleSessionState(
                monitorID: monitorID,
                candidateSet: candidateSet,
                orderedWindowIDs: freshOrderedWindowIDs,
                lastEventAt: now
            )
            return CycleOrderResolution(
                state: state,
                orderedWindowIDs: freshOrderedWindowIDs,
                resetReason: reason,
                reusedSession: false
            )
        }

        let reused = CycleSessionState(
            monitorID: existing.monitorID,
            candidateSet: existing.candidateSet,
            orderedWindowIDs: existing.orderedWindowIDs,
            lastEventAt: now
        )
        return CycleOrderResolution(
            state: reused,
            orderedWindowIDs: existing.orderedWindowIDs,
            resetReason: nil,
            reusedSession: true
        )
    }
}
