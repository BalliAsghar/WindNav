import AppKit
import CoreGraphics
@testable import WindNavCore
import XCTest

@MainActor
final class BrowseFlowControllerTests: XCTestCase {
    func testStartSessionShowsHUDWithoutSelectionAndNoFocus() async {
        let snapshots = [
            snapshot(windowId: 1, pid: 101, bundleId: "app.alpha", x: 50_000, y: 50_000),
            snapshot(windowId: 2, pid: 202, bundleId: "app.beta", x: 60_000, y: 60_000),
        ]
        let harness = makeHarness(
            snapshots: snapshots,
            focusedWindowID: nil,
            mouseLocation: onScreenMousePoint()
        )

        harness.controller.startSessionIfNeeded()
        harness.controller.handleDirection(.up)
        await waitUntil {
            harness.hudController.lastModel != nil
        }

        XCTAssertTrue(harness.controller.isSessionActive)
        XCTAssertTrue(harness.focusPerformer.calls.isEmpty)
        XCTAssertEqual(harness.hudController.lastTimeoutMs, 0)
    }

    func testMoveRightSelectsFromNilThenWraps() async {
        let snapshots = [
            snapshot(windowId: 1, pid: 101, bundleId: "app.alpha", x: 50_000, y: 50_000),
            snapshot(windowId: 2, pid: 202, bundleId: "app.beta", x: 60_000, y: 60_000),
        ]
        let harness = makeHarness(
            snapshots: snapshots,
            focusedWindowID: nil,
            mouseLocation: onScreenMousePoint()
        )

        harness.controller.startSessionIfNeeded()
        await waitUntil {
            harness.hudController.lastModel != nil
        }

        harness.controller.handleDirection(.right)
        XCTAssertEqual(harness.hudController.lastModel?.selectedIndex, 0)

        harness.controller.handleDirection(.right)
        XCTAssertEqual(harness.hudController.lastModel?.selectedIndex, 1)

        harness.controller.handleDirection(.right)
        XCTAssertEqual(harness.hudController.lastModel?.selectedIndex, 0)
        XCTAssertTrue(harness.focusPerformer.calls.isEmpty)
    }

    func testMoveLeftSelectsLastFromNil() async {
        let snapshots = [
            snapshot(windowId: 1, pid: 101, bundleId: "app.alpha", x: 50_000, y: 50_000),
            snapshot(windowId: 2, pid: 202, bundleId: "app.beta", x: 60_000, y: 60_000),
        ]
        let harness = makeHarness(
            snapshots: snapshots,
            focusedWindowID: nil,
            mouseLocation: onScreenMousePoint()
        )

        harness.controller.startSessionIfNeeded()
        await waitUntil {
            harness.hudController.lastModel != nil
        }

        harness.controller.handleDirection(.left)
        XCTAssertEqual(harness.hudController.lastModel?.selectedIndex, 1)
        XCTAssertTrue(harness.focusPerformer.calls.isEmpty)
    }

    func testCommitWithSelectionFocusesOnce() async {
        let snapshots = [
            snapshot(windowId: 1, pid: 101, bundleId: "app.alpha", x: 50_000, y: 50_000),
            snapshot(windowId: 2, pid: 202, bundleId: "app.beta", x: 60_000, y: 60_000),
        ]
        let harness = makeHarness(
            snapshots: snapshots,
            focusedWindowID: nil,
            mouseLocation: onScreenMousePoint()
        )

        harness.controller.startSessionIfNeeded()
        await waitUntil {
            harness.hudController.lastModel != nil
        }
        harness.controller.handleDirection(.left)
        harness.controller.commitSessionOnModifierRelease()

        await waitUntil {
            !harness.focusPerformer.calls.isEmpty
        }

        XCTAssertFalse(harness.controller.isSessionActive)
        XCTAssertEqual(harness.focusPerformer.calls.count, 1)
        XCTAssertEqual(harness.focusPerformer.calls[0].pid, 202)
    }

    func testCommitWithoutSelectionDoesNotFocus() async {
        let snapshots = [
            snapshot(windowId: 1, pid: 101, bundleId: "app.alpha", x: 50_000, y: 50_000),
            snapshot(windowId: 2, pid: 202, bundleId: "app.beta", x: 60_000, y: 60_000),
        ]
        let harness = makeHarness(
            snapshots: snapshots,
            focusedWindowID: nil,
            mouseLocation: onScreenMousePoint()
        )

        harness.controller.startSessionIfNeeded()
        await waitUntil {
            harness.hudController.lastModel != nil
        }
        harness.controller.commitSessionOnModifierRelease()
        try? await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertFalse(harness.controller.isSessionActive)
        XCTAssertTrue(harness.focusPerformer.calls.isEmpty)
        XCTAssertGreaterThanOrEqual(harness.hudController.hideCalls, 1)
    }

    func testCommitWhenSelectedAppDisappearsDoesNotFocus() async {
        let snapshots = [
            snapshot(windowId: 1, pid: 101, bundleId: "app.alpha", x: 50_000, y: 50_000),
            snapshot(windowId: 2, pid: 202, bundleId: "app.beta", x: 60_000, y: 60_000),
        ]
        let harness = makeHarness(
            snapshots: snapshots,
            focusedWindowID: nil,
            mouseLocation: onScreenMousePoint()
        )

        harness.controller.startSessionIfNeeded()
        await waitUntil {
            harness.hudController.lastModel != nil
        }
        harness.controller.handleDirection(.left)

        harness.windowProvider.snapshots = [
            snapshot(windowId: 1, pid: 101, bundleId: "app.alpha", x: 50_000, y: 50_000),
        ]
        harness.controller.commitSessionOnModifierRelease()
        try? await Task.sleep(nanoseconds: 80_000_000)

        XCTAssertFalse(harness.controller.isSessionActive)
        XCTAssertTrue(harness.focusPerformer.calls.isEmpty)
    }

    private func makeHarness(
        snapshots: [WindowSnapshot],
        focusedWindowID: UInt32?,
        mouseLocation: CGPoint
    ) -> Harness {
        let windowProvider = FakeWindowProvider(snapshots: snapshots)
        let cache = WindowStateCache(provider: windowProvider)
        let focusPerformer = FakeFocusPerformer()
        let focusedProvider = FakeFocusedWindowProvider(focusedWindowID: focusedWindowID)
        let hudController = FakeHUDController()
        let controller = BrowseFlowController(
            cache: cache,
            focusedWindowProvider: focusedProvider,
            focusPerformer: focusPerformer,
            appRingStateStore: AppRingStateStore(),
            appFocusMemoryStore: AppFocusMemoryStore(),
            hudController: hudController,
            navigationConfig: .default,
            hudConfig: .default,
            mouseLocationProvider: { mouseLocation }
        )
        return Harness(
            controller: controller,
            focusPerformer: focusPerformer,
            hudController: hudController,
            windowProvider: windowProvider
        )
    }

    private func waitUntil(
        timeoutNs: UInt64 = 1_000_000_000,
        pollNs: UInt64 = 10_000_000,
        condition: @escaping @MainActor () -> Bool
    ) async {
        let start = DispatchTime.now().uptimeNanoseconds
        while DispatchTime.now().uptimeNanoseconds - start < timeoutNs {
            if condition() {
                return
            }
            try? await Task.sleep(nanoseconds: pollNs)
        }
        XCTFail("Timed out waiting for condition")
    }

    private func onScreenMousePoint() -> CGPoint {
        if let screen = NSScreen.screens.first {
            return CGPoint(x: screen.frame.midX, y: screen.frame.midY)
        }
        return .zero
    }

    private func snapshot(windowId: UInt32, pid: pid_t, bundleId: String?, x: CGFloat, y: CGFloat) -> WindowSnapshot {
        WindowSnapshot(
            windowId: windowId,
            pid: pid,
            bundleId: bundleId,
            frame: CGRect(x: x, y: y, width: 120, height: 100),
            isMinimized: false,
            appIsHidden: false,
            title: nil
        )
    }
}

private struct Harness {
    let controller: BrowseFlowController
    let focusPerformer: FakeFocusPerformer
    let hudController: FakeHUDController
    let windowProvider: FakeWindowProvider
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
private final class FakeHUDController: CycleHUDControlling {
    var lastModel: CycleHUDModel?
    var lastTimeoutMs: Int?
    var hideCalls = 0

    func show(model: CycleHUDModel, config: HUDConfig, timeoutMs: Int) {
        lastModel = model
        lastTimeoutMs = timeoutMs
    }

    func hide() {
        hideCalls += 1
    }
}
