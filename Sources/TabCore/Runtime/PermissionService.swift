import AppKit
import Foundation

public enum PermissionKind: String, CaseIterable, Sendable {
    case accessibility
}

public enum PermissionStatus: Sendable, Equatable {
    case notDetermined
    case denied
    case granted
}

public enum PermissionRequestResult: Sendable, Equatable {
    case granted
    case denied
}

struct PermissionStatusEvaluator {
    let isAccessibilityGranted: () -> Bool
    let requestAccessibility: () -> Bool

    @MainActor
    static let live = PermissionStatusEvaluator(
        isAccessibilityGranted: { AXPermission.ensureTrusted(prompt: false) },
        requestAccessibility: { AXPermission.ensureTrusted(prompt: true) }
    )
}

@MainActor
public final class PermissionService {
    private let evaluator: PermissionStatusEvaluator
    private let defaults: UserDefaults

    public init() {
        self.evaluator = .live
        self.defaults = .standard
    }

    init(
        evaluator: PermissionStatusEvaluator,
        defaults: UserDefaults
    ) {
        self.evaluator = evaluator
        self.defaults = defaults
    }

    public func status(for permission: PermissionKind) -> PermissionStatus {
        if isGranted(permission) {
            return .granted
        }
        if hasRequested(permission) {
            return .denied
        }
        return .notDetermined
    }

    public func request(_ permission: PermissionKind) -> PermissionRequestResult {
        markRequested(permission)
        let granted = evaluator.requestAccessibility()
        return granted ? .granted : .denied
    }

    public func openSystemSettings(for permission: PermissionKind) {
        guard let url = URL(string: settingsURLString(for: permission)) else { return }
        NSWorkspace.shared.open(url)
    }

    private func isGranted(_ permission: PermissionKind) -> Bool {
        evaluator.isAccessibilityGranted()
    }

    private func hasRequested(_ permission: PermissionKind) -> Bool {
        defaults.bool(forKey: requestedDefaultsKey(for: permission))
    }

    private func markRequested(_ permission: PermissionKind) {
        defaults.set(true, forKey: requestedDefaultsKey(for: permission))
    }

    private func requestedDefaultsKey(for permission: PermissionKind) -> String {
        "windnav.permission.requested.\(permission.rawValue)"
    }

    private func settingsURLString(for permission: PermissionKind) -> String {
        "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
    }
}
