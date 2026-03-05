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
                isInputMonitoringGranted: { false },
                isScreenRecordingGranted: { false },
                requestAccessibility: { false },
                requestInputMonitoring: { false },
                requestScreenRecording: { false }
            ),
            defaults: defaults
        )

        XCTAssertEqual(service.status(for: .accessibility), .notDetermined)
        XCTAssertEqual(service.status(for: .inputMonitoring), .notDetermined)
        XCTAssertEqual(service.status(for: .screenRecording), .notDetermined)
    }

    func testRequestTransitionsDeniedToGranted() {
        let suite = "PermissionServiceCoreTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)

        var granted = false
        let service = PermissionService(
            evaluator: PermissionStatusEvaluator(
                isAccessibilityGranted: { granted },
                isInputMonitoringGranted: { granted },
                isScreenRecordingGranted: { granted },
                requestAccessibility: { granted = true; return true },
                requestInputMonitoring: { granted = true; return true },
                requestScreenRecording: { granted = true; return true }
            ),
            defaults: defaults
        )

        XCTAssertEqual(service.request(.inputMonitoring), .granted)
        XCTAssertEqual(service.status(for: .inputMonitoring), .granted)
        XCTAssertEqual(service.request(.screenRecording), .granted)
        XCTAssertEqual(service.status(for: .screenRecording), .granted)
    }
}
