@testable import WindNavCore
import Carbon
import XCTest

@MainActor
final class NativeCommandTabOverrideTests: XCTestCase {
    func testCommandTabTriggerDisablesNativeHotkeys() {
        let controller = FakeSymbolicHotKeyController(
            states: [
                1: true,
                2: true,
            ]
        )
        let override = NativeCommandTabOverride(controller: controller)

        override.apply(for: ParsedHotkey(keyCode: UInt32(kVK_Tab), modifiers: UInt32(cmdKey)))

        XCTAssertEqual(controller.state(for: 1), false)
        XCTAssertEqual(controller.state(for: 2), false)
    }

    func testNonCommandTriggerDoesNotDisableNativeHotkeys() {
        let controller = FakeSymbolicHotKeyController(
            states: [
                1: true,
                2: true,
            ]
        )
        let override = NativeCommandTabOverride(controller: controller)

        override.apply(for: ParsedHotkey(keyCode: UInt32(kVK_Tab), modifiers: UInt32(optionKey)))

        XCTAssertEqual(controller.setCalls.count, 0)
        XCTAssertEqual(controller.state(for: 1), true)
        XCTAssertEqual(controller.state(for: 2), true)
    }

    func testRestoreBringsBackOriginalState() {
        let controller = FakeSymbolicHotKeyController(
            states: [
                1: true,
                2: false,
            ]
        )
        let override = NativeCommandTabOverride(controller: controller)

        override.apply(for: ParsedHotkey(keyCode: UInt32(kVK_Tab), modifiers: UInt32(cmdKey)))
        override.restore()

        XCTAssertEqual(controller.state(for: 1), true)
        XCTAssertEqual(controller.state(for: 2), false)
    }

    func testSwitchingAwayFromCommandTriggerRestores() {
        let controller = FakeSymbolicHotKeyController(
            states: [
                1: true,
                2: true,
            ]
        )
        let override = NativeCommandTabOverride(controller: controller)

        override.apply(for: ParsedHotkey(keyCode: UInt32(kVK_Tab), modifiers: UInt32(cmdKey)))
        override.apply(for: ParsedHotkey(keyCode: UInt32(kVK_Tab), modifiers: UInt32(optionKey)))

        XCTAssertEqual(controller.state(for: 1), true)
        XCTAssertEqual(controller.state(for: 2), true)
    }
}

private final class FakeSymbolicHotKeyController: SymbolicHotKeyControlling {
    private var states: [Int32: Bool]
    private let failRead: Bool
    private let failWrite: Bool
    private(set) var setCalls: [(Int32, Bool)] = []

    init(states: [Int32: Bool], failRead: Bool = false, failWrite: Bool = false) {
        self.states = states
        self.failRead = failRead
        self.failWrite = failWrite
    }

    func isSymbolicHotKeyEnabled(_ hotKeyID: Int32) -> Bool? {
        if failRead {
            return nil
        }
        return states[hotKeyID]
    }

    func setSymbolicHotKeyEnabled(_ hotKeyID: Int32, enabled: Bool) -> Bool {
        if failWrite {
            return false
        }
        states[hotKeyID] = enabled
        setCalls.append((hotKeyID, enabled))
        return true
    }

    func state(for id: Int32) -> Bool? {
        states[id]
    }
}
