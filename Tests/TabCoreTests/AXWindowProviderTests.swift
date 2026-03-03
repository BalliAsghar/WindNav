@testable import TabCore
import ApplicationServices
import CoreGraphics
import XCTest

final class AXWindowProviderTests: XCTestCase {
    func testCGPresenceDetectsPIDWithRealWindow() {
        let info = [
            makeCGWindowInfo(
                ownerPID: 4242,
                layer: 0,
                alpha: 1,
                bounds: CGRect(x: 0, y: 0, width: 1920, height: 1080)
            )
        ]

        let result = CGWindowPresence.likelyWindowOwnerPIDs(from: info)

        XCTAssertEqual(result, [4242])
    }

    func testCGPresenceIgnoresNonNormalLayers() {
        let info = [
            makeCGWindowInfo(
                ownerPID: 4242,
                layer: 25,
                alpha: 1,
                bounds: CGRect(x: 0, y: 0, width: 1920, height: 1080)
            )
        ]

        let result = CGWindowPresence.likelyWindowOwnerPIDs(from: info)

        XCTAssertTrue(result.isEmpty)
    }

    func testAXMissWithCGPresenceReturnsActivationFallbackNonWindowless() {
        let result = AXWindowFallbackClassifier.fallbackKind(
            bundleId: "org.example.player",
            showEmptyApps: .showAtEnd,
            cgHasLikelyWindow: true
        )

        XCTAssertEqual(result, .activationFallback)
    }

    func testAXMissWithoutCGPresenceReturnsWindowlessWhenPolicyShow() {
        let result = AXWindowFallbackClassifier.fallbackKind(
            bundleId: "org.example.player",
            showEmptyApps: .show,
            cgHasLikelyWindow: false
        )

        XCTAssertEqual(result, .confirmedWindowless)
    }

    func testAXMissWithoutCGPresenceReturnsNoneWhenPolicyHide() {
        let result = AXWindowFallbackClassifier.fallbackKind(
            bundleId: "org.example.player",
            showEmptyApps: .hide,
            cgHasLikelyWindow: false
        )

        XCTAssertEqual(result, .none)
    }

    func testFinderConfirmedWindowlessIsSuppressed() {
        let result = AXWindowFallbackClassifier.fallbackKind(
            bundleId: "com.apple.finder",
            showEmptyApps: .show,
            cgHasLikelyWindow: false
        )

        XCTAssertEqual(result, .none)
    }

    func testFinderAXMissWithCGPresenceIsSuppressed() {
        let result = AXWindowFallbackClassifier.fallbackKind(
            bundleId: "com.apple.finder",
            showEmptyApps: .hide,
            cgHasLikelyWindow: true
        )

        XCTAssertEqual(result, .none)
    }

    func testFullscreenNonstandardSubroleIsAccepted() {
        XCTAssertTrue(AXWindowEligibility.acceptsSubrole("AXUnknown", isFullscreen: true))
        XCTAssertFalse(AXWindowEligibility.acceptsSubrole("AXUnknown", isFullscreen: false))
        XCTAssertTrue(AXWindowEligibility.acceptsSubrole(kAXStandardWindowSubrole as String, isFullscreen: false))
    }

    private func makeCGWindowInfo(
        ownerPID: pid_t,
        layer: Int,
        alpha: Double,
        bounds: CGRect
    ) -> [String: Any] {
        [
            kCGWindowOwnerPID as String: NSNumber(value: ownerPID),
            kCGWindowLayer as String: NSNumber(value: layer),
            kCGWindowAlpha as String: NSNumber(value: alpha),
            kCGWindowBounds as String: [
                "X": bounds.origin.x,
                "Y": bounds.origin.y,
                "Width": bounds.size.width,
                "Height": bounds.size.height,
            ],
        ]
    }
}
