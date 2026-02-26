@testable import WindNavCore
import XCTest

@MainActor
final class LaunchAtLoginRuntimeTests: XCTestCase {
    func testApplyLaunchAtLoginSkipsWhenAlreadyEnabled() {
        let manager = FakeLaunchAtLoginManager(isEnabled: true, statusDescription: "enabled")
        let runtime = WindNavRuntime(configURL: nil, launchAtLoginManager: manager)

        runtime.applyLaunchAtLogin(true)

        XCTAssertEqual(manager.setEnabledCalls, [])
    }

    func testApplyLaunchAtLoginEnablesWhenDisabled() {
        let manager = FakeLaunchAtLoginManager(isEnabled: false, statusDescription: "notRegistered")
        let runtime = WindNavRuntime(configURL: nil, launchAtLoginManager: manager)

        runtime.applyLaunchAtLogin(true)

        XCTAssertEqual(manager.setEnabledCalls, [true])
        XCTAssertTrue(manager.isEnabled)
    }

    func testApplyLaunchAtLoginDisablesWhenEnabled() {
        let manager = FakeLaunchAtLoginManager(isEnabled: true, statusDescription: "enabled")
        let runtime = WindNavRuntime(configURL: nil, launchAtLoginManager: manager)

        runtime.applyLaunchAtLogin(false)

        XCTAssertEqual(manager.setEnabledCalls, [false])
        XCTAssertFalse(manager.isEnabled)
    }

    func testApplyLaunchAtLoginFailureDoesNotCrashRuntime() {
        let manager = FakeLaunchAtLoginManager(isEnabled: false, statusDescription: "notRegistered")
        manager.error = NSError(domain: "test", code: 1)
        let runtime = WindNavRuntime(configURL: nil, launchAtLoginManager: manager)

        runtime.applyLaunchAtLogin(true)

        XCTAssertEqual(manager.setEnabledCalls, [true])
        XCTAssertFalse(manager.isEnabled)
    }
}

private final class FakeLaunchAtLoginManager: LaunchAtLoginManaging {
    var isEnabled: Bool
    var statusDescription: String
    var error: Error?
    var setEnabledCalls: [Bool] = []

    init(isEnabled: Bool, statusDescription: String) {
        self.isEnabled = isEnabled
        self.statusDescription = statusDescription
    }

    func setEnabled(_ enabled: Bool) throws {
        setEnabledCalls.append(enabled)
        if let error {
            throw error
        }
        isEnabled = enabled
        statusDescription = enabled ? "enabled" : "notRegistered"
    }
}
