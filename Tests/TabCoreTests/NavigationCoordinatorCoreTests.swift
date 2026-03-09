@testable import TabCore
import Foundation
import XCTest

@MainActor
final class NavigationCoordinatorCoreTests: XCTestCase {
    func testCycleAdvanceThenCommitFocusesSelectedWindow() async {
        let harness = makeHarness(
            snapshots: [
                snapshot(windowId: 10, pid: 1001, appName: "Alpha"),
                snapshot(windowId: 20, pid: 1002, appName: "Beta"),
            ],
            focusedWindowID: 10
        )

        await harness.coordinator.startOrAdvanceCycle(direction: .right, hotkeyTimestamp: .now())
        await harness.coordinator.commitCycleOnModifierRelease(commitTimestamp: .now())

        XCTAssertEqual(harness.focus.calls.count, 1)
        XCTAssertEqual(harness.focus.calls.first?.windowId, 20)
        XCTAssertEqual(harness.hud.hideCalls, 1)
    }

    func testCancelCycleSessionHidesHudWithoutFocusingSelectedWindow() async {
        let harness = makeHarness(
            snapshots: [
                snapshot(windowId: 10, pid: 1001, appName: "Alpha"),
                snapshot(windowId: 20, pid: 1002, appName: "Beta"),
            ],
            focusedWindowID: 10
        )

        await harness.coordinator.startOrAdvanceCycle(direction: .right, hotkeyTimestamp: .now())
        harness.coordinator.cancelCycleSession()

        XCTAssertTrue(harness.focus.calls.isEmpty)
        XCTAssertEqual(harness.hud.hideCalls, 1)
        XCTAssertFalse(harness.coordinator.hasActiveCycleSession())
    }

    func testCloseSelectedWindowRefreshesSession() async {
        let harness = makeHarness(
            snapshots: [
                snapshot(windowId: 10, pid: 1001, appName: "Alpha"),
                snapshot(windowId: 20, pid: 1002, appName: "Beta"),
                snapshot(windowId: 30, pid: 1003, appName: "Gamma"),
            ],
            focusedWindowID: 10
        )

        await harness.coordinator.startOrAdvanceCycle(direction: .right, hotkeyTimestamp: .now())
        harness.provider.snapshots = [
            snapshot(windowId: 10, pid: 1001, appName: "Alpha"),
            snapshot(windowId: 30, pid: 1003, appName: "Gamma"),
        ]
        await harness.coordinator.requestCloseSelectedWindowInCycle()

        XCTAssertEqual(harness.closer.calls.count, 1)
        XCTAssertEqual(harness.closer.calls.first?.windowId, 20)
        XCTAssertEqual(harness.hud.lastModel?.items.count, 2)
        XCTAssertTrue(harness.coordinator.hasActiveCycleSession())
    }

    private func makeHarness(
        snapshots: [WindowSnapshot],
        focusedWindowID: UInt32?
    ) -> Harness {
        let provider = FakeWindowProvider(snapshots: snapshots)
        let focused = FakeFocusedWindowProvider(focusedWindowID: focusedWindowID)
        let focus = FakeFocusPerformer()
        let hud = FakeHUDController()
        let terminator = FakeAppTerminationPerformer()
        let closer = FakeWindowClosePerformer()
        let coordinator = NavigationCoordinator(
            windowProvider: provider,
            focusedWindowProvider: focused,
            focusPerformer: focus,
            appTerminationPerformer: terminator,
            windowClosePerformer: closer,
            hudController: hud,
            config: .default
        )
        return Harness(
            coordinator: coordinator,
            provider: provider,
            focus: focus,
            hud: hud,
            closer: closer
        )
    }

    private func snapshot(
        windowId: UInt32,
        pid: pid_t,
        appName: String,
        size: CGSize = CGSize(width: 100, height: 80)
    ) -> WindowSnapshot {
        WindowSnapshot(
            windowId: windowId,
            pid: pid,
            bundleId: "bundle.\(appName.lowercased())",
            appName: appName,
            frame: CGRect(x: 10, y: 10, width: size.width, height: size.height),
            isMinimized: false,
            appIsHidden: false,
            isFullscreen: false,
            title: appName
        )
    }
}

private struct Harness {
    let coordinator: NavigationCoordinator
    let provider: FakeWindowProvider
    let focus: FakeFocusPerformer
    let hud: FakeHUDController
    let closer: FakeWindowClosePerformer
}

@MainActor
private final class FakeWindowProvider: WindowProvider {
    var snapshots: [WindowSnapshot]

    init(snapshots: [WindowSnapshot]) {
        self.snapshots = snapshots
    }

    func currentSnapshot() async throws -> [WindowSnapshot] {
        snapshots
    }
}

@MainActor
private final class FakeFocusedWindowProvider: FocusedWindowProvider {
    var focusedWindowIDValue: UInt32?

    init(focusedWindowID: UInt32?) {
        self.focusedWindowIDValue = focusedWindowID
    }

    func focusedWindowID() async -> UInt32? {
        focusedWindowIDValue
    }
}

@MainActor
private final class FakeFocusPerformer: FocusPerformer {
    var calls: [(windowId: UInt32, pid: pid_t)] = []

    func focus(windowId: UInt32, pid: pid_t) async throws {
        calls.append((windowId: windowId, pid: pid))
    }
}

@MainActor
private final class FakeHUDController: HUDControlling {
    var lastModel: HUDModel?
    var hideCalls = 0

    func show(model: HUDModel, appearance: AppearanceConfig, hud: HUDConfig) {
        lastModel = model
    }

    func hide() {
        hideCalls += 1
    }
}

@MainActor
private final class FakeAppTerminationPerformer: AppTerminationPerformer {
    func terminate(pid: pid_t) {}
    func forceTerminate(pid: pid_t) {}
    func bundleIdentifier(pid: pid_t) -> String? { nil }
}

@MainActor
private final class FakeWindowClosePerformer: WindowClosePerformer {
    var calls: [(windowId: UInt32, pid: pid_t)] = []

    func close(windowId: UInt32, pid: pid_t) -> Bool {
        calls.append((windowId: windowId, pid: pid))
        return true
    }
}
