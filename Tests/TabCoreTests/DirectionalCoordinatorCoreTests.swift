@testable import TabCore
import Foundation
import XCTest

@MainActor
final class DirectionalCoordinatorCoreTests: XCTestCase {
    func testBrowseSelectionCommitsOnRelease() async {
        var config = TabConfig.default
        config.directional.commitOnModifierRelease = true
        config.directional.browseLeftRightMode = .selection

        let harness = makeHarness(
            snapshots: [
                snapshot(windowId: 10, pid: 1001, appName: "Alpha"),
                snapshot(windowId: 20, pid: 1002, appName: "Beta"),
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

    func testBrowseImmediateFocusesOnLeftRight() async {
        var config = TabConfig.default
        config.directional.commitOnModifierRelease = true
        config.directional.browseLeftRightMode = .immediate

        let harness = makeHarness(
            snapshots: [
                snapshot(windowId: 10, pid: 1001, appName: "Alpha"),
                snapshot(windowId: 20, pid: 1002, appName: "Beta"),
                snapshot(windowId: 30, pid: 1003, appName: "Gamma"),
            ],
            focusedWindowID: 10,
            config: config
        )

        await harness.coordinator.handleHotkey(direction: .up, hotkeyTimestamp: .now())
        await harness.coordinator.handleHotkey(direction: .right, hotkeyTimestamp: .now())

        XCTAssertEqual(harness.focus.calls.count, 1)
    }

    func testRepeatedUpClosesActiveBrowseSessionWithoutFocusOrCommit() async {
        var config = TabConfig.default
        config.directional.commitOnModifierRelease = true
        config.directional.browseLeftRightMode = .selection

        let harness = makeHarness(
            snapshots: [
                snapshot(windowId: 10, pid: 1001, appName: "Alpha"),
                snapshot(windowId: 20, pid: 1002, appName: "Beta"),
            ],
            focusedWindowID: 10,
            config: config
        )

        await harness.coordinator.handleHotkey(direction: .up, hotkeyTimestamp: .now())
        XCTAssertTrue(harness.coordinator.hasActiveSession())
        XCTAssertEqual(harness.hud.hideCalls, 0)

        await harness.coordinator.handleHotkey(direction: .up, hotkeyTimestamp: .now())

        XCTAssertFalse(harness.coordinator.hasActiveSession())
        XCTAssertEqual(harness.hud.hideCalls, 1)
        XCTAssertTrue(harness.focus.calls.isEmpty)

        await harness.coordinator.commitOrEndSessionOnModifierRelease(commitTimestamp: .now())

        XCTAssertTrue(harness.focus.calls.isEmpty)
        XCTAssertEqual(harness.hud.hideCalls, 1)
    }

    func testDownClosesActiveBrowseSessionWithoutFocus() async {
        var config = TabConfig.default
        config.directional.commitOnModifierRelease = true
        config.directional.browseLeftRightMode = .selection

        let harness = makeHarness(
            snapshots: [
                snapshot(windowId: 10, pid: 1001, appName: "Alpha"),
                snapshot(windowId: 20, pid: 1002, appName: "Beta"),
            ],
            focusedWindowID: 10,
            config: config
        )

        await harness.coordinator.handleHotkey(direction: .up, hotkeyTimestamp: .now())
        XCTAssertTrue(harness.coordinator.hasActiveSession())

        await harness.coordinator.handleHotkey(direction: .down, hotkeyTimestamp: .now())

        XCTAssertFalse(harness.coordinator.hasActiveSession())
        XCTAssertEqual(harness.hud.hideCalls, 1)
        XCTAssertTrue(harness.focus.calls.isEmpty)
    }

    func testCloseSelectedWindowRefreshesBrowseSession() async {
        let harness = makeHarness(
            snapshots: [
                snapshot(windowId: 10, pid: 1001, appName: "Alpha"),
                snapshot(windowId: 20, pid: 1002, appName: "Beta"),
            ],
            focusedWindowID: 10,
            config: .default
        )

        await harness.coordinator.handleHotkey(direction: .up, hotkeyTimestamp: .now())
        harness.provider.snapshots = [snapshot(windowId: 10, pid: 1001, appName: "Alpha")]
        await harness.coordinator.requestCloseSelectedWindowInSession()

        XCTAssertEqual(harness.closer.calls.count, 1)
        XCTAssertEqual(harness.hud.lastModel?.items.count, 1)
        XCTAssertTrue(harness.coordinator.hasActiveSession())
    }

    private func makeHarness(
        snapshots: [WindowSnapshot],
        focusedWindowID: UInt32?,
        config: TabConfig
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

private struct DirectionalHarness {
    let coordinator: DirectionalCoordinator
    let provider: DirectionalFakeWindowProvider
    let focus: DirectionalFakeFocusPerformer
    let hud: DirectionalFakeHUDController
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
        self.focusedWindowIDValue = focusedWindowID
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

    func show(model: HUDModel, appearance: AppearanceConfig, hud: HUDConfig) {
        lastModel = model
    }

    func hide() {
        hideCalls += 1
    }
}

@MainActor
private final class DirectionalFakeAppTerminationPerformer: AppTerminationPerformer {
    func terminate(pid: pid_t) {}
    func forceTerminate(pid: pid_t) {}
    func bundleIdentifier(pid: pid_t) -> String? { nil }
}

@MainActor
private final class DirectionalFakeWindowClosePerformer: WindowClosePerformer {
    var calls: [(windowId: UInt32, pid: pid_t)] = []

    func close(windowId: UInt32, pid: pid_t) -> Bool {
        calls.append((windowId: windowId, pid: pid))
        return true
    }
}
