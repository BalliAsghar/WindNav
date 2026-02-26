import Foundation
import ServiceManagement

protocol LaunchAtLoginManaging {
    var isEnabled: Bool { get }
    var statusDescription: String { get }

    func setEnabled(_ enabled: Bool) throws
}

public struct LaunchAtLoginManager: LaunchAtLoginManaging {
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
        let before = statusDescription
        Logger.info(.startup, "Set launch-on-login requested=\(enabled ? "true" : "false") status-before=\(before)")

        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            let after = statusDescription
            Logger.error(
                .startup,
                "Launch-on-login change failed requested=\(enabled ? "true" : "false") status-before=\(before) status-after=\(after) error=\(error.localizedDescription)"
            )
            throw error
        }

        let after = statusDescription
        Logger.info(.startup, "Launch-on-login set requested=\(enabled ? "true" : "false") status-after=\(after)")
    }
}
