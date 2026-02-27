import AppKit
import CoreGraphics
@testable import WindNavCore
import XCTest

@MainActor
final class NavigationCoordinatorTests: XCTestCase {
    func testNoFocusRightSelectsFirstAppEvenWhenMonitorCandidatesEmpty() async {
        let snapshots = [
            snapshot(windowId: 1, pid: 101, bundleId: "app.alpha", x: 50_000, y: 50_000),
            snapshot(windowId: 2, pid: 202, bundleId: "app.beta", x: 60_000, y: 60_000),
        ]

        let harness = makeHarness(
            snapshots: snapshots,
            focusedWindowID: nil,
            mouseLocation: onScreenMousePoint()
        )

        harness.coordinator.enqueue(.right)
        await waitUntil {
            !harness.focusPerformer.calls.isEmpty
        }

        XCTAssertEqual(harness.focusPerformer.calls.count, 1)
        XCTAssertEqual(harness.focusPerformer.calls[0].pid, 101)
        XCTAssertEqual(harness.hudController.lastModel?.selectedIndex, 0)
    }

    func testNoFocusLeftSelectsLastApp() async {
        let snapshots = [
            snapshot(windowId: 1, pid: 101, bundleId: "app.alpha", x: 50_000, y: 50_000),
            snapshot(windowId: 2, pid: 202, bundleId: "app.beta", x: 60_000, y: 60_000),
        ]

        let harness = makeHarness(
            snapshots: snapshots,
            focusedWindowID: nil,
            mouseLocation: onScreenMousePoint()
        )

        harness.coordinator.enqueue(.left)
        await waitUntil {
            !harness.focusPerformer.calls.isEmpty
        }

        XCTAssertEqual(harness.focusPerformer.calls.count, 1)
        XCTAssertEqual(harness.focusPerformer.calls[0].pid, 202)
        XCTAssertEqual(harness.hudController.lastModel?.selectedIndex, 1)
    }

    func testNoFocusUpShowsPreviewHUDWithoutSelection() async {
        let snapshots = [
            snapshot(windowId: 1, pid: 101, bundleId: "app.alpha", x: 50_000, y: 50_000),
            snapshot(windowId: 2, pid: 202, bundleId: "app.beta", x: 60_000, y: 60_000),
        ]

        let harness = makeHarness(
            snapshots: snapshots,
            focusedWindowID: nil,
            mouseLocation: onScreenMousePoint()
        )

        harness.coordinator.enqueue(.up)
        await waitUntil {
            harness.hudController.lastModel != nil
        }

        XCTAssertTrue(harness.focusPerformer.calls.isEmpty)
        XCTAssertNil(harness.hudController.lastModel?.selectedIndex)
        XCTAssertEqual(harness.hudController.lastModel?.items.count, 2)
        XCTAssertEqual(harness.hudController.lastModel?.items.allSatisfy { !$0.isCurrent }, true)
    }

    func testNoFocusDownShowsPreviewHUDWithoutSelection() async {
        let snapshots = [
            snapshot(windowId: 1, pid: 101, bundleId: "app.alpha", x: 50_000, y: 50_000),
            snapshot(windowId: 2, pid: 202, bundleId: "app.beta", x: 60_000, y: 60_000),
        ]

        let harness = makeHarness(
            snapshots: snapshots,
            focusedWindowID: nil,
            mouseLocation: onScreenMousePoint()
        )

        harness.coordinator.enqueue(.down)
        await waitUntil {
            harness.hudController.lastModel != nil
        }

        XCTAssertTrue(harness.focusPerformer.calls.isEmpty)
        XCTAssertNil(harness.hudController.lastModel?.selectedIndex)
        XCTAssertEqual(harness.hudController.lastModel?.items.allSatisfy { !$0.isCurrent }, true)
    }

    func testFocusedWindowPathStillNavigatesToNextAppOnRight() async {
        let screenFrame = NSScreen.screens.first?.frame ?? CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let snapshots = [
            snapshot(windowId: 1, pid: 101, bundleId: "app.alpha", x: screenFrame.minX + 80, y: screenFrame.minY + 80),
            snapshot(windowId: 2, pid: 202, bundleId: "app.beta", x: screenFrame.minX + 320, y: screenFrame.minY + 80),
        ]

        let harness = makeHarness(
            snapshots: snapshots,
            focusedWindowID: 1,
            mouseLocation: onScreenMousePoint()
        )

        harness.coordinator.enqueue(.right)
        await waitUntil {
            !harness.focusPerformer.calls.isEmpty
        }

        XCTAssertEqual(harness.focusPerformer.calls.count, 1)
        XCTAssertEqual(harness.focusPerformer.calls[0].pid, 202)
        XCTAssertEqual(harness.hudController.lastModel?.selectedIndex, 1)
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
        let coordinator = NavigationCoordinator(
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
            coordinator: coordinator,
            focusPerformer: focusPerformer,
            hudController: hudController
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
    let coordinator: NavigationCoordinator
    let focusPerformer: FakeFocusPerformer
    let hudController: FakeHUDController
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

    func show(model: CycleHUDModel, config: HUDConfig, timeoutMs: Int) {
        lastModel = model
    }

    func hide() {
        // no-op for tests
    }
}
