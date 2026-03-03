@testable import TabCore
import CoreGraphics
import XCTest

final class SystemHotkeyOverrideTests: XCTestCase {
    private final class CallsBox: @unchecked Sendable {
        private var calls: [(Int, Bool)] = []
        private let lock = NSLock()

        func append(_ value: (Int, Bool)) {
            lock.lock()
            calls.append(value)
            lock.unlock()
        }

        func snapshot() -> [(Int, Bool)] {
            lock.lock()
            defer { lock.unlock() }
            return calls
        }
    }

    override func tearDown() {
        super.tearDown()
        SystemHotkeyOverride._resetDriverForTests()
    }

    func testDisableIsIdempotent() {
        let calls = CallsBox()
        SystemHotkeyOverride._setDriverForTests { id, enabled in
            calls.append((id, enabled))
            return .success
        }

        SystemHotkeyOverride.disableSystemCmdTab()
        SystemHotkeyOverride.disableSystemCmdTab()

        let snapshot = calls.snapshot()
        XCTAssertEqual(snapshot.count, 2)
        XCTAssertEqual(snapshot[0].0, CGSSymbolicHotKey.commandTab.rawValue)
        XCTAssertEqual(snapshot[0].1, false)
        XCTAssertEqual(snapshot[1].0, CGSSymbolicHotKey.commandShiftTab.rawValue)
        XCTAssertEqual(snapshot[1].1, false)
        XCTAssertTrue(SystemHotkeyOverride._isDisabledForTests())
    }

    func testRestoreIsIdempotent() {
        let calls = CallsBox()
        SystemHotkeyOverride._setDriverForTests { id, enabled in
            calls.append((id, enabled))
            return .success
        }

        SystemHotkeyOverride.disableSystemCmdTab()
        SystemHotkeyOverride.restoreSystemCmdTab()
        SystemHotkeyOverride.restoreSystemCmdTab()

        let snapshot = calls.snapshot()
        XCTAssertEqual(snapshot.count, 4)
        XCTAssertEqual(snapshot[2].0, CGSSymbolicHotKey.commandTab.rawValue)
        XCTAssertEqual(snapshot[2].1, true)
        XCTAssertEqual(snapshot[3].0, CGSSymbolicHotKey.commandShiftTab.rawValue)
        XCTAssertEqual(snapshot[3].1, true)
        XCTAssertFalse(SystemHotkeyOverride._isDisabledForTests())
    }
}
