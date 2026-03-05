import Foundation
import ServiceManagement

public struct LaunchAtLoginManager {
    public init() {}

    public var status: SMAppService.Status {
        SMAppService.mainApp.status
    }

    public var isEnabled: Bool {
        status == .enabled
    }

    public var statusDescription: String {
        switch status {
        case .enabled:
            "enabled"
        case .notRegistered:
            "notRegistered"
        case .notFound:
            "notFound"
        case .requiresApproval:
            "requiresApproval"
        @unknown default:
            "unknown(\(status.rawValue))"
        }
    }

    public func setEnabled(_ enabled: Bool) throws {
        Logger.info(
            .runtime,
            "launch-at-login requested=\(enabled) status-before=\(statusDescription)"
        )
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
        Logger.info(
            .runtime,
            "launch-at-login updated requested=\(enabled) status-after=\(statusDescription)"
        )
    }
}
