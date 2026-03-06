import AppKit
import XCTest
@testable import TabApp
import TabCore

@MainActor
final class MenuBarViewModelTests: XCTestCase {
    func testInitialStateReflectsPersistedConfigAndPermissionStatuses() throws {
        var config = TabConfig.default
        config.directional.enabled = false
        config.appearance.showThumbnails = false

        let runtime = RuntimeStub(
            statuses: [
                .accessibility: .granted,
                .screenRecording: .granted,
            ]
        )
        let settingsStore = SettingsStoreStub(storedConfig: config)
        let alerts = AlertPresenterStub()

        let viewModel = try MenuBarViewModel(
            runtime: runtime,
            settingsStore: settingsStore,
            alertPresenter: alerts
        )

        XCTAssertFalse(viewModel.isFeatureEnabled(.directionalNavigation))
        XCTAssertFalse(viewModel.isFeatureEnabled(.thumbnails))
        XCTAssertEqual(viewModel.statusLabel(for: .accessibility), "Granted")
        XCTAssertEqual(viewModel.summaryText, "Status: Ready")
    }

    func testEnableFeatureCancelledAtPrePermissionPromptDoesNotPersist() throws {
        var config = TabConfig.default
        config.directional.enabled = false
        config.appearance.showThumbnails = false

        let runtime = RuntimeStub(
            statuses: [
                .accessibility: .notDetermined,
                .screenRecording: .granted,
            ]
        )
        let settingsStore = SettingsStoreStub(storedConfig: config)
        let alerts = AlertPresenterStub()
        alerts.prePermissionResponses = [false]

        let viewModel = try MenuBarViewModel(
            runtime: runtime,
            settingsStore: settingsStore,
            alertPresenter: alerts
        )

        viewModel.setFeature(.directionalNavigation, enabled: true)

        XCTAssertFalse(viewModel.isFeatureEnabled(.directionalNavigation))
        XCTAssertEqual(alerts.prePermissionPrompts.count, 1)
        XCTAssertTrue(runtime.requestedPermissions.isEmpty)
        XCTAssertTrue(settingsStore.savedConfigs.isEmpty)
    }

    func testEnableFeatureDeniedPermissionShowsAlertAndCanOpenSettings() throws {
        var config = TabConfig.default
        config.directional.enabled = false
        config.appearance.showThumbnails = false

        let runtime = RuntimeStub(
            statuses: [
                .accessibility: .notDetermined,
                .screenRecording: .granted,
            ]
        )
        runtime.requestResults[.accessibility] = [.denied]

        let settingsStore = SettingsStoreStub(storedConfig: config)
        let alerts = AlertPresenterStub()
        alerts.prePermissionResponses = [true]
        alerts.permissionDeniedAlertResponse = true

        let viewModel = try MenuBarViewModel(
            runtime: runtime,
            settingsStore: settingsStore,
            alertPresenter: alerts
        )

        viewModel.setFeature(.directionalNavigation, enabled: true)

        XCTAssertFalse(viewModel.isFeatureEnabled(.directionalNavigation))
        XCTAssertEqual(alerts.permissionDeniedCalls, [.accessibility])
        XCTAssertEqual(runtime.openedSettingsPermissions, [.accessibility])
        XCTAssertTrue(settingsStore.savedConfigs.isEmpty)
    }

    func testPermissionRowDenialOpensSystemSettings() throws {
        var config = TabConfig.default
        config.directional.enabled = false
        config.appearance.showThumbnails = false

        let runtime = RuntimeStub(
            statuses: [
                .accessibility: .granted,
                .screenRecording: .denied,
            ]
        )
        runtime.requestResults[.screenRecording] = [.denied]

        let viewModel = try MenuBarViewModel(
            runtime: runtime,
            settingsStore: SettingsStoreStub(storedConfig: config),
            alertPresenter: AlertPresenterStub()
        )

        viewModel.handlePermissionRowClick(.screenRecording)

        XCTAssertEqual(runtime.openedSettingsPermissions, [.screenRecording])
    }

    func testSuccessfulTogglePersistsAndAppliesConfig() throws {
        var config = TabConfig.default
        config.directional.enabled = false
        config.appearance.showThumbnails = false

        let runtime = RuntimeStub(
            statuses: [
                .accessibility: .granted,
                .screenRecording: .granted,
            ]
        )
        let settingsStore = SettingsStoreStub(storedConfig: config)
        let viewModel = try MenuBarViewModel(
            runtime: runtime,
            settingsStore: settingsStore,
            alertPresenter: AlertPresenterStub()
        )

        viewModel.setFeature(.directionalNavigation, enabled: true)

        XCTAssertTrue(viewModel.isFeatureEnabled(.directionalNavigation))
        XCTAssertEqual(settingsStore.savedConfigs.count, 1)
        XCTAssertTrue(settingsStore.savedConfigs[0].directional.enabled)
        XCTAssertEqual(runtime.appliedConfigs.count, 1)
        XCTAssertTrue(runtime.appliedConfigs[0].directional.enabled)
    }

    func testSaveFailureShowsErrorAndReloadsConfig() throws {
        var config = TabConfig.default
        config.directional.enabled = false
        config.appearance.showThumbnails = false

        let runtime = RuntimeStub(
            statuses: [
                .accessibility: .granted,
                .screenRecording: .granted,
            ]
        )
        let settingsStore = SettingsStoreStub(storedConfig: config)
        settingsStore.saveError = StubError.saveFailed
        let alerts = AlertPresenterStub()

        let viewModel = try MenuBarViewModel(
            runtime: runtime,
            settingsStore: settingsStore,
            alertPresenter: alerts
        )

        viewModel.setFeature(.thumbnails, enabled: true)

        XCTAssertFalse(viewModel.isFeatureEnabled(.thumbnails))
        XCTAssertEqual(alerts.errorAlerts.count, 1)
        XCTAssertTrue(runtime.appliedConfigs.isEmpty)
    }

    func testApplyFailureShowsErrorAndReloadsPersistedConfig() throws {
        var config = TabConfig.default
        config.directional.enabled = false
        config.appearance.showThumbnails = false

        let runtime = RuntimeStub(
            statuses: [
                .accessibility: .granted,
                .screenRecording: .granted,
            ]
        )
        runtime.applyError = StubError.applyFailed

        let settingsStore = SettingsStoreStub(storedConfig: config)
        let alerts = AlertPresenterStub()

        let viewModel = try MenuBarViewModel(
            runtime: runtime,
            settingsStore: settingsStore,
            alertPresenter: alerts
        )

        viewModel.setFeature(.thumbnails, enabled: true)

        XCTAssertTrue(viewModel.isFeatureEnabled(.thumbnails))
        XCTAssertEqual(settingsStore.savedConfigs.count, 1)
        XCTAssertEqual(alerts.errorAlerts.count, 1)
        XCTAssertTrue(runtime.appliedConfigs.isEmpty)
    }

    func testSummaryStatusTracksPermissionRequirementsForEnabledFeatures() throws {
        var config = TabConfig.default
        config.directional.enabled = false
        config.appearance.showThumbnails = false

        let runtime = RuntimeStub(
            statuses: [
                .accessibility: .denied,
                .screenRecording: .denied,
            ]
        )
        let settingsStore = SettingsStoreStub(storedConfig: config)
        let viewModel = try MenuBarViewModel(
            runtime: runtime,
            settingsStore: settingsStore,
            alertPresenter: AlertPresenterStub()
        )

        XCTAssertEqual(viewModel.summaryText, "Status: Permissions Needed")

        runtime.statuses[.accessibility] = .granted
        settingsStore.storedConfig = config

        viewModel.refreshFromDiskIfPossible()

        XCTAssertEqual(viewModel.summaryText, "Status: Ready")
    }

    func testOnboardingShownOnceAndPersistsFlag() throws {
        var config = TabConfig.default
        config.onboarding.permissionExplainerShown = false

        let settingsStore = SettingsStoreStub(storedConfig: config)
        let alerts = AlertPresenterStub()
        let viewModel = try MenuBarViewModel(
            runtime: RuntimeStub(statuses: [:]),
            settingsStore: settingsStore,
            alertPresenter: alerts
        )

        viewModel.presentOnboardingIfNeeded(appIcon: nil)
        viewModel.presentOnboardingIfNeeded(appIcon: nil)

        XCTAssertEqual(alerts.onboardingCallCount, 1)
        XCTAssertEqual(settingsStore.savedConfigs.count, 1)
        XCTAssertTrue(settingsStore.savedConfigs[0].onboarding.permissionExplainerShown)
    }

    func testLaunchAtLoginToggleOnSuccessPersistsTrue() throws {
        var config = TabConfig.default
        config.onboarding.launchAtLoginEnabled = false

        let launchAtLoginManager = LaunchAtLoginManagerStub(isEnabled: false)
        let settingsStore = SettingsStoreStub(storedConfig: config)
        let alerts = AlertPresenterStub()
        let viewModel = try MenuBarViewModel(
            runtime: RuntimeStub(statuses: [:]),
            settingsStore: settingsStore,
            alertPresenter: alerts,
            launchAtLoginManager: launchAtLoginManager
        )

        viewModel.setLaunchAtLoginEnabled(true)

        XCTAssertEqual(launchAtLoginManager.requests, [true])
        XCTAssertTrue(viewModel.isLaunchAtLoginEnabled())
        XCTAssertEqual(settingsStore.savedConfigs.last?.onboarding.launchAtLoginEnabled, true)
        XCTAssertTrue(alerts.launchAtLoginErrors.isEmpty)
    }

    func testLaunchAtLoginToggleOffSuccessPersistsFalse() throws {
        var config = TabConfig.default
        config.onboarding.launchAtLoginEnabled = true

        let launchAtLoginManager = LaunchAtLoginManagerStub(isEnabled: true)
        let settingsStore = SettingsStoreStub(storedConfig: config)
        let alerts = AlertPresenterStub()
        let viewModel = try MenuBarViewModel(
            runtime: RuntimeStub(statuses: [:]),
            settingsStore: settingsStore,
            alertPresenter: alerts,
            launchAtLoginManager: launchAtLoginManager
        )

        viewModel.setLaunchAtLoginEnabled(false)

        XCTAssertEqual(launchAtLoginManager.requests, [false])
        XCTAssertFalse(viewModel.isLaunchAtLoginEnabled())
        XCTAssertEqual(settingsStore.savedConfigs.last?.onboarding.launchAtLoginEnabled, false)
        XCTAssertTrue(alerts.launchAtLoginErrors.isEmpty)
    }

    func testLaunchAtLoginToggleOnFailureRevertsAndShowsError() throws {
        var config = TabConfig.default
        config.onboarding.launchAtLoginEnabled = false

        let launchAtLoginManager = LaunchAtLoginManagerStub(isEnabled: false)
        launchAtLoginManager.errorForSet = StubError.launchAtLoginFailed
        let settingsStore = SettingsStoreStub(storedConfig: config)
        let alerts = AlertPresenterStub()
        let viewModel = try MenuBarViewModel(
            runtime: RuntimeStub(statuses: [:]),
            settingsStore: settingsStore,
            alertPresenter: alerts,
            launchAtLoginManager: launchAtLoginManager
        )

        viewModel.setLaunchAtLoginEnabled(true)

        XCTAssertFalse(viewModel.isLaunchAtLoginEnabled())
        XCTAssertEqual(settingsStore.savedConfigs.last?.onboarding.launchAtLoginEnabled, false)
        XCTAssertEqual(alerts.launchAtLoginErrors.count, 1)
    }

    func testLaunchAtLoginToggleOffFailureRevertsAndShowsError() throws {
        var config = TabConfig.default
        config.onboarding.launchAtLoginEnabled = true

        let launchAtLoginManager = LaunchAtLoginManagerStub(isEnabled: true)
        launchAtLoginManager.errorForSet = StubError.launchAtLoginFailed
        let settingsStore = SettingsStoreStub(storedConfig: config)
        let alerts = AlertPresenterStub()
        let viewModel = try MenuBarViewModel(
            runtime: RuntimeStub(statuses: [:]),
            settingsStore: settingsStore,
            alertPresenter: alerts,
            launchAtLoginManager: launchAtLoginManager
        )

        viewModel.setLaunchAtLoginEnabled(false)

        XCTAssertTrue(viewModel.isLaunchAtLoginEnabled())
        XCTAssertEqual(settingsStore.savedConfigs.last?.onboarding.launchAtLoginEnabled, true)
        XCTAssertEqual(alerts.launchAtLoginErrors.count, 1)
    }

    func testLaunchAtLoginReconcileSavedTrueActualFalseAttemptsEnable() throws {
        var config = TabConfig.default
        config.onboarding.launchAtLoginEnabled = true

        let launchAtLoginManager = LaunchAtLoginManagerStub(isEnabled: false)
        let settingsStore = SettingsStoreStub(storedConfig: config)
        let viewModel = try MenuBarViewModel(
            runtime: RuntimeStub(statuses: [:]),
            settingsStore: settingsStore,
            alertPresenter: AlertPresenterStub(),
            launchAtLoginManager: launchAtLoginManager
        )

        viewModel.reconcileLaunchAtLoginStateOnStartup()

        XCTAssertEqual(launchAtLoginManager.requests, [true])
        XCTAssertTrue(viewModel.isLaunchAtLoginEnabled())
    }

    func testLaunchAtLoginReconcileSavedFalseActualTrueAttemptsDisable() throws {
        var config = TabConfig.default
        config.onboarding.launchAtLoginEnabled = false

        let launchAtLoginManager = LaunchAtLoginManagerStub(isEnabled: true)
        let settingsStore = SettingsStoreStub(storedConfig: config)
        let viewModel = try MenuBarViewModel(
            runtime: RuntimeStub(statuses: [:]),
            settingsStore: settingsStore,
            alertPresenter: AlertPresenterStub(),
            launchAtLoginManager: launchAtLoginManager
        )

        viewModel.reconcileLaunchAtLoginStateOnStartup()

        XCTAssertEqual(launchAtLoginManager.requests, [false])
        XCTAssertFalse(viewModel.isLaunchAtLoginEnabled())
    }

    func testLaunchAtLoginReconcileFailurePersistsActualAndDoesNotCrash() throws {
        var config = TabConfig.default
        config.onboarding.launchAtLoginEnabled = true

        let launchAtLoginManager = LaunchAtLoginManagerStub(isEnabled: false)
        launchAtLoginManager.errorForSet = StubError.launchAtLoginFailed
        let settingsStore = SettingsStoreStub(storedConfig: config)
        let viewModel = try MenuBarViewModel(
            runtime: RuntimeStub(statuses: [:]),
            settingsStore: settingsStore,
            alertPresenter: AlertPresenterStub(),
            launchAtLoginManager: launchAtLoginManager
        )

        viewModel.reconcileLaunchAtLoginStateOnStartup()

        XCTAssertEqual(launchAtLoginManager.requests, [true])
        XCTAssertEqual(settingsStore.savedConfigs.last?.onboarding.launchAtLoginEnabled, false)
    }
}

@MainActor
private final class RuntimeStub: MenuBarRuntimeProviding {
    var statuses: [PermissionKind: PermissionStatus]
    var requestResults: [PermissionKind: [PermissionRequestResult]] = [:]
    var requestedPermissions: [PermissionKind] = []
    var openedSettingsPermissions: [PermissionKind] = []
    var appliedConfigs: [TabConfig] = []
    var applyError: Error?

    init(statuses: [PermissionKind: PermissionStatus]) {
        self.statuses = statuses
    }

    func permissionStatus(for permission: PermissionKind) -> PermissionStatus {
        statuses[permission] ?? .notDetermined
    }

    func requestPermission(_ permission: PermissionKind) -> PermissionRequestResult {
        requestedPermissions.append(permission)
        var queued = requestResults[permission] ?? []
        let result = queued.isEmpty ? .granted : queued.removeFirst()
        requestResults[permission] = queued
        statuses[permission] = result == .granted ? .granted : .denied
        return result
    }

    func openSystemSettings(for permission: PermissionKind) {
        openedSettingsPermissions.append(permission)
    }

    func applyConfig(_ updated: TabConfig) throws {
        if let applyError {
            throw applyError
        }
        appliedConfigs.append(updated)
    }
}

@MainActor
private final class SettingsStoreStub: MenuBarSettingsStoreProviding {
    var storedConfig: TabConfig
    var loadError: Error?
    var saveError: Error?
    var savedConfigs: [TabConfig] = []

    init(storedConfig: TabConfig) {
        self.storedConfig = storedConfig
    }

    func loadOrCreate() throws -> TabConfig {
        if let loadError {
            throw loadError
        }
        return storedConfig
    }

    func save(_ config: TabConfig) throws {
        if let saveError {
            throw saveError
        }
        storedConfig = config
        savedConfigs.append(config)
    }
}

@MainActor
private final class AlertPresenterStub: MenuBarAlertPresenting {
    var onboardingCallCount = 0
    var prePermissionResponses: [Bool] = [true]
    var prePermissionPrompts: [(featureTitle: String, permissions: [PermissionKind])] = []
    var permissionDeniedAlertResponse = false
    var permissionDeniedCalls: [PermissionKind] = []
    var errorAlerts: [(title: String, message: String)] = []
    var launchAtLoginErrors: [String] = []

    func presentOnboarding(appIcon: NSImage?) {
        onboardingCallCount += 1
    }

    func presentPrePermissionPrompt(featureTitle: String, missingPermissions: [PermissionKind]) -> Bool {
        prePermissionPrompts.append((featureTitle: featureTitle, permissions: missingPermissions))
        if prePermissionResponses.isEmpty {
            return true
        }
        return prePermissionResponses.removeFirst()
    }

    func presentPermissionDeniedAlert(_ permission: PermissionKind) -> Bool {
        permissionDeniedCalls.append(permission)
        return permissionDeniedAlertResponse
    }

    func presentErrorAlert(title: String, message: String) {
        errorAlerts.append((title: title, message: message))
    }

    func presentLaunchAtLoginError(message: String) {
        launchAtLoginErrors.append(message)
    }
}

private final class LaunchAtLoginManagerStub: LaunchAtLoginManaging {
    var isEnabled: Bool
    var statusDescription: String = "enabled"
    var requests: [Bool] = []
    var errorForSet: Error?

    init(isEnabled: Bool) {
        self.isEnabled = isEnabled
        self.statusDescription = isEnabled ? "enabled" : "notRegistered"
    }

    func setEnabled(_ enabled: Bool) throws {
        requests.append(enabled)
        if let errorForSet {
            throw errorForSet
        }
        isEnabled = enabled
        statusDescription = enabled ? "enabled" : "notRegistered"
    }
}

private enum StubError: Error {
    case saveFailed
    case applyFailed
    case launchAtLoginFailed
}
