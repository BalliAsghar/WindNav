@testable import TabCore
import CoreGraphics
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

    func testThumbnailCallbackUpdatesDirectionalHUD() async {
        let harness = makeHarness(
            snapshots: [
                snapshot(windowId: 10, pid: 1001, appName: "Alpha"),
                snapshot(windowId: 20, pid: 1002, appName: "Beta"),
            ],
            focusedWindowID: 10,
            config: .default
        )

        await harness.coordinator.handleHotkey(direction: .up, hotkeyTimestamp: .now())
        let baselineShowCalls = harness.hud.showCalls

        harness.thumbnails.emit(windowId: 10)
        try? await Task.sleep(nanoseconds: 60_000_000)

        XCTAssertGreaterThan(harness.hud.showCalls, baselineShowCalls)
        XCTAssertNotNil(harness.hud.lastModel?.items.first(where: { $0.id == "10" })?.thumbnail)
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
        let thumbnails = DirectionalFakeThumbnailService()
        let terminator = DirectionalFakeAppTerminationPerformer()
        let closer = DirectionalFakeWindowClosePerformer()
        let coordinator = DirectionalCoordinator(
            windowProvider: provider,
            focusedWindowProvider: focused,
            focusPerformer: focus,
            appTerminationPerformer: terminator,
            windowClosePerformer: closer,
            hudController: hud,
            thumbnailService: thumbnails,
            config: config
        )
        return DirectionalHarness(
            coordinator: coordinator,
            provider: provider,
            focus: focus,
            hud: hud,
            closer: closer,
            thumbnails: thumbnails
        )
    }

    private func snapshot(windowId: UInt32, pid: pid_t, appName: String) -> WindowSnapshot {
        WindowSnapshot(
            windowId: windowId,
            pid: pid,
            bundleId: "bundle.\(appName.lowercased())",
            appName: appName,
            frame: CGRect(x: 10, y: 10, width: 100, height: 80),
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
    let thumbnails: DirectionalFakeThumbnailService
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
    var showCalls = 0

    func show(model: HUDModel, appearance: AppearanceConfig) {
        lastModel = model
        showCalls += 1
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

private final class DirectionalFakeThumbnailService: WindowThumbnailProviding {
    var cache: [UInt32: CGImage] = [:]
    private var update: (@MainActor (_ windowID: UInt32, _ image: CGImage) -> Void)?

    func cachedThumbnails(for windowIDs: [UInt32]) -> [UInt32: CGImage] {
        var output: [UInt32: CGImage] = [:]
        for windowID in windowIDs {
            if let image = cache[windowID] {
                output[windowID] = image
            }
        }
        return output
    }

    func requestThumbnails(
        for snapshots: [WindowSnapshot],
        thumbnailWidth: Int,
        onUpdate: @escaping @MainActor (_ windowID: UInt32, _ image: CGImage) -> Void
    ) {
        update = onUpdate
    }

    func clear() {
        cache.removeAll()
    }

    @MainActor
    func emit(windowId: UInt32) {
        let image = Self.makeImage()
        cache[windowId] = image
        update?(windowId, image)
    }

    private static func makeImage() -> CGImage {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
        let context = CGContext(
            data: nil,
            width: 8,
            height: 8,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        )!
        context.setFillColor(CGColor(red: 0.8, green: 0.5, blue: 0.3, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        return context.makeImage()!
    }
}
