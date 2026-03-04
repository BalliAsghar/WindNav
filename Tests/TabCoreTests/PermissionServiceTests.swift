@testable import TabCore
import Foundation
import XCTest

@MainActor
final class PermissionServiceTests: XCTestCase {
    func testStatusIsNotDeterminedBeforeAnyRequestWhenDenied() {
        let suite = "PermissionServiceTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let service = PermissionService(
            evaluator: PermissionStatusEvaluator(
                isAccessibilityGranted: { false },
                isInputMonitoringGranted: { false },
                requestAccessibility: { false },
                requestInputMonitoring: { false }
            ),
            defaults: defaults
        )

        XCTAssertEqual(service.status(for: .accessibility), .notDetermined)
        XCTAssertEqual(service.status(for: .inputMonitoring), .notDetermined)
    }

    func testRequestDeniedMarksStatusAsDenied() {
        let suite = "PermissionServiceTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let service = PermissionService(
            evaluator: PermissionStatusEvaluator(
                isAccessibilityGranted: { false },
                isInputMonitoringGranted: { false },
                requestAccessibility: { false },
                requestInputMonitoring: { false }
            ),
            defaults: defaults
        )

        let result = service.request(.accessibility)

        XCTAssertEqual(result, .denied)
        XCTAssertEqual(service.status(for: .accessibility), .denied)
    }

    func testRequestGrantedReturnsGrantedStatus() {
        let suite = "PermissionServiceTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)

        var granted = false
        let service = PermissionService(
            evaluator: PermissionStatusEvaluator(
                isAccessibilityGranted: { granted },
                isInputMonitoringGranted: { granted },
                requestAccessibility: {
                    granted = true
                    return true
                },
                requestInputMonitoring: {
                    granted = true
                    return true
                }
            ),
            defaults: defaults
        )

        let result = service.request(.inputMonitoring)

        XCTAssertEqual(result, .granted)
        XCTAssertEqual(service.status(for: .inputMonitoring), .granted)
    }
}
