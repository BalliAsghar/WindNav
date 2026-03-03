@testable import TabCore
import Foundation
import XCTest

@MainActor
final class DirectionalCoordinatorTests: XCTestCase {
    func testLeftRightImmediateUsesStableRingNoBounce() async {
        let harness = makeHarness(
            snapshots: [
                snapshot(windowId: 10, pid: 1001, appName: "Alpha", title: "A"),
                snapshot(windowId: 20, pid: 1002, appName: "Beta", title: "B"),
                snapshot(windowId: 30, pid: 1003, appName: "Gamma", title: "C"),
            ],
            focusedWindowID: 10
        )

        await harness.coordinator.handleHotkey(direction: .right, hotkeyTimestamp: .now())
        await harness.coordinator.handleHotkey(direction: .right, hotkeyTimestamp: .now())
        await harness.coordinator.handleHotkey(direction: .right, hotkeyTimestamp: .now())

        XCTAssertEqual(harness.focus.calls.map(\.windowId), [20, 30, 10])
    }

    func testLeftRightWrapsAcrossAppRing() async {
        let harness = makeHarness(
            snapshots: [
                snapshot(windowId: 10, pid: 1001, appName: "Alpha", title: "A"),
                snapshot(windowId: 20, pid: 1002, appName: "Beta", title: "B"),
            ],
            focusedWindowID: 10
        )

        await harness.coordinator.handleHotkey(direction: .left, hotkeyTimestamp: .now())

        XCTAssertEqual(harness.focus.calls.last?.windowId, 20)
    }

    func testUpDownStartsBrowseHUDWithoutFocus() async {
        let harness = makeHarness(
            snapshots: [
                snapshot(windowId: 10, pid: 1001, appName: "Alpha", title: "A"),
                snapshot(windowId: 20, pid: 1002, appName: "Beta", title: "B"),
            ],
            focusedWindowID: 10
        )

        await harness.coordinator.handleHotkey(direction: .up, hotkeyTimestamp: .now())

        XCTAssertTrue(harness.coordinator.hasActiveSession())
        XCTAssertEqual(harness.coordinator.currentFlowKind(), .browse)
        XCTAssertTrue(harness.focus.calls.isEmpty)
        XCTAssertNotNil(harness.hud.lastModel)
    }

    func testBrowseSelectionCommitOnReleaseTrueCommitsOnce() async {
        var config = TabConfig.default
        config.directional.commitOnModifierRelease = true
        config.directional.browseLeftRightMode = .selection
        let harness = makeHarness(
            snapshots: [
                snapshot(windowId: 10, pid: 1001, appName: "Alpha", title: "A"),
                snapshot(windowId: 20, pid: 1002, appName: "Beta", title: "B"),
            ],
            focusedWindowID: 10,
            config: config
        )

        await harness.coordinator.handleHotkey(direction: .up, hotkeyTimestamp: .now())
        XCTAssertTrue(harness.focus.calls.isEmpty)

        await harness.coordinator.commitOrEndSessionOnModifierRelease(commitTimestamp: .now())

        XCTAssertEqual(harness.focus.calls.count, 1)
        XCTAssertEqual(harness.hud.hideCalls, 1)
    }

    func testBrowseSelectionCommitOnReleaseFalseCommitsImmediately() async {
        var config = TabConfig.default
        config.directional.commitOnModifierRelease = false
        config.directional.browseLeftRightMode = .selection
        let harness = makeHarness(
            snapshots: [
                snapshot(windowId: 10, pid: 1001, appName: "Alpha", title: "A"),
                snapshot(windowId: 20, pid: 1002, appName: "Beta", title: "B"),
            ],
            focusedWindowID: 10,
            config: config
        )

        await harness.coordinator.handleHotkey(direction: .up, hotkeyTimestamp: .now())
        XCTAssertEqual(harness.focus.calls.count, 1)

        await harness.coordinator.commitOrEndSessionOnModifierRelease(commitTimestamp: .now())

        XCTAssertEqual(harness.focus.calls.count, 1)
        XCTAssertEqual(harness.hud.hideCalls, 1)
    }

    func testBrowseLeftRightModeImmediateFocuses() async {
        var config = TabConfig.default
        config.directional.commitOnModifierRelease = true
        config.directional.browseLeftRightMode = .immediate
        let harness = makeHarness(
            snapshots: [
                snapshot(windowId: 10, pid: 1001, appName: "Alpha", title: "A"),
                snapshot(windowId: 20, pid: 1002, appName: "Beta", title: "B"),
                snapshot(windowId: 30, pid: 1003, appName: "Gamma", title: "C"),
            ],
            focusedWindowID: 10,
            config: config
        )

        await harness.coordinator.handleHotkey(direction: .up, hotkeyTimestamp: .now())
        XCTAssertTrue(harness.focus.calls.isEmpty)

        await harness.coordinator.handleHotkey(direction: .right, hotkeyTimestamp: .now())
        XCTAssertEqual(harness.focus.calls.count, 1)
    }

    func testBrowseLeftRightModeSelectionDefers() async {
        var config = TabConfig.default
        config.directional.commitOnModifierRelease = true
        config.directional.browseLeftRightMode = .selection
        let harness = makeHarness(
            snapshots: [
                snapshot(windowId: 10, pid: 1001, appName: "Alpha", title: "A"),
                snapshot(windowId: 20, pid: 1002, appName: "Beta", title: "B"),
                snapshot(windowId: 30, pid: 1003, appName: "Gamma", title: "C"),
            ],
            focusedWindowID: 10,
            config: config
        )

        await harness.coordinator.handleHotkey(direction: .up, hotkeyTimestamp: .now())
        await harness.coordinator.handleHotkey(direction: .right, hotkeyTimestamp: .now())
        XCTAssertTrue(harness.focus.calls.isEmpty)

        await harness.coordinator.commitOrEndSessionOnModifierRelease(commitTimestamp: .now())
        XCTAssertEqual(harness.focus.calls.count, 1)
    }

    func testLeftRightSkipsWindowlessGroups() async {
        var config = TabConfig.default
        config.visibility.showEmptyApps = .show
        let pid: pid_t = 4444
        let synthetic = UInt32.max - UInt32(pid % Int32.max)
        let harness = makeHarness(
            snapshots: [
                snapshot(windowId: 10, pid: 1001, appName: "Alpha", title: "A"),
                WindowSnapshot(
                    windowId: synthetic,
                    pid: pid,
                    bundleId: "bundle.windowless",
                    appName: "Windowless",
                    frame: .zero,
                    isMinimized: false,
                    appIsHidden: false,
                    isFullscreen: false,
                    title: nil,
                    isWindowlessApp: true
                ),
                snapshot(windowId: 30, pid: 1003, appName: "Gamma", title: "C"),
            ],
            focusedWindowID: 10,
            config: config
        )

        await harness.coordinator.handleHotkey(direction: .right, hotkeyTimestamp: .now())

        XCTAssertEqual(harness.focus.calls.last?.windowId, 30)
        XCTAssertEqual(harness.hud.lastModel?.items.count, 2)
    }

    func testBrowseRespectsShowEmptyAppsPolicyShowAtEnd() async {
        var config = TabConfig.default
        config.visibility.showEmptyApps = .showAtEnd
        let pid: pid_t = 4444
        let synthetic = UInt32.max - UInt32(pid % Int32.max)
        let harness = makeHarness(
            snapshots: [
                snapshot(windowId: 10, pid: 1001, appName: "Alpha", title: "A"),
                WindowSnapshot(
                    windowId: synthetic,
                    pid: pid,
                    bundleId: "bundle.windowless",
                    appName: "Beta",
                    frame: .zero,
                    isMinimized: false,
                    appIsHidden: false,
                    isFullscreen: false,
                    title: nil,
                    isWindowlessApp: true
                ),
                snapshot(windowId: 30, pid: 1003, appName: "Gamma", title: "C"),
            ],
            focusedWindowID: 10,
            config: config
        )

        await harness.coordinator.handleHotkey(direction: .up, hotkeyTimestamp: .now())

        let items = harness.hud.lastModel?.items ?? []
        XCTAssertEqual(items.last?.label, "Beta")
        XCTAssertEqual(items.last?.isWindowlessApp, true)
    }

    func testBrowseReleaseWithMissingTargetNoCrashCleanEnd() async {
        var config = TabConfig.default
        config.directional.commitOnModifierRelease = true
        config.directional.browseLeftRightMode = .selection
        let harness = makeHarness(
            snapshots: [
                snapshot(windowId: 10, pid: 1001, appName: "Alpha", title: "A"),
                snapshot(windowId: 20, pid: 1002, appName: "Beta", title: "B"),
            ],
            focusedWindowID: 10,
            config: config
        )

        await harness.coordinator.handleHotkey(direction: .up, hotkeyTimestamp: .now())
        harness.provider.snapshots = []

        await harness.coordinator.commitOrEndSessionOnModifierRelease(commitTimestamp: .now())

        XCTAssertTrue(harness.focus.calls.isEmpty)
        XCTAssertEqual(harness.hud.hideCalls, 1)
        XCTAssertFalse(harness.coordinator.hasActiveSession())
    }

    private func makeHarness(
        snapshots: [WindowSnapshot],
        focusedWindowID: UInt32?,
        config: TabConfig = .default
    ) -> DirectionalHarness {
        let provider = DirectionalFakeWindowProvider(snapshots: snapshots)
        let focused = DirectionalFakeFocusedWindowProvider(focusedWindowID: focusedWindowID)
        let focus = DirectionalFakeFocusPerformer()
        let hud = DirectionalFakeHUDController()
        let terminator = DirectionalFakeAppTerminationPerformer()
        let closer = DirectionalFakeWindowClosePerformer()
        let coordinator = DirectionalCoordinator(
            windowProvider: provider,
            focusedWindowProvider: focused,
            focusPerformer: focus,
            appTerminationPerformer: terminator,
            windowClosePerformer: closer,
            hudController: hud,
            config: config
        )
        return DirectionalHarness(
            coordinator: coordinator,
            provider: provider,
            focused: focused,
            focus: focus,
            hud: hud,
            terminator: terminator,
            closer: closer
        )
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

private struct DirectionalHarness {
    let coordinator: DirectionalCoordinator
    let provider: DirectionalFakeWindowProvider
    let focused: DirectionalFakeFocusedWindowProvider
    let focus: DirectionalFakeFocusPerformer
    let hud: DirectionalFakeHUDController
    let terminator: DirectionalFakeAppTerminationPerformer
    let closer: DirectionalFakeWindowClosePerformer
}

@MainActor
private final class DirectionalFakeWindowProvider: WindowProvider {
    var snapshots: [WindowSnapshot]

    init(snapshots: [WindowSnapshot]) {
        self.snapshots = snapshots
    }

    func currentSnapshot() async throws -> [WindowSnapshot] {
        snapshots
    }
}

@MainActor
private final class DirectionalFakeFocusedWindowProvider: FocusedWindowProvider {
    var focusedWindowIDValue: UInt32?

    init(focusedWindowID: UInt32?) {
        focusedWindowIDValue = focusedWindowID
    }

    func focusedWindowID() async -> UInt32? {
        focusedWindowIDValue
    }
}

@MainActor
private final class DirectionalFakeFocusPerformer: FocusPerformer {
    var calls: [(windowId: UInt32, pid: pid_t)] = []

    func focus(windowId: UInt32, pid: pid_t) async throws {
        calls.append((windowId: windowId, pid: pid))
    }
}

@MainActor
private final class DirectionalFakeHUDController: HUDControlling {
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
private final class DirectionalFakeAppTerminationPerformer: AppTerminationPerformer {
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

@MainActor
private final class DirectionalFakeWindowClosePerformer: WindowClosePerformer {
    var calls: [(windowId: UInt32, pid: pid_t)] = []
    var result = true

    func close(windowId: UInt32, pid: pid_t) -> Bool {
        calls.append((windowId: windowId, pid: pid))
        return result
    }
}
