@testable import TabCore
import XCTest

final class KeyboardListenPermissionTests: XCTestCase {
    func testEnsureAccessReturnsTrueWhenPreflightAlreadyGranted() {
        var requestCalls = 0
        let evaluator = KeyboardListenAccessEvaluator(
            preflight: { true },
            request: {
                requestCalls += 1
                return true
            }
        )

        XCTAssertTrue(evaluator.ensureAccess(prompt: true))
        XCTAssertEqual(requestCalls, 0)
    }

    func testEnsureAccessReturnsFalseWhenPreflightDeniedAndPromptDisabled() {
        var requestCalls = 0
        let evaluator = KeyboardListenAccessEvaluator(
            preflight: { false },
            request: {
                requestCalls += 1
                return true
            }
        )

        XCTAssertFalse(evaluator.ensureAccess(prompt: false))
        XCTAssertEqual(requestCalls, 0)
    }

    func testEnsureAccessReturnsTrueWhenPromptEnabledAndRequestGrantsAccess() {
        var granted = false
        let evaluator = KeyboardListenAccessEvaluator(
            preflight: { granted },
            request: {
                granted = true
                return true
            }
        )

        XCTAssertTrue(evaluator.ensureAccess(prompt: true))
    }

    func testEnsureAccessReturnsFalseWhenPromptEnabledButRequestDoesNotGrantAccess() {
        var requestCalls = 0
        let evaluator = KeyboardListenAccessEvaluator(
            preflight: { false },
            request: {
                requestCalls += 1
                return false
            }
        )

        XCTAssertFalse(evaluator.ensureAccess(prompt: true))
        XCTAssertEqual(requestCalls, 1)
    }
}
