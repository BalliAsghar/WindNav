@testable import TabCore
import AppKit
import Carbon
import XCTest

@MainActor
final class RuntimeCoreTests: XCTestCase {
    func testCycleCommandRouting() {
        XCTAssertEqual(
            TabRuntime.cycleCommand(keyCode: UInt16(kVK_Tab), flags: [.command]),
            .move(.right)
        )
        XCTAssertEqual(
            TabRuntime.cycleCommand(keyCode: UInt16(kVK_Tab), flags: [.command, .shift]),
            .move(.left)
        )
        XCTAssertEqual(
            TabRuntime.cycleCommand(keyCode: UInt16(kVK_Escape), flags: []),
            .cancel
        )
        XCTAssertEqual(
            TabRuntime.cycleCommand(keyCode: UInt16(kVK_LeftArrow), flags: [.command]),
            .move(.left)
        )
        XCTAssertEqual(
            TabRuntime.cycleCommand(keyCode: UInt16(kVK_RightArrow), flags: [.command]),
            .move(.right)
        )
        XCTAssertEqual(
            TabRuntime.cycleCommand(keyCode: UInt16(kVK_ANSI_Q), flags: [.command]),
            .quitSelectedApp
        )
        XCTAssertEqual(
            TabRuntime.cycleCommand(keyCode: UInt16(kVK_ANSI_W), flags: [.command]),
            .closeSelectedWindow
        )
        XCTAssertNil(
            TabRuntime.cycleCommand(keyCode: UInt16(kVK_RightArrow), flags: [])
        )
        XCTAssertNil(
            TabRuntime.cycleCommand(keyCode: UInt16(kVK_Tab), flags: [])
        )
    }

    func testDirectionalMutationRouting() {
        XCTAssertEqual(
            TabRuntime.directionalMutationCommand(keyCode: UInt16(kVK_ANSI_Q), flags: [.command]),
            .quitSelectedApp
        )
        XCTAssertEqual(
            TabRuntime.directionalMutationCommand(keyCode: UInt16(kVK_ANSI_W), flags: [.command]),
            .closeSelectedWindow
        )
        XCTAssertNil(
            TabRuntime.directionalMutationCommand(keyCode: UInt16(kVK_ANSI_W), flags: [])
        )
        XCTAssertNil(
            TabRuntime.directionalMutationCommand(keyCode: UInt16(kVK_Escape), flags: [.command])
        )
    }

    func testRuntimeCanInitializeAndStop() {
        let runtime = TabRuntime(configURL: nil)
        runtime.stop()
    }

    func testAdvancedInputRequiresAccessibilityOnly() {
        XCTAssertTrue(TabRuntime.shouldEnableAdvancedInput(accessibilityGranted: true))
        XCTAssertFalse(TabRuntime.shouldEnableAdvancedInput(accessibilityGranted: false))
    }
}
