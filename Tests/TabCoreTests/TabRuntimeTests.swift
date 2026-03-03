@testable import TabCore
import AppKit
import Carbon
import XCTest

@MainActor
final class TabRuntimeTests: XCTestCase {
    func testRuntimeCanInitializeAndStop() {
        let runtime = TabRuntime(configURL: nil)
        runtime.stop()
    }

    func testRightArrowWithCmdAndActiveSessionRoutesRight() {
        let command = CycleKeyRouter.routeCommand(
            keyCode: UInt16(kVK_RightArrow),
            flags: [.command],
            cycleActive: true
        )

        XCTAssertEqual(command, .move(.right))
    }

    func testLeftArrowWithCmdAndActiveSessionRoutesLeft() {
        let command = CycleKeyRouter.routeCommand(
            keyCode: UInt16(kVK_LeftArrow),
            flags: [.command],
            cycleActive: true
        )

        XCTAssertEqual(command, .move(.left))
    }

    func testArrowWithoutActiveSessionIsIgnored() {
        let command = CycleKeyRouter.routeCommand(
            keyCode: UInt16(kVK_RightArrow),
            flags: [.command],
            cycleActive: false
        )

        XCTAssertNil(command)
    }

    func testArrowWithoutCmdIsIgnored() {
        let command = CycleKeyRouter.routeCommand(
            keyCode: UInt16(kVK_RightArrow),
            flags: [],
            cycleActive: true
        )

        XCTAssertNil(command)
    }

    func testNonArrowKeysAreIgnored() {
        let command = CycleKeyRouter.routeCommand(
            keyCode: UInt16(kVK_Tab),
            flags: [.command],
            cycleActive: true
        )

        XCTAssertNil(command)
    }

    func testCmdQWithActiveCycleRoutesQuitCommand() {
        let command = CycleKeyRouter.routeCommand(
            keyCode: UInt16(kVK_ANSI_Q),
            flags: [.command],
            cycleActive: true
        )

        XCTAssertEqual(command, .quitSelectedApp)
    }

    func testQWithoutCmdIsIgnored() {
        let command = CycleKeyRouter.routeCommand(
            keyCode: UInt16(kVK_ANSI_Q),
            flags: [],
            cycleActive: true
        )

        XCTAssertNil(command)
    }

    func testCmdQWithoutActiveCycleIsIgnored() {
        let command = CycleKeyRouter.routeCommand(
            keyCode: UInt16(kVK_ANSI_Q),
            flags: [.command],
            cycleActive: false
        )

        XCTAssertNil(command)
    }
}
