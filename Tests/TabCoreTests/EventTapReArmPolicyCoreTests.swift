@testable import TabCore
import XCTest

@MainActor
final class EventTapReArmPolicyCoreTests: XCTestCase {

    // MARK: - Basic Decisions

    func testFirstReArmReturnsReArm() {
        let policy = EventTapReArmPolicy()
        // Advance past the cooldown
        policy.lastReArmTime = DispatchTime.now() - .seconds(1)
        XCTAssertEqual(policy.shouldReArm(), .reArm)
    }

    func testReArmWithinCooldownReturnsThrottled() {
        let policy = EventTapReArmPolicy()
        policy.reArmCooldown = 10 // 10 seconds — we're well within it
        // lastReArmTime is .now() by default, so any call is within cooldown
        XCTAssertEqual(policy.shouldReArm(), .throttled)
    }

    func testReArmAfterCooldownReturnsReArm() {
        let policy = EventTapReArmPolicy()
        policy.reArmCooldown = 0.1
        policy.lastReArmTime = DispatchTime.now() - .milliseconds(200)
        XCTAssertEqual(policy.shouldReArm(), .reArm)
    }

    // MARK: - Recreate Threshold

    func testReachingMaxDisablesReturnsRecreate() {
        let policy = EventTapReArmPolicy()
        policy.maxDisablesBeforeRecreate = 3
        policy.disableCount = 3
        XCTAssertEqual(policy.shouldReArm(), .recreate)
    }

    func testRecreateResetsDisableCount() {
        let policy = EventTapReArmPolicy()
        policy.maxDisablesBeforeRecreate = 2
        policy.disableCount = 2
        let decision = policy.shouldReArm()
        XCTAssertEqual(decision, .recreate)
        XCTAssertEqual(policy.disableCount, 0)
    }

    func testReArmIncrementsDisableCount() {
        let policy = EventTapReArmPolicy()
        policy.lastReArmTime = DispatchTime.now() - .seconds(1)
        XCTAssertEqual(policy.disableCount, 0)
        _ = policy.shouldReArm()
        XCTAssertEqual(policy.disableCount, 1)
    }

    // MARK: - Reset

    func testResetClearsState() {
        let policy = EventTapReArmPolicy()
        policy.disableCount = 10
        policy.lastReArmTime = DispatchTime.now() - .seconds(60)

        policy.reset()

        XCTAssertEqual(policy.disableCount, 0)
        // After reset, lastReArmTime is .now(), so within default cooldown → throttled
        XCTAssertEqual(policy.shouldReArm(), .throttled)
    }

    // MARK: - Rapid Fire Simulation

    func testRapidDisablesEventuallyRecreate() {
        let policy = EventTapReArmPolicy()
        policy.maxDisablesBeforeRecreate = 3
        policy.reArmCooldown = 0 // no cooldown so all calls go through as .reArm

        // Simulate rapid disables
        let d1 = policy.shouldReArm()
        XCTAssertEqual(d1, .reArm)

        let d2 = policy.shouldReArm()
        XCTAssertEqual(d2, .reArm)

        let d3 = policy.shouldReArm()
        XCTAssertEqual(d3, .reArm)

        // Now at count 3 → should recreate
        let d4 = policy.shouldReArm()
        XCTAssertEqual(d4, .recreate)

        // After recreate, count is reset → next call should reArm again
        let d5 = policy.shouldReArm()
        XCTAssertEqual(d5, .reArm)
    }

    // MARK: - Throttle Then ReArm After Cooldown

    func testThrottleThenReArmAfterCooldown() {
        let policy = EventTapReArmPolicy()
        policy.reArmCooldown = 0.01 // 10ms

        // First call within cooldown → throttled (lastReArmTime is .now())
        XCTAssertEqual(policy.shouldReArm(), .throttled)

        // Wait past cooldown
        Thread.sleep(forTimeInterval: 0.02)

        // Now should succeed
        XCTAssertEqual(policy.shouldReArm(), .reArm)
    }
}

// MARK: - Equatable conformance for test assertions

extension ReArmDecision: @retroactive Equatable {
    public static func == (lhs: ReArmDecision, rhs: ReArmDecision) -> Bool {
        switch (lhs, rhs) {
        case (.reArm, .reArm), (.throttled, .throttled), (.recreate, .recreate):
            return true
        default:
            return false
        }
    }
}

