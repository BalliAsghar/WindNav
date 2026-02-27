import CoreGraphics
@testable import WindNavCore
import XCTest

@MainActor
final class FixedAppRingTests: XCTestCase {
    func testPinnedAppsPreserveOrderAndSkipMissing() {
        let store = AppRingStateStore()
        let seeds = [
            seed(bundleId: "com.apple.Terminal", label: "Terminal", windowID: 2, pid: 200),
            seed(bundleId: "com.microsoft.VSCode", label: "Editor", windowID: 3, pid: 300),
        ]
        var config = FixedAppRingConfig.default
        config.pinnedApps = ["com.google.Chrome", "com.microsoft.VSCode", "com.apple.Terminal"]
        config.unpinnedApps = .ignore

        let result = store.orderedGroups(from: seeds, monitorID: 1, config: config)

        XCTAssertEqual(result.map(\.label), ["Editor", "Terminal"])
        XCTAssertEqual(result.map(\.isPinned), [true, true])
    }

    func testAppendUnpinnedKeepsFirstSeenOrderStableAcrossCalls() {
        let store = AppRingStateStore()
        var config = FixedAppRingConfig.default
        config.unpinnedApps = .append

        let first = [
            seed(bundleId: "a", label: "Alpha", windowID: 1, pid: 100),
            seed(bundleId: "b", label: "Beta", windowID: 2, pid: 200),
        ]
        _ = store.orderedGroups(from: first, monitorID: 1, config: config)

        let second = [
            seed(bundleId: "b", label: "Beta", windowID: 2, pid: 200),
            seed(bundleId: "a", label: "Alpha", windowID: 1, pid: 100),
            seed(bundleId: "c", label: "Gamma", windowID: 3, pid: 300),
        ]
        let result = store.orderedGroups(from: second, monitorID: 1, config: config)

        XCTAssertEqual(result.map(\.label), ["Alpha", "Beta", "Gamma"])
    }

    func testIgnoreUnpinnedExcludesAllUnpinnedApps() {
        let store = AppRingStateStore()
        var config = FixedAppRingConfig.default
        config.unpinnedApps = .ignore

        let seeds = [
            seed(bundleId: "a", label: "Alpha", windowID: 1, pid: 100),
            seed(bundleId: "b", label: "Beta", windowID: 2, pid: 200),
        ]
        let result = store.orderedGroups(from: seeds, monitorID: 1, config: config)

        XCTAssertTrue(result.isEmpty)
    }

    func testAppRingKeyUsesBundleIdForGroupingAndPidFallback() {
        let chrome1 = snapshot(windowId: 1, pid: 100, bundleId: "com.google.Chrome")
        let chrome2 = snapshot(windowId: 2, pid: 101, bundleId: "com.google.Chrome")
        let noBundle1 = snapshot(windowId: 3, pid: 200, bundleId: nil)
        let noBundle2 = snapshot(windowId: 4, pid: 201, bundleId: nil)

        XCTAssertEqual(AppRingKey(window: chrome1), AppRingKey(window: chrome2))
        XCTAssertNotEqual(AppRingKey(window: noBundle1), AppRingKey(window: noBundle2))
    }

    func testAppFocusMemorySelectsLastFocusedAndFallsBackAfterPrune() {
        let memory = AppFocusMemoryStore()
        let monitor: NSNumber = 1
        let w1 = snapshot(windowId: 10, pid: 100, bundleId: "com.apple.Terminal")
        let w2 = snapshot(windowId: 11, pid: 100, bundleId: "com.apple.Terminal")
        let key = AppRingKey(window: w1)

        memory.recordFocused(window: w2, monitorID: monitor)
        XCTAssertEqual(
            memory.preferredWindowID(appKey: key, candidateWindows: [w1, w2], monitorID: monitor, policy: .lastFocused),
            11
        )

        memory.prune(using: [w1])
        XCTAssertNil(memory.preferredWindowID(appKey: key, candidateWindows: [w1], monitorID: monitor, policy: .lastFocused))
    }

    func testAppFocusMemoryLastFocusedOnMonitorFallsBackToGlobal() {
        let memory = AppFocusMemoryStore()
        let w1 = snapshot(windowId: 20, pid: 100, bundleId: "com.apple.Terminal")
        let w2 = snapshot(windowId: 21, pid: 100, bundleId: "com.apple.Terminal")
        let key = AppRingKey(window: w1)

        memory.recordFocused(window: w2, monitorID: 2)

        XCTAssertEqual(
            memory.preferredWindowID(appKey: key, candidateWindows: [w1, w2], monitorID: 1, policy: .lastFocusedOnMonitor),
            21
        )
    }

    private func seed(bundleId: String?, label: String, windowID: UInt32, pid: pid_t) -> AppRingGroupSeed {
        AppRingGroupSeed(key: AppRingKey(bundleId: bundleId, pid: pid), label: label, windows: [snapshot(windowId: windowID, pid: pid, bundleId: bundleId)])
    }

    private func snapshot(windowId: UInt32, pid: pid_t, bundleId: String?) -> WindowSnapshot {
        WindowSnapshot(
            windowId: windowId,
            pid: pid,
            bundleId: bundleId,
            frame: CGRect(x: 0, y: 0, width: 100, height: 100),
            isMinimized: false,
            appIsHidden: false,
            title: nil
        )
    }
}
