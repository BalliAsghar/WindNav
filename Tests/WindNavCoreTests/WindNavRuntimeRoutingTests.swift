import AppKit
import Carbon
import CoreGraphics
@testable import WindNavCore
import XCTest

@MainActor
final class WindNavRuntimeRoutingTests: XCTestCase {
    func testFirstKeyUpStartsBrowseFlowWithoutImmediateFocus() async {
        let harness = makeHarness(initialFocusedWindowID: 2)

        harness.runtime.handleHotkey(.up, carbonModifiers: UInt32(cmdKey))
        await waitUntil {
            harness.hudController.lastModel != nil
        }

        XCTAssertTrue(harness.browseController.isSessionActive)
        XCTAssertTrue(harness.focusPerformer.calls.isEmpty)
    }

    func testFirstKeyRightLocksNavigationFlowThenUpCyclesWindowImmediately() async {
        let harness = makeHarness(initialFocusedWindowID: 2)

        harness.runtime.handleHotkey(.right, carbonModifiers: UInt32(cmdKey))
        await waitUntil {
            harness.focusPerformer.calls.count == 1
        }

        harness.runtime.handleHotkey(.up, carbonModifiers: UInt32(cmdKey))
        await waitUntil {
            harness.focusPerformer.calls.count == 2
        }

        XCTAssertFalse(harness.browseController.isSessionActive)
        XCTAssertEqual(harness.focusPerformer.calls[0].windowId, 1)
        XCTAssertEqual(harness.focusPerformer.calls[1].windowId, 3)
        let current = harness.hudController.lastModel?.items.first(where: { $0.isCurrent })
        XCTAssertEqual(current?.windowCount, 2)
        XCTAssertNotNil(current?.currentWindowIndex)
    }

    func testFirstKeyUpLocksBrowseFlowThenRightStaysDeferred() async {
        let harness = makeHarness(initialFocusedWindowID: 2)

        harness.runtime.handleHotkey(.up, carbonModifiers: UInt32(cmdKey))
        await waitUntil {
            harness.hudController.lastModel != nil
        }

        harness.runtime.handleHotkey(.right, carbonModifiers: UInt32(cmdKey))
        try? await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertTrue(harness.browseController.isSessionActive)
        XCTAssertTrue(harness.focusPerformer.calls.isEmpty)
    }

    func testModifierReleaseCommitsBrowseFlowSelection() async {
        let harness = makeHarness(initialFocusedWindowID: 2)
        harness.runtime._setHoldCycleUntilModifierReleaseForTests(false)

        harness.runtime.handleHotkey(.up, carbonModifiers: UInt32(cmdKey))
        await waitUntil {
            harness.hudController.lastModel != nil
        }
        harness.runtime.handleHotkey(.up, carbonModifiers: UInt32(cmdKey))
        harness.runtime.handleModifierFlagsChanged([])

        await waitUntil {
            !harness.focusPerformer.calls.isEmpty
        }

        XCTAssertEqual(harness.focusPerformer.calls.count, 1)
        XCTAssertEqual(harness.focusPerformer.calls[0].windowId, 2)
        XCTAssertFalse(harness.browseController.isSessionActive)
    }

    func testModifierReleaseEndsNavFlowCycleHUDWhenHoldCycleEnabled() async {
        let harness = makeHarness(initialFocusedWindowID: 2)
        harness.runtime._setHoldCycleUntilModifierReleaseForTests(true)

        harness.runtime.handleHotkey(.right, carbonModifiers: UInt32(cmdKey))
        await waitUntil {
            harness.hudController.lastModel != nil
        }

        harness.runtime.handleModifierFlagsChanged([])

        XCTAssertGreaterThanOrEqual(harness.hudController.hideCalls, 1)
    }

    private func makeHarness(initialFocusedWindowID: UInt32?) -> RuntimeHarness {
        let screenFrame = NSScreen.screens.first?.frame ?? CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let snapshots = [
            snapshot(windowId: 1, pid: 101, bundleId: "app.alpha", x: screenFrame.minX + 80, y: screenFrame.minY + 80),
            snapshot(windowId: 3, pid: 101, bundleId: "app.alpha", x: 50_000, y: 50_000),
            snapshot(windowId: 2, pid: 202, bundleId: "app.beta", x: screenFrame.minX + 500, y: screenFrame.minY + 80),
        ]

        let focusState = RuntimeFocusState(focusedWindowID: initialFocusedWindowID)
        let windowProvider = RuntimeFakeWindowProvider(snapshots: snapshots)
        let cache = WindowStateCache(provider: windowProvider)
        let focusedProvider = RuntimeFakeFocusedWindowProvider(state: focusState)
        let focusPerformer = RuntimeFakeFocusPerformer(state: focusState)
        let hudController = RuntimeFakeHUDController()
        let appRingStateStore = AppRingStateStore()
        let appFocusMemoryStore = AppFocusMemoryStore()

        let navigationController = NavigationCoordinator(
            cache: cache,
            focusedWindowProvider: focusedProvider,
            focusPerformer: focusPerformer,
            appRingStateStore: appRingStateStore,
            appFocusMemoryStore: appFocusMemoryStore,
            hudController: hudController,
            navigationConfig: .default,
            hudConfig: .default,
            mouseLocationProvider: {
                if let screen = NSScreen.screens.first {
                    return CGPoint(x: screen.frame.midX, y: screen.frame.midY)
                }
                return .zero
            }
        )
        let browseController = BrowseFlowController(
            cache: cache,
            focusedWindowProvider: focusedProvider,
            focusPerformer: focusPerformer,
            appRingStateStore: appRingStateStore,
            appFocusMemoryStore: appFocusMemoryStore,
            hudController: hudController,
            navigationConfig: .default,
            hudConfig: .default,
            mouseLocationProvider: {
                if let screen = NSScreen.screens.first {
                    return CGPoint(x: screen.frame.midX, y: screen.frame.midY)
                }
                return .zero
            }
        )

        let manager = RuntimeFakeLaunchAtLoginManager()
        let runtime = WindNavRuntime(configURL: nil, launchAtLoginManager: manager)
        runtime._setControllersForTests(navigation: navigationController, browse: browseController)

        return RuntimeHarness(
            runtime: runtime,
            browseController: browseController,
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

private struct RuntimeHarness {
    let runtime: WindNavRuntime
    let browseController: BrowseFlowController
    let focusPerformer: RuntimeFakeFocusPerformer
    let hudController: RuntimeFakeHUDController
}

@MainActor
private final class RuntimeFocusState {
    var focusedWindowID: UInt32?

    init(focusedWindowID: UInt32?) {
        self.focusedWindowID = focusedWindowID
    }
}

@MainActor
private final class RuntimeFakeWindowProvider: WindowProvider {
    var snapshots: [WindowSnapshot]

    init(snapshots: [WindowSnapshot]) {
        self.snapshots = snapshots
    }

    func currentSnapshot() async throws -> [WindowSnapshot] {
        snapshots
    }
}

@MainActor
private final class RuntimeFakeFocusedWindowProvider: FocusedWindowProvider {
    let state: RuntimeFocusState

    init(state: RuntimeFocusState) {
        self.state = state
    }

    func focusedWindowID() async -> UInt32? {
        state.focusedWindowID
    }
}

@MainActor
private final class RuntimeFakeFocusPerformer: FocusPerformer {
    let state: RuntimeFocusState
    var calls: [(windowId: UInt32, pid: pid_t)] = []

    init(state: RuntimeFocusState) {
        self.state = state
    }

    func focus(windowId: UInt32, pid: pid_t) async throws {
        calls.append((windowId: windowId, pid: pid))
        state.focusedWindowID = windowId
    }
}

@MainActor
private final class RuntimeFakeHUDController: CycleHUDControlling {
    var lastModel: CycleHUDModel?
    var hideCalls = 0

    func show(model: CycleHUDModel, config: HUDConfig, timeoutMs: Int) {
        lastModel = model
    }

    func hide() {
        hideCalls += 1
    }
}

private final class RuntimeFakeLaunchAtLoginManager: LaunchAtLoginManaging {
    var isEnabled = false
    var statusDescription: String = "notRegistered"

    func setEnabled(_ enabled: Bool) throws {
        isEnabled = enabled
        statusDescription = enabled ? "enabled" : "notRegistered"
    }
}
