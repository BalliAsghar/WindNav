@testable import TabCore
import AppKit
import Foundation
import XCTest

final class InternalCleanupCoreTests: XCTestCase {
    func testSyntheticWindowIDRoundTripsPID() {
        let pid: pid_t = 4242
        let synthetic = SyntheticWindowID.make(pid: pid)

        XCTAssertTrue(SyntheticWindowID.matches(windowId: synthetic, pid: pid))
        XCTAssertFalse(SyntheticWindowID.matches(windowId: synthetic - 1, pid: pid))
    }

    func testWrappedIndexHandlesNegativeAndOverflowValues() {
        XCTAssertEqual(WindowSnapshotSupport.wrappedIndex(-1, count: 3), 2)
        XCTAssertEqual(WindowSnapshotSupport.wrappedIndex(3, count: 3), 0)
        XCTAssertEqual(WindowSnapshotSupport.wrappedIndex(0, count: 0), 0)
    }

    func testSnapshotFilteringAndWindowlessOrderingPreserveRules() {
        let snapshots: [WindowSnapshot] = [
            .init(
                windowId: 1,
                pid: 101,
                bundleId: "com.apple.finder",
                appName: "Finder",
                frame: .zero,
                isMinimized: false,
                appIsHidden: false,
                isFullscreen: false,
                title: "Finder",
                isWindowlessApp: true
            ),
            .init(
                windowId: 2,
                pid: 102,
                bundleId: "com.example.hidden",
                appName: "Hidden",
                frame: .zero,
                isMinimized: false,
                appIsHidden: true,
                isFullscreen: false,
                title: "Hidden"
            ),
            .init(
                windowId: 3,
                pid: 103,
                bundleId: "com.example.notes",
                appName: "Notes",
                frame: .zero,
                isMinimized: false,
                appIsHidden: false,
                isFullscreen: false,
                title: "Notes"
            ),
            .init(
                windowId: 4,
                pid: 104,
                bundleId: "com.example.empty",
                appName: "Empty",
                frame: .zero,
                isMinimized: false,
                appIsHidden: false,
                isFullscreen: false,
                title: "Empty",
                isWindowlessApp: true
            ),
        ]

        let filtered = WindowSnapshotSupport.applyFilters(
            snapshots,
            visibility: .init(
                showMinimized: true,
                showHidden: false,
                showFullscreen: true,
                showEmptyApps: .showAtEnd
            ),
            filters: .default
        )

        XCTAssertEqual(filtered.map(\.windowId), [3, 4])

        let reordered = WindowSnapshotSupport.applyWindowlessOrdering(
            filtered.reversed(),
            showEmptyApps: .showAtEnd
        )
        XCTAssertEqual(reordered.map(\.windowId), [3, 4])
    }

    func testSnapshotSortAndLabelHelpersProduceStableResults() {
        let alpha = WindowSnapshot(
            windowId: 20,
            pid: 200,
            bundleId: "com.example.alpha",
            appName: "Alpha",
            frame: .zero,
            isMinimized: false,
            appIsHidden: false,
            isFullscreen: false,
            title: "B"
        )
        let beta = WindowSnapshot(
            windowId: 10,
            pid: 100,
            bundleId: "com.example.beta",
            appName: "Beta",
            frame: .zero,
            isMinimized: false,
            appIsHidden: false,
            isFullscreen: false,
            title: "A"
        )

        let sorted = [beta, alpha].sorted(by: WindowSnapshotSupport.snapshotSortOrder(lhs:rhs:))
        XCTAssertEqual(sorted.map(\.windowId), [20, 10])
        XCTAssertEqual(WindowSnapshotSupport.appLabel(for: [alpha]), "Alpha")

        let bundleOnly = WindowSnapshot(
            windowId: 30,
            pid: 300,
            bundleId: "com.example.bundle",
            appName: nil,
            frame: .zero,
            isMinimized: false,
            appIsHidden: false,
            isFullscreen: false,
            title: nil
        )
        XCTAssertEqual(WindowSnapshotSupport.appLabel(for: [bundleOnly]), "com.example.bundle")
    }

    func testHUDModelFactoryBuildsBadgesForRepeatedAppWindows() {
        let windows: [WindowSnapshot] = [
            .init(
                windowId: 1,
                pid: 500,
                bundleId: "com.example.app",
                appName: "Example",
                frame: .zero,
                isMinimized: false,
                appIsHidden: false,
                isFullscreen: false,
                title: "One"
            ),
            .init(
                windowId: 2,
                pid: 500,
                bundleId: "com.example.app",
                appName: "Example",
                frame: .zero,
                isMinimized: false,
                appIsHidden: false,
                isFullscreen: false,
                title: "Two",
                isWindowlessApp: true
            ),
        ]

        let model = HUDModelFactory.makeModel(
            windows: windows,
            selectedIndex: 1,
            appearance: .default,
            hud: .default
        )

        XCTAssertEqual(model.selectedIndex, 1)
        XCTAssertEqual(model.items.map(\.windowIndexInApp), [1, 2])
        XCTAssertEqual(model.items.map(\.isSelected), [false, true])
        XCTAssertEqual(model.items.map(\.isWindowlessApp), [false, true])
        XCTAssertEqual(model.items.map(\.label), ["", ""])
    }

    @MainActor
    func testSyntheticActivationFallbackActivatesRunningAppWithoutOpeningBundle() async throws {
        let pid: pid_t = 4242
        let app = FocusFakeRunningApplication(pid: pid, bundleURL: URL(fileURLWithPath: "/Applications/IINA.app"))
        let activation = FocusFakeAppActivationService(apps: [pid: app])
        let resolver = FocusFakeWindowResolver()
        let performer = AXFocusPerformer(activationService: activation, windowResolver: resolver)

        try await performer.focus(focusSnapshot(windowId: SyntheticWindowID.make(pid: pid), pid: pid, isWindowlessApp: false))

        XCTAssertEqual(app.activateCalls.count, 1)
        XCTAssertTrue(app.activateCalls[0].contains(.activateAllWindows))
        XCTAssertTrue(app.activateCalls[0].contains(.activateIgnoringOtherApps))
        XCTAssertTrue(activation.openedApplicationURLs.isEmpty)
        XCTAssertTrue(resolver.requests.isEmpty)
    }

    @MainActor
    func testSyntheticWindowlessAppFallsBackToWorkspaceOpenWhenActivationDoesNotBecomeFrontmost() async throws {
        let pid: pid_t = 5151
        let bundleURL = URL(fileURLWithPath: "/Applications/Example.app")
        let app = FocusFakeRunningApplication(pid: pid, bundleURL: bundleURL)
        let activation = FocusFakeAppActivationService(apps: [pid: app])
        activation.frontmostPIDValue = 9999
        let performer = AXFocusPerformer(activationService: activation, windowResolver: FocusFakeWindowResolver())

        try await performer.focus(focusSnapshot(windowId: SyntheticWindowID.make(pid: pid), pid: pid, isWindowlessApp: true))

        XCTAssertEqual(app.activateCalls.count, 1)
        XCTAssertEqual(activation.openedApplicationURLs, [bundleURL])
    }

    @MainActor
    func testConcreteFullscreenSnapshotUsesWindowFocusPathAndActivation() async throws {
        let pid: pid_t = 6262
        let app = FocusFakeRunningApplication(pid: pid)
        let activation = FocusFakeAppActivationService(apps: [pid: app])
        let window = FocusFakeWindowElement()
        let resolver = FocusFakeWindowResolver(windows: [20: window])
        let performer = AXFocusPerformer(activationService: activation, windowResolver: resolver)

        try await performer.focus(focusSnapshot(windowId: 20, pid: pid, isFullscreen: true))

        XCTAssertEqual(resolver.requests.map(\.windowId), [20])
        XCTAssertEqual(window.setMainCalls, 1)
        XCTAssertEqual(window.raiseCalls, 1)
        XCTAssertEqual(app.activateCalls.count, 2)
        XCTAssertTrue(activation.openedApplicationURLs.isEmpty)
    }

    private func focusSnapshot(
        windowId: UInt32,
        pid: pid_t,
        isFullscreen: Bool = false,
        isWindowlessApp: Bool = false
    ) -> WindowSnapshot {
        WindowSnapshot(
            windowId: windowId,
            pid: pid,
            bundleId: "bundle.\(pid)",
            appName: "App \(pid)",
            frame: isWindowlessApp ? .zero : CGRect(x: 0, y: 0, width: 100, height: 80),
            isMinimized: false,
            appIsHidden: false,
            isFullscreen: isFullscreen,
            title: "App \(pid)",
            isWindowlessApp: isWindowlessApp
        )
    }
}

@MainActor
private final class FocusFakeRunningApplication: RunningApplicationControlling {
    let processIdentifier: pid_t
    var isHidden: Bool
    let bundleURL: URL?
    var unhideCalls = 0
    var activateCalls: [NSApplication.ActivationOptions] = []

    init(pid: pid_t, isHidden: Bool = false, bundleURL: URL? = nil) {
        self.processIdentifier = pid
        self.isHidden = isHidden
        self.bundleURL = bundleURL
    }

    func unhide() -> Bool {
        unhideCalls += 1
        isHidden = false
        return true
    }

    func activate(options: NSApplication.ActivationOptions) -> Bool {
        activateCalls.append(options)
        return true
    }
}

@MainActor
private final class FocusFakeAppActivationService: AppActivationServicing {
    var frontmostPIDValue: pid_t?
    var openedApplicationURLs: [URL] = []

    private let apps: [pid_t: FocusFakeRunningApplication]

    init(apps: [pid_t: FocusFakeRunningApplication]) {
        self.apps = apps
    }

    var frontmostPID: pid_t? {
        frontmostPIDValue
    }

    func runningApplication(processIdentifier: pid_t) -> RunningApplicationControlling? {
        apps[processIdentifier]
    }

    func openApplication(at bundleURL: URL) {
        openedApplicationURLs.append(bundleURL)
    }
}

@MainActor
private final class FocusFakeWindowElement: FocusWindowElement {
    var isMinimized: Bool?
    var setMinimizedCalls: [Bool] = []
    var setMainCalls = 0
    var raiseCalls = 0

    init(isMinimized: Bool? = false) {
        self.isMinimized = isMinimized
    }

    func setMinimized(_ minimized: Bool) {
        setMinimizedCalls.append(minimized)
        isMinimized = minimized
    }

    func setMain() {
        setMainCalls += 1
    }

    func raise() {
        raiseCalls += 1
    }
}

@MainActor
private final class FocusFakeWindowResolver: FocusWindowResolving {
    var requests: [(windowId: UInt32, pid: pid_t)] = []
    private let windows: [UInt32: FocusFakeWindowElement]

    init(windows: [UInt32: FocusFakeWindowElement] = [:]) {
        self.windows = windows
    }

    func windowElement(windowId: UInt32, pid: pid_t) -> FocusWindowElement? {
        requests.append((windowId: windowId, pid: pid))
        return windows[windowId]
    }
}
