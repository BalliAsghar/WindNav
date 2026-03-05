import AppKit
import Foundation
import TabCore

@MainActor
final class MenuBarSettingsController: NSObject, NSMenuDelegate {
    private enum FeatureToggle {
        case cmdTabOverride
        case directionalNavigation
        case thumbnails

        var title: String {
            switch self {
            case .cmdTabOverride:
                "Cmd+Tab override"
            case .directionalNavigation:
                "directional navigation"
            case .thumbnails:
                "window thumbnails"
            }
        }
    }

    private let runtime: TabRuntime
    private let settingsStore: FileSettingsStateStore
    private var config: TabConfig

    private let statusItem: NSStatusItem
    private let menu = NSMenu()

    private let titleItem = NSMenuItem(title: "WindNav", action: nil, keyEquivalent: "")
    private let summaryItem = NSMenuItem(title: "Status: Ready", action: nil, keyEquivalent: "")
    private let cmdTabToggleItem = NSMenuItem(
        title: "Enable Cmd+Tab override", action: nil, keyEquivalent: "")
    private let directionalToggleItem = NSMenuItem(
        title: "Enable directional navigation", action: nil, keyEquivalent: "")
    private let thumbnailToggleItem = NSMenuItem(
        title: "Show window thumbnails", action: nil, keyEquivalent: "")
    private let accessibilityPermissionItem = NSMenuItem(
        title: "Accessibility: Not Granted", action: nil, keyEquivalent: "")
    private let inputMonitoringPermissionItem = NSMenuItem(
        title: "Input Monitoring: Not Granted", action: nil, keyEquivalent: "")
    private let screenRecordingPermissionItem = NSMenuItem(
        title: "Screen Recording: Not Granted", action: nil, keyEquivalent: "")
    private let quitItem = NSMenuItem(title: "Quit WindNav", action: nil, keyEquivalent: "q")

    init(runtime: TabRuntime, settingsStore: FileSettingsStateStore) throws {
        self.runtime = runtime
        self.settingsStore = settingsStore
        self.config = try settingsStore.loadOrCreate()
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        configureStatusButton()
        buildMenu()
        refreshMenuState()
        presentOnboardingIfNeeded()
    }

    func menuWillOpen(_ menu: NSMenu) {
        refreshFromDiskIfPossible()
        refreshMenuState()
    }

    private func configureStatusButton() {
        if let button = statusItem.button {
            button.title = ""
            button.image = NSImage(
                systemSymbolName: "rectangle.stack.fill",
                accessibilityDescription: "WindNav"
            )
        }
    }

    private func buildMenu() {
        menu.delegate = self

        titleItem.isEnabled = false
        summaryItem.isEnabled = false

        cmdTabToggleItem.target = self
        cmdTabToggleItem.action = #selector(toggleCmdTabOverride)

        directionalToggleItem.target = self
        directionalToggleItem.action = #selector(toggleDirectionalNavigation)

        thumbnailToggleItem.target = self
        thumbnailToggleItem.action = #selector(toggleThumbnails)

        accessibilityPermissionItem.target = self
        accessibilityPermissionItem.action = #selector(handleAccessibilityPermissionRow)

        inputMonitoringPermissionItem.target = self
        inputMonitoringPermissionItem.action = #selector(handleInputMonitoringPermissionRow)

        screenRecordingPermissionItem.target = self
        screenRecordingPermissionItem.action = #selector(handleScreenRecordingPermissionRow)

        quitItem.target = self
        quitItem.action = #selector(quitApp)

        menu.addItem(titleItem)
        menu.addItem(summaryItem)
        menu.addItem(.separator())
        menu.addItem(cmdTabToggleItem)
        menu.addItem(directionalToggleItem)
        menu.addItem(thumbnailToggleItem)
        menu.addItem(.separator())
        menu.addItem(accessibilityPermissionItem)
        menu.addItem(inputMonitoringPermissionItem)
        menu.addItem(screenRecordingPermissionItem)
        menu.addItem(.separator())
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    @objc private func toggleCmdTabOverride() {
        handleToggle(.cmdTabOverride)
    }

    @objc private func toggleDirectionalNavigation() {
        handleToggle(.directionalNavigation)
    }

    @objc private func toggleThumbnails() {
        handleToggle(.thumbnails)
    }

    @objc private func handleAccessibilityPermissionRow() {
        handlePermissionRowClick(.accessibility)
    }

    @objc private func handleInputMonitoringPermissionRow() {
        handlePermissionRowClick(.inputMonitoring)
    }

    @objc private func handleScreenRecordingPermissionRow() {
        handlePermissionRowClick(.screenRecording)
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }

    private func refreshMenuState() {
        cmdTabToggleItem.state = config.activation.overrideSystemCmdTab ? .on : .off
        directionalToggleItem.state = config.directional.enabled ? .on : .off
        thumbnailToggleItem.state = config.appearance.showThumbnails ? .on : .off

        let accessibilityStatus = runtime.permissionStatus(for: .accessibility)
        let inputStatus = runtime.permissionStatus(for: .inputMonitoring)
        let screenStatus = runtime.permissionStatus(for: .screenRecording)

        accessibilityPermissionItem.title = "Accessibility: \(statusLabel(accessibilityStatus))"
        inputMonitoringPermissionItem.title = "Input Monitoring: \(statusLabel(inputStatus))"
        screenRecordingPermissionItem.title = "Screen Recording: \(statusLabel(screenStatus))"

        let needed = permissionsRequiredForEnabledFeatures().contains {
            runtime.permissionStatus(for: $0) != .granted
        }
        summaryItem.title = needed ? "Status: Permissions Needed" : "Status: Ready"
    }

    private func statusLabel(_ status: PermissionStatus) -> String {
        switch status {
        case .granted:
            "Granted"
        case .notDetermined, .denied:
            "Not Granted"
        }
    }

    private func handleToggle(_ feature: FeatureToggle) {
        let targetEnabled = !isFeatureEnabled(feature)

        if targetEnabled {
            let missingPermissions = permissionsRequired(for: feature).filter {
                runtime.permissionStatus(for: $0) != .granted
            }
            if !missingPermissions.isEmpty {
                let confirmed = presentPrePermissionPrompt(
                    feature: feature, missingPermissions: missingPermissions)
                guard confirmed else {
                    refreshMenuState()
                    return
                }

                for permission in missingPermissions {
                    let requestResult = runtime.requestPermission(permission)
                    if requestResult == .denied {
                        presentPermissionDeniedAlert(permission)
                        refreshMenuState()
                        return
                    }
                }
            }
        }

        setFeature(feature, enabled: targetEnabled)
        persistAndApplyCurrentConfig()
        refreshMenuState()
    }

    private func handlePermissionRowClick(_ permission: PermissionKind) {
        let result = runtime.requestPermission(permission)
        if result == .denied {
            runtime.openSystemSettings(for: permission)
            refreshMenuState()
            return
        }

        if config.activation.overrideSystemCmdTab || config.directional.enabled || config.appearance.showThumbnails {
            do {
                try runtime.applyConfig(config)
            } catch {
                presentErrorAlert(
                    title: "Unable to Apply Configuration", message: error.localizedDescription)
            }
        }

        refreshMenuState()
    }

    private func presentOnboardingIfNeeded() {
        guard !config.onboarding.permissionExplainerShown else { return }

        let alert = NSAlert()
        alert.alertStyle = .informational
        let projectRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let appIconURL = projectRoot.appendingPathComponent("Packaging/AppIcon.svg")
        alert.icon =
            NSImage(contentsOf: appIconURL)
            ?? NSImage(
                systemSymbolName: "hand.wave.fill",
                accessibilityDescription: "Welcome to WindNav"
            )
        alert.messageText = "Welcome to WindNav"
        alert.informativeText =
            "WindNav is controlled from the menu bar. Permissions are requested on demand when you enable related features."
        alert.addButton(withTitle: "Continue")
        alert.runModal()

        config.onboarding.permissionExplainerShown = true
        do {
            try settingsStore.save(config)
        } catch {
            Logger.error(
                .config, "Failed to persist onboarding state: \(error.localizedDescription)")
        }
    }

    private func presentPrePermissionPrompt(
        feature: FeatureToggle, missingPermissions: [PermissionKind]
    ) -> Bool {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "Enable \(feature.title)?"
        let names = missingPermissions.map(permissionTitle).joined(separator: ", ")
        alert.informativeText =
            "WindNav needs \(names) to enable this feature. Continue to show the macOS permission prompt."
        alert.addButton(withTitle: "Continue")
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn
    }

    private func presentPermissionDeniedAlert(_ permission: PermissionKind) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "\(permissionTitle(permission)) Permission Required"
        alert.informativeText =
            "WindNav could not enable this feature because \(permissionTitle(permission)) was denied. Open System Settings to grant access."
        alert.addButton(withTitle: "Open Settings")
        alert.addButton(withTitle: "Not Now")
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            runtime.openSystemSettings(for: permission)
        }
    }

    private func presentErrorAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    private func permissionTitle(_ permission: PermissionKind) -> String {
        switch permission {
        case .accessibility:
            "Accessibility"
        case .inputMonitoring:
            "Input Monitoring"
        case .screenRecording:
            "Screen Recording"
        }
    }

    private func isFeatureEnabled(_ feature: FeatureToggle) -> Bool {
        switch feature {
        case .cmdTabOverride:
            config.activation.overrideSystemCmdTab
        case .directionalNavigation:
            config.directional.enabled
        case .thumbnails:
            config.appearance.showThumbnails
        }
    }

    private func setFeature(_ feature: FeatureToggle, enabled: Bool) {
        switch feature {
        case .cmdTabOverride:
            config.activation.overrideSystemCmdTab = enabled
        case .directionalNavigation:
            config.directional.enabled = enabled
        case .thumbnails:
            config.appearance.showThumbnails = enabled
        }
    }

    private func permissionsRequired(for feature: FeatureToggle) -> [PermissionKind] {
        switch feature {
        case .cmdTabOverride, .directionalNavigation:
            [.accessibility, .inputMonitoring]
        case .thumbnails:
            [.screenRecording]
        }
    }

    private func permissionsRequiredForEnabledFeatures() -> [PermissionKind] {
        var required: [PermissionKind] = []
        if config.activation.overrideSystemCmdTab || config.directional.enabled {
            required.append(contentsOf: [.accessibility, .inputMonitoring])
        }
        if config.appearance.showThumbnails {
            required.append(.screenRecording)
        }
        return required
    }

    private func persistAndApplyCurrentConfig() {
        do {
            try settingsStore.save(config)
            try runtime.applyConfig(config)
        } catch {
            Logger.error(
                .runtime, "Failed to apply menu settings update: \(error.localizedDescription)")
            presentErrorAlert(title: "Unable to Save Settings", message: error.localizedDescription)
            refreshFromDiskIfPossible()
        }
    }

    private func refreshFromDiskIfPossible() {
        do {
            config = try settingsStore.loadOrCreate()
        } catch {
            Logger.error(
                .config, "Failed to reload config for menu state: \(error.localizedDescription)")
        }
    }
}
