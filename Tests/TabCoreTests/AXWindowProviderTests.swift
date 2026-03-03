@testable import TabCore
import ApplicationServices
import CoreGraphics
import XCTest

final class AXWindowProviderTests: XCTestCase {
    func testCGEvidenceNoneWhenLayerNonzeroOrTiny() {
        let info = [
            makeCGWindowInfo(
                ownerPID: 1111,
                layer: 25,
                alpha: 1,
                isOnscreen: true,
                bounds: CGRect(x: 0, y: 0, width: 1920, height: 1080)
            ),
            makeCGWindowInfo(
                ownerPID: 2222,
                layer: 0,
                alpha: 1,
                isOnscreen: true,
                bounds: CGRect(x: 0, y: 0, width: 90, height: 40)
            ),
        ]

        let result = CGWindowPresence.windowEvidenceByPID(from: info)

        XCTAssertTrue(result.isEmpty)
    }

    func testCGEvidenceWeakForOffscreenMediumWindow() {
        let info = [
            makeCGWindowInfo(
                ownerPID: 4242,
                layer: 0,
                alpha: 1,
                isOnscreen: false,
                bounds: CGRect(x: 0, y: 0, width: 320, height: 240)
            )
        ]

        let result = CGWindowPresence.windowEvidenceByPID(from: info)

        XCTAssertEqual(result[4242], .weak)
    }

    func testCGEvidenceStrongForOnscreenNormalWindow() {
        let info = [
            makeCGWindowInfo(
                ownerPID: 4242,
                layer: 0,
                alpha: 1,
                isOnscreen: true,
                bounds: CGRect(x: 0, y: 0, width: 320, height: 240)
            )
        ]

        let result = CGWindowPresence.windowEvidenceByPID(from: info)

        XCTAssertEqual(result[4242], .strong)
    }

    func testCGEvidenceStrongForOffscreenLargeWindow() {
        let info = [
            makeCGWindowInfo(
                ownerPID: 4242,
                layer: 0,
                alpha: 1,
                isOnscreen: false,
                bounds: CGRect(x: 0, y: 0, width: 800, height: 500)
            )
        ]

        let result = CGWindowPresence.windowEvidenceByPID(from: info)

        XCTAssertEqual(result[4242], .strong)
    }

    func testFallbackStrongEvidenceReturnsActivationFallback() {
        let result = AXWindowFallbackClassifier.fallbackKind(
            bundleId: "org.example.player",
            showEmptyApps: .showAtEnd,
            cgEvidence: .strong
        )

        XCTAssertEqual(result, .activationFallback)
    }

    func testFallbackWeakEvidenceReturnsConfirmedWindowless() {
        let result = AXWindowFallbackClassifier.fallbackKind(
            bundleId: "org.example.player",
            showEmptyApps: .show,
            cgEvidence: .weak
        )

        XCTAssertEqual(result, .confirmedWindowless)
    }

    func testFallbackNoneEvidenceReturnsConfirmedWindowlessWhenShowEnabled() {
        let result = AXWindowFallbackClassifier.fallbackKind(
            bundleId: "org.example.player",
            showEmptyApps: .showAtEnd,
            cgEvidence: .none
        )

        XCTAssertEqual(result, .confirmedWindowless)
    }

    func testFallbackShowEmptyHideReturnsNone() {
        let result = AXWindowFallbackClassifier.fallbackKind(
            bundleId: "org.example.player",
            showEmptyApps: .hide,
            cgEvidence: .none
        )

        XCTAssertEqual(result, .none)
    }

    func testFinderIsSuppressedForAllEvidenceLevels() {
        let values: [CGWindowEvidence] = [.none, .weak, .strong]
        for evidence in values {
            let result = AXWindowFallbackClassifier.fallbackKind(
                bundleId: "com.apple.finder",
                showEmptyApps: .show,
                cgEvidence: evidence
            )
            XCTAssertEqual(result, .none)
        }
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
        isOnscreen: Bool,
        bounds: CGRect
    ) -> [String: Any] {
        [
            kCGWindowOwnerPID as String: NSNumber(value: ownerPID),
            kCGWindowLayer as String: NSNumber(value: layer),
            kCGWindowAlpha as String: NSNumber(value: alpha),
            kCGWindowIsOnscreen as String: NSNumber(value: isOnscreen),
            kCGWindowBounds as String: [
                "X": bounds.origin.x,
                "Y": bounds.origin.y,
                "Width": bounds.size.width,
                "Height": bounds.size.height,
            ],
        ]
    }
}
