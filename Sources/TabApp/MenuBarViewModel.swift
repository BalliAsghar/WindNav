import AppKit
import Foundation
import TabCore

@MainActor
protocol MenuBarRuntimeProviding: AnyObject {
    func permissionStatus(for permission: PermissionKind) -> PermissionStatus
    func requestPermission(_ permission: PermissionKind) -> PermissionRequestResult
    func openSystemSettings(for permission: PermissionKind)
    func applyConfig(_ updated: TabConfig) throws
}

extension TabRuntime: MenuBarRuntimeProviding {}

@MainActor
protocol MenuBarSettingsStoreProviding: AnyObject {
    func loadOrCreate() throws -> TabConfig
    func save(_ config: TabConfig) throws
}

extension FileSettingsStateStore: MenuBarSettingsStoreProviding {}

protocol LaunchAtLoginManaging {
    var isEnabled: Bool { get }
    var statusDescription: String { get }
    func setEnabled(_ enabled: Bool) throws
}

extension LaunchAtLoginManager: LaunchAtLoginManaging {}

@MainActor
protocol MenuBarAlertPresenting: AnyObject {
    func presentOnboarding(appIcon: NSImage?)
    func presentPrePermissionPrompt(featureTitle: String, missingPermissions: [PermissionKind]) -> Bool
    func presentPermissionDeniedAlert(_ permission: PermissionKind) -> Bool
    func presentErrorAlert(title: String, message: String)
    func presentLaunchAtLoginError(message: String)
}

@MainActor
final class AppKitMenuBarAlertPresenter: MenuBarAlertPresenting {
    func presentOnboarding(appIcon: NSImage?) {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.icon =
            appIcon
            ?? NSImage(
                systemSymbolName: "hand.wave.fill",
                accessibilityDescription: "Welcome to WindNav"
            )
        alert.messageText = "Welcome to WindNav"
        alert.informativeText =
            "WindNav is controlled from the menu bar. Permissions are requested on demand when you enable related features."
        alert.addButton(withTitle: "Continue")
        alert.runModal()
    }

    func presentPrePermissionPrompt(featureTitle: String, missingPermissions: [PermissionKind]) -> Bool {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "Enable \(featureTitle)?"
        let names = missingPermissions.map(menuBarPermissionTitle).joined(separator: ", ")
        alert.informativeText =
            "WindNav needs \(names) to enable this feature. Continue to show the macOS permission prompt."
        alert.addButton(withTitle: "Continue")
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn
    }

    func presentPermissionDeniedAlert(_ permission: PermissionKind) -> Bool {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "\(menuBarPermissionTitle(permission)) Permission Required"
        alert.informativeText =
            "WindNav could not enable this feature because \(menuBarPermissionTitle(permission)) was denied. Open System Settings to grant access."
        alert.addButton(withTitle: "Open Settings")
        alert.addButton(withTitle: "Not Now")
        return alert.runModal() == .alertFirstButtonReturn
    }

    func presentErrorAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    func presentLaunchAtLoginError(message: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Unable to Update Launch at Login"
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}

@MainActor
func menuBarPermissionTitle(_ permission: PermissionKind) -> String {
    switch permission {
        case .accessibility:
            "Accessibility"
        case .screenRecording:
            "Screen Recording"
    }
}

@MainActor
final class MenuBarViewModel: ObservableObject {
    enum FeatureToggle: CaseIterable {
        case directionalNavigation

        var rowTitle: String {
            switch self {
            case .directionalNavigation:
                "Directional Navigation"
            }
        }

        var promptTitle: String {
            switch self {
            case .directionalNavigation:
                "directional navigation"
            }
        }
    }

    @Published private(set) var config: TabConfig
    @Published private(set) var permissionStatuses: [PermissionKind: PermissionStatus] = [:]
    @Published private(set) var summaryText = "Status: Ready"

    private let runtime: MenuBarRuntimeProviding
    private let settingsStore: MenuBarSettingsStoreProviding
    private let launchAtLoginManager: any LaunchAtLoginManaging
    private let alertPresenter: MenuBarAlertPresenting

    init(
        runtime: MenuBarRuntimeProviding,
        settingsStore: MenuBarSettingsStoreProviding,
        alertPresenter: MenuBarAlertPresenting,
        launchAtLoginManager: any LaunchAtLoginManaging = LaunchAtLoginManager()
    ) throws {
        self.runtime = runtime
        self.settingsStore = settingsStore
        self.launchAtLoginManager = launchAtLoginManager
        self.alertPresenter = alertPresenter
        self.config = try settingsStore.loadOrCreate()
        refreshPermissionStatuses()
        refreshSummaryText()
    }

    func presentOnboardingIfNeeded(appIcon: NSImage?) {
        guard !config.onboarding.permissionExplainerShown else { return }

        alertPresenter.presentOnboarding(appIcon: appIcon)
        config.onboarding.permissionExplainerShown = true
        do {
            try settingsStore.save(config)
        } catch {
            Logger.error(
                .config, "Failed to persist onboarding state: \(error.localizedDescription)")
        }
    }

    func refreshFromDiskIfPossible() {
        do {
            config = try settingsStore.loadOrCreate()
        } catch {
            Logger.error(
                .config, "Failed to reload config for menu state: \(error.localizedDescription)")
        }
        refreshPermissionStatuses()
        refreshSummaryText()
    }

    func statusLabel(for permission: PermissionKind) -> String {
        switch permissionStatus(for: permission) {
        case .granted:
            "Granted"
        case .notDetermined, .denied:
            "Not Granted"
        }
    }

    func permissionStatus(for permission: PermissionKind) -> PermissionStatus {
        permissionStatuses[permission] ?? .notDetermined
    }

    func isFeatureEnabled(_ feature: FeatureToggle) -> Bool {
        switch feature {
        case .directionalNavigation:
            config.directional.enabled
        }
    }

    func setFeature(_ feature: FeatureToggle, enabled: Bool) {
        guard isFeatureEnabled(feature) != enabled else { return }

        if enabled {
            let missingPermissions = permissionsRequired(for: feature).filter {
                permissionStatus(for: $0) != .granted
            }
            if !missingPermissions.isEmpty {
                let confirmed = alertPresenter.presentPrePermissionPrompt(
                    featureTitle: feature.promptTitle, missingPermissions: missingPermissions)
                guard confirmed else {
                    refreshPermissionStatuses()
                    refreshSummaryText()
                    return
                }

                for permission in missingPermissions {
                    let requestResult = runtime.requestPermission(permission)
                    if requestResult == .denied {
                        let shouldOpenSettings = alertPresenter.presentPermissionDeniedAlert(permission)
                        if shouldOpenSettings {
                            runtime.openSystemSettings(for: permission)
                        }
                        refreshPermissionStatuses()
                        refreshSummaryText()
                        return
                    }
                    refreshPermissionStatuses()
                }
            }
        }

        updateFeature(feature, enabled: enabled)
        persistAndApplyCurrentConfig()
        refreshPermissionStatuses()
        refreshSummaryText()
    }

    func handlePermissionRowClick(_ permission: PermissionKind) {
        let result = runtime.requestPermission(permission)
        if result == .denied {
            runtime.openSystemSettings(for: permission)
            refreshPermissionStatuses()
            refreshSummaryText()
            return
        }

        do {
            try runtime.applyConfig(config)
        } catch {
            alertPresenter.presentErrorAlert(
                title: "Unable to Apply Configuration",
                message: error.localizedDescription
            )
        }

        refreshPermissionStatuses()
        refreshSummaryText()
    }

    func isLaunchAtLoginEnabled() -> Bool {
        config.onboarding.launchAtLoginEnabled
    }

    func setLaunchAtLoginEnabled(_ enabled: Bool) {
        guard config.onboarding.launchAtLoginEnabled != enabled else { return }

        let previous = config.onboarding.launchAtLoginEnabled
        config.onboarding.launchAtLoginEnabled = enabled

        do {
            try launchAtLoginManager.setEnabled(enabled)
            let actual = launchAtLoginManager.isEnabled
            config.onboarding.launchAtLoginEnabled = actual
            if !persistConfigOnly() {
                config.onboarding.launchAtLoginEnabled = previous
                return
            }
            if actual != enabled {
                alertPresenter.presentLaunchAtLoginError(
                    message:
                        "macOS reported launch-at-login as \(actual ? "enabled" : "disabled") after requesting \(enabled ? "enabled" : "disabled"). Status: \(launchAtLoginManager.statusDescription)."
                )
            }
        } catch {
            let actual = launchAtLoginManager.isEnabled
            config.onboarding.launchAtLoginEnabled = actual
            _ = persistConfigOnly()
            alertPresenter.presentLaunchAtLoginError(
                message:
                    "\(error.localizedDescription)\nCurrent status: \(launchAtLoginManager.statusDescription)."
            )
        }
    }

    func reconcileLaunchAtLoginStateOnStartup() {
        let saved = config.onboarding.launchAtLoginEnabled
        let actual = launchAtLoginManager.isEnabled

        guard saved != actual else { return }

        if saved && !actual {
            do {
                try launchAtLoginManager.setEnabled(true)
            } catch {
                Logger.error(
                    .runtime,
                    "launch-at-login reconcile enable failed: \(error.localizedDescription)"
                )
            }
        } else if !saved && actual {
            do {
                try launchAtLoginManager.setEnabled(false)
            } catch {
                Logger.error(
                    .runtime,
                    "launch-at-login reconcile disable failed: \(error.localizedDescription)"
                )
            }
        }

        let postReconcileActual = launchAtLoginManager.isEnabled
        if config.onboarding.launchAtLoginEnabled != postReconcileActual {
            config.onboarding.launchAtLoginEnabled = postReconcileActual
            _ = persistConfigOnly()
        }
    }

    private func updateFeature(_ feature: FeatureToggle, enabled: Bool) {
        switch feature {
        case .directionalNavigation:
            config.directional.enabled = enabled
        }
    }

    private func permissionsRequired(for feature: FeatureToggle) -> [PermissionKind] {
        switch feature {
        case .directionalNavigation:
            [.accessibility]
        }
    }

    private func permissionsRequiredForEnabledFeatures() -> [PermissionKind] {
        [.accessibility]
    }

    private func refreshPermissionStatuses() {
        permissionStatuses = Dictionary(
            uniqueKeysWithValues: PermissionKind.allCases.map {
                ($0, runtime.permissionStatus(for: $0))
            }
        )
    }

    private func refreshSummaryText() {
        let needed = permissionsRequiredForEnabledFeatures().contains {
            permissionStatus(for: $0) != .granted
        }
        summaryText = needed ? "Status: Permissions Needed" : "Status: Ready"
    }

    private func persistAndApplyCurrentConfig() {
        do {
            try settingsStore.save(config)
            try runtime.applyConfig(config)
        } catch {
            Logger.error(
                .runtime, "Failed to apply menu settings update: \(error.localizedDescription)")
            alertPresenter.presentErrorAlert(
                title: "Unable to Save Settings",
                message: error.localizedDescription
            )
            refreshFromDiskIfPossible()
        }
    }

    private func persistConfigOnly() -> Bool {
        do {
            try settingsStore.save(config)
            return true
        } catch {
            Logger.error(.config, "Failed to save config: \(error.localizedDescription)")
            alertPresenter.presentErrorAlert(
                title: "Unable to Save Settings",
                message: error.localizedDescription
            )
            refreshFromDiskIfPossible()
            return false
        }
    }
}
