@testable import TabCore
import CoreGraphics
import Foundation
import XCTest

final class SystemHotkeyOverrideCoreTests: XCTestCase {
    override func tearDown() {
        SystemHotkeyOverride._resetDriverForTests()
        super.tearDown()
    }

    func testDisableAndRestoreAreIdempotent() {
        let recorder = DriverCallRecorder()
        SystemHotkeyOverride._setDriverForTests { hotkey, enabled in
            recorder.append((hotkey, enabled))
            return .success
        }

        SystemHotkeyOverride.disableSystemCmdTab()
        SystemHotkeyOverride.disableSystemCmdTab()
        SystemHotkeyOverride.restoreSystemCmdTab()
        SystemHotkeyOverride.restoreSystemCmdTab()

        let calls = recorder.calls
        XCTAssertEqual(calls.count, 4)
        XCTAssertFalse(calls[0].1)
        XCTAssertFalse(calls[1].1)
        XCTAssertTrue(calls[2].1)
        XCTAssertTrue(calls[3].1)
    }
}

private final class DriverCallRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [(CGSSymbolicHotKey.RawValue, Bool)] = []

    var calls: [(CGSSymbolicHotKey.RawValue, Bool)] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func append(_ call: (CGSSymbolicHotKey.RawValue, Bool)) {
        lock.lock()
        storage.append(call)
        lock.unlock()
    }
}
