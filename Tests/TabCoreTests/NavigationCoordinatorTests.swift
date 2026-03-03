@testable import TabCore
import Foundation
import XCTest

@MainActor
final class NavigationCoordinatorTests: XCTestCase {
    func testCycleStableOrderNoBounce() async {
        let focused = FakeFocusedWindowProvider(focusedWindowID: 10)
        let harness = makeHarness(
            snapshots: [
                snapshot(windowId: 10, pid: 1001, appName: "Alpha", title: "A"),
                snapshot(windowId: 20, pid: 1002, appName: "Beta", title: "B"),
                snapshot(windowId: 30, pid: 1003, appName: "Gamma", title: "C"),
                snapshot(windowId: 40, pid: 1004, appName: "Zeta", title: "D"),
            ],
            focusedProvider: focused
        )

        await harness.coordinator.startOrAdvanceCycle(direction: .right, hotkeyTimestamp: .now())
        XCTAssertEqual(harness.hud.lastModel?.selectedIndex, 1)

        await harness.coordinator.startOrAdvanceCycle(direction: .right, hotkeyTimestamp: .now())
        XCTAssertEqual(harness.hud.lastModel?.selectedIndex, 2)

        await harness.coordinator.startOrAdvanceCycle(direction: .right, hotkeyTimestamp: .now())
        XCTAssertEqual(harness.hud.lastModel?.selectedIndex, 3)

        XCTAssertTrue(harness.focus.calls.isEmpty)
    }

    func testNoFocusBeforeRelease() async {
        let harness = makeHarness(
            snapshots: [
                snapshot(windowId: 10, pid: 1001, appName: "Alpha", title: "A"),
                snapshot(windowId: 20, pid: 1002, appName: "Beta", title: "B"),
            ],
            focusedProvider: FakeFocusedWindowProvider(focusedWindowID: 10)
        )

        await harness.coordinator.startOrAdvanceCycle(direction: .right, hotkeyTimestamp: .now())
        await harness.coordinator.startOrAdvanceCycle(direction: .right, hotkeyTimestamp: .now())

        XCTAssertEqual(harness.focus.calls.count, 0)
    }

    func testSingleCommitOnRelease() async {
        let harness = makeHarness(
            snapshots: [
                snapshot(windowId: 10, pid: 1001, appName: "Alpha", title: "A"),
                snapshot(windowId: 20, pid: 1002, appName: "Beta", title: "B"),
            ],
            focusedProvider: FakeFocusedWindowProvider(focusedWindowID: 10)
        )

        await harness.coordinator.startOrAdvanceCycle(direction: .right, hotkeyTimestamp: .now())
        XCTAssertEqual(harness.hud.lastModel?.selectedIndex, 1)

        await harness.coordinator.commitCycleOnModifierRelease(commitTimestamp: .now())

        XCTAssertEqual(harness.focus.calls.count, 1)
        XCTAssertEqual(harness.focus.calls[0].windowId, 20)
        XCTAssertEqual(harness.hud.hideCalls, 1)
    }

    func testReverseCycleWrap() async {
        let harness = makeHarness(
            snapshots: [
                snapshot(windowId: 10, pid: 1001, appName: "Alpha", title: "A"),
                snapshot(windowId: 20, pid: 1002, appName: "Beta", title: "B"),
                snapshot(windowId: 30, pid: 1003, appName: "Gamma", title: "C"),
            ],
            focusedProvider: FakeFocusedWindowProvider(focusedWindowID: nil)
        )

        await harness.coordinator.startOrAdvanceCycle(direction: .left, hotkeyTimestamp: .now())
        XCTAssertEqual(harness.hud.lastModel?.selectedIndex, 2)

        await harness.coordinator.startOrAdvanceCycle(direction: .left, hotkeyTimestamp: .now())
        XCTAssertEqual(harness.hud.lastModel?.selectedIndex, 1)
    }

    func testCommitWhenTargetDisappearsFallsBackToSamePid() async {
        let provider = FakeWindowProvider(snapshots: [
            snapshot(windowId: 10, pid: 1001, appName: "Alpha", title: "A"),
            snapshot(windowId: 20, pid: 1002, appName: "Beta", title: "B-1"),
            snapshot(windowId: 21, pid: 1002, appName: "Beta", title: "B-2"),
        ])
        let focus = FakeFocusPerformer()
        let focused = FakeFocusedWindowProvider(focusedWindowID: 10)
        let hud = FakeHUDController()
        let coordinator = NavigationCoordinator(
            windowProvider: provider,
            focusedWindowProvider: focused,
            focusPerformer: focus,
            hudController: hud,
            config: .default
        )

        await coordinator.startOrAdvanceCycle(direction: .right, hotkeyTimestamp: .now())
        XCTAssertEqual(hud.lastModel?.selectedIndex, 1)

        provider.snapshots = [
            snapshot(windowId: 10, pid: 1001, appName: "Alpha", title: "A"),
            snapshot(windowId: 21, pid: 1002, appName: "Beta", title: "B-2"),
        ]

        await coordinator.commitCycleOnModifierRelease(commitTimestamp: .now())

        XCTAssertEqual(focus.calls.count, 1)
        XCTAssertEqual(focus.calls[0].windowId, 21)
        XCTAssertEqual(hud.hideCalls, 1)
    }

    func testQuitSelectedAppTerminatesFirstRequest() async {
        let harness = makeHarness(
            snapshots: [
                snapshot(windowId: 10, pid: 1001, appName: "Alpha", title: "A"),
                snapshot(windowId: 20, pid: 1002, appName: "Beta", title: "B"),
            ],
            focusedProvider: FakeFocusedWindowProvider(focusedWindowID: 10)
        )

        await harness.coordinator.startOrAdvanceCycle(direction: .right, hotkeyTimestamp: .now())
        await harness.coordinator.requestQuitSelectedAppInCycle()

        XCTAssertEqual(harness.terminator.terminateCalls, [1002])
        XCTAssertTrue(harness.terminator.forceTerminateCalls.isEmpty)
    }

    func testQuitSelectedAppSecondRequestForceTerminates() async {
        let harness = makeHarness(
            snapshots: [
                snapshot(windowId: 10, pid: 1001, appName: "Alpha", title: "A"),
                snapshot(windowId: 20, pid: 1002, appName: "Beta", title: "B"),
            ],
            focusedProvider: FakeFocusedWindowProvider(focusedWindowID: 10)
        )

        await harness.coordinator.startOrAdvanceCycle(direction: .right, hotkeyTimestamp: .now())
        await harness.coordinator.requestQuitSelectedAppInCycle()
        await harness.coordinator.requestQuitSelectedAppInCycle()

        XCTAssertEqual(harness.terminator.terminateCalls, [1002])
        XCTAssertEqual(harness.terminator.forceTerminateCalls, [1002])
    }

    func testQuitSelectedAppNeverQuitsFinder() async {
        let finder = WindowSnapshot(
            windowId: 40,
            pid: 2001,
            bundleId: "com.apple.finder",
            appName: nil,
            frame: CGRect(x: 20, y: 20, width: 120, height: 90),
            isMinimized: false,
            appIsHidden: false,
            isFullscreen: false,
            title: "Finder"
        )
        let harness = makeHarness(
            snapshots: [snapshot(windowId: 10, pid: 1001, appName: "Alpha", title: "A"), finder],
            focusedProvider: FakeFocusedWindowProvider(focusedWindowID: 10)
        )

        await harness.coordinator.startOrAdvanceCycle(direction: .right, hotkeyTimestamp: .now())
        await harness.coordinator.requestQuitSelectedAppInCycle()

        XCTAssertTrue(harness.terminator.terminateCalls.isEmpty)
        XCTAssertTrue(harness.terminator.forceTerminateCalls.isEmpty)
        XCTAssertEqual(harness.hud.lastModel?.selectedIndex, 1)
    }

    func testQuitSelectedAppRemovesTerminatedTargetAndAdvancesSelection() async {
        let harness = makeHarness(
            snapshots: [
                snapshot(windowId: 10, pid: 1001, appName: "Alpha", title: "A"),
                snapshot(windowId: 20, pid: 1002, appName: "Beta", title: "B"),
                snapshot(windowId: 30, pid: 1003, appName: "Gamma", title: "C"),
            ],
            focusedProvider: FakeFocusedWindowProvider(focusedWindowID: 10)
        )

        await harness.coordinator.startOrAdvanceCycle(direction: .right, hotkeyTimestamp: .now())
        harness.provider.snapshots = [
            snapshot(windowId: 10, pid: 1001, appName: "Alpha", title: "A"),
            snapshot(windowId: 30, pid: 1003, appName: "Gamma", title: "C"),
        ]

        await harness.coordinator.requestQuitSelectedAppInCycle()

        XCTAssertEqual(harness.hud.lastModel?.items.map(\.id), ["10", "30"])
        XCTAssertEqual(harness.hud.lastModel?.selectedIndex, 1)
    }

    func testQuitSelectedAppWhenLastCandidateCancelsSession() async {
        let harness = makeHarness(
            snapshots: [snapshot(windowId: 10, pid: 1001, appName: "Alpha", title: "A")],
            focusedProvider: FakeFocusedWindowProvider(focusedWindowID: nil)
        )

        await harness.coordinator.startOrAdvanceCycle(direction: .right, hotkeyTimestamp: .now())
        harness.provider.snapshots = []

        await harness.coordinator.requestQuitSelectedAppInCycle()

        XCTAssertFalse(harness.coordinator.hasActiveCycleSession())
        XCTAssertEqual(harness.hud.hideCalls, 1)
    }

    func testReleaseAfterQuitCommitsCurrentRemainingSelectionOnce() async {
        let harness = makeHarness(
            snapshots: [
                snapshot(windowId: 10, pid: 1001, appName: "Alpha", title: "A"),
                snapshot(windowId: 20, pid: 1002, appName: "Beta", title: "B"),
                snapshot(windowId: 30, pid: 1003, appName: "Gamma", title: "C"),
            ],
            focusedProvider: FakeFocusedWindowProvider(focusedWindowID: 10)
        )

        await harness.coordinator.startOrAdvanceCycle(direction: .right, hotkeyTimestamp: .now())
        harness.provider.snapshots = [
            snapshot(windowId: 10, pid: 1001, appName: "Alpha", title: "A"),
            snapshot(windowId: 30, pid: 1003, appName: "Gamma", title: "C"),
        ]

        await harness.coordinator.requestQuitSelectedAppInCycle()
        await harness.coordinator.commitCycleOnModifierRelease(commitTimestamp: .now())

        XCTAssertEqual(harness.focus.calls.count, 1)
        XCTAssertEqual(harness.focus.calls[0].windowId, 30)
    }

    func testReleaseWithoutSessionNoop() async {
        let harness = makeHarness(
            snapshots: [snapshot(windowId: 10, pid: 1001, appName: "Alpha", title: "A")],
            focusedProvider: FakeFocusedWindowProvider(focusedWindowID: nil)
        )

        await harness.coordinator.commitCycleOnModifierRelease(commitTimestamp: .now())

        XCTAssertTrue(harness.focus.calls.isEmpty)
        XCTAssertEqual(harness.hud.hideCalls, 0)
    }

    func testCancelCycleSessionHidesHudAndDoesNotFocus() async {
        let harness = makeHarness(
            snapshots: [
                snapshot(windowId: 10, pid: 1001, appName: "Alpha", title: "A"),
                snapshot(windowId: 20, pid: 1002, appName: "Beta", title: "B"),
            ],
            focusedProvider: FakeFocusedWindowProvider(focusedWindowID: 10)
        )

        await harness.coordinator.startOrAdvanceCycle(direction: .right, hotkeyTimestamp: .now())
        harness.coordinator.cancelCycleSession()

        XCTAssertEqual(harness.hud.hideCalls, 1)
        XCTAssertEqual(harness.focus.calls.count, 0)
    }

    private func makeHarness(
        snapshots: [WindowSnapshot],
        focusedProvider: FakeFocusedWindowProvider
    ) -> Harness {
        let provider = FakeWindowProvider(snapshots: snapshots)
        let focus = FakeFocusPerformer()
        let hud = FakeHUDController()
        let terminator = FakeAppTerminationPerformer()
        let coordinator = NavigationCoordinator(
            windowProvider: provider,
            focusedWindowProvider: focusedProvider,
            focusPerformer: focus,
            appTerminationPerformer: terminator,
            hudController: hud,
            config: .default
        )
        return Harness(coordinator: coordinator, provider: provider, focused: focusedProvider, focus: focus, hud: hud, terminator: terminator)
    }

    private func snapshot(windowId: UInt32, pid: pid_t, appName: String, title: String) -> WindowSnapshot {
        WindowSnapshot(
            windowId: windowId,
            pid: pid,
            bundleId: "bundle.\(appName.lowercased())",
            appName: appName,
            frame: CGRect(x: 10, y: 10, width: 120, height: 90),
            isMinimized: false,
            appIsHidden: false,
            isFullscreen: false,
            title: title
        )
    }
}

private struct Harness {
    let coordinator: NavigationCoordinator
    let provider: FakeWindowProvider
    let focused: FakeFocusedWindowProvider
    let focus: FakeFocusPerformer
    let hud: FakeHUDController
    let terminator: FakeAppTerminationPerformer
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
        focusedWindowIDValue = focusedWindowID
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

    func show(model: HUDModel, appearance: AppearanceConfig) {
        lastModel = model
    }

    func hide() {
        hideCalls += 1
    }
}

@MainActor
private final class FakeAppTerminationPerformer: AppTerminationPerformer {
    var terminateCalls: [pid_t] = []
    var forceTerminateCalls: [pid_t] = []
    var bundleIDByPID: [pid_t: String] = [:]

    func terminate(pid: pid_t) {
        terminateCalls.append(pid)
    }

    func forceTerminate(pid: pid_t) {
        forceTerminateCalls.append(pid)
    }

    func bundleIdentifier(pid: pid_t) -> String? {
        bundleIDByPID[pid]
    }
}
