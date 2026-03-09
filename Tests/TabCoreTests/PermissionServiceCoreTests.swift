@testable import TabCore
import Foundation
import XCTest

@MainActor
final class PermissionServiceCoreTests: XCTestCase {
    func testStatusStartsNotDeterminedWhenDeniedAndNeverRequested() {
        let suite = "PermissionServiceCoreTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)

        let service = PermissionService(
            evaluator: PermissionStatusEvaluator(
                isAccessibilityGranted: { false },
                requestAccessibility: { false },
                isScreenRecordingGranted: { false },
                requestScreenRecording: { false }
            ),
            defaults: defaults
        )

        XCTAssertEqual(service.status(for: .accessibility), .notDetermined)
    }

    func testRequestTransitionsDeniedToGranted() {
        let suite = "PermissionServiceCoreTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)

        var granted = false
        let service = PermissionService(
            evaluator: PermissionStatusEvaluator(
                isAccessibilityGranted: { granted },
                requestAccessibility: { granted = true; return true },
                isScreenRecordingGranted: { false },
                requestScreenRecording: { false }
            ),
            defaults: defaults
        )

        XCTAssertEqual(service.request(.accessibility), .granted)
        XCTAssertEqual(service.status(for: .accessibility), .granted)
    }

    func testScreenRecordingPermissionTracksSeparateState() {
        let suite = "PermissionServiceCoreTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)

        var granted = false
        let service = PermissionService(
            evaluator: PermissionStatusEvaluator(
                isAccessibilityGranted: { false },
                requestAccessibility: { false },
                isScreenRecordingGranted: { granted },
                requestScreenRecording: { granted = true; return true }
            ),
            defaults: defaults
        )

        XCTAssertEqual(service.status(for: .screenRecording), .notDetermined)
        XCTAssertEqual(service.request(.screenRecording), .granted)
        XCTAssertEqual(service.status(for: .screenRecording), .granted)
    }
}
