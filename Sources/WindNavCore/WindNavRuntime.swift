import AppKit
import Foundation

@MainActor
public final class WindNavRuntime {
    private let configLoader: ConfigLoader
    private let windowProvider: AXWindowProvider
    private let focusPerformer: AXFocusPerformer
    private let observerHub: AXEventObserverHub
    private let cache: WindowStateCache
    private let navigator: LogicalCycleNavigator
    private let mruOrderStore: MRUWindowOrderStore
    private let appRingStateStore: AppRingStateStore
    private let appFocusMemoryStore: AppFocusMemoryStore
    private let hotkeys: CarbonHotkeyRegistrar
    private let launchAtLoginManager: any LaunchAtLoginManaging
    private let hudController: CycleHUDController

    private var coordinator: NavigationCoordinator?

    public convenience init(configURL: URL? = nil) {
        self.init(configURL: configURL, launchAtLoginManager: LaunchAtLoginManager())
    }

    init(configURL: URL?, launchAtLoginManager: any LaunchAtLoginManaging) {
        let resolvedURL = configURL ?? Self.defaultConfigURL()
        configLoader = ConfigLoader(configURL: resolvedURL)
        windowProvider = AXWindowProvider()
        focusPerformer = AXFocusPerformer()
        observerHub = AXEventObserverHub()
        cache = WindowStateCache(provider: windowProvider)
        navigator = LogicalCycleNavigator()
        mruOrderStore = MRUWindowOrderStore()
        appRingStateStore = AppRingStateStore()
        appFocusMemoryStore = AppFocusMemoryStore()
        hotkeys = CarbonHotkeyRegistrar()
        self.launchAtLoginManager = launchAtLoginManager
        hudController = CycleHUDController()
    }

    public func start() {
        Logger.configure(level: .info, colorMode: .auto)
        Logger.info(.runtime, "Starting WindNav")

        do {
            let config = try configLoader.loadOrCreate()
            Logger.info(.config, "Loaded config from \(configLoader.configURL.path)")
            try apply(config: config)
            Logger.info(.config, "Config changes require restarting WindNav (live reload disabled)")
        } catch {
            Logger.error(.config, "Failed to load config: \(error.localizedDescription)")
            NSApp.terminate(nil)
            return
        }

        Logger.info(.ax, "Checking accessibility permissions")
        guard AXPermission.ensureTrusted(prompt: true) else {
            Logger.error(.ax, "Accessibility permission is required. Grant permission and start WindNav again.")
            NSApp.terminate(nil)
            return
        }
        Logger.info(.ax, "Accessibility permission granted")

        observerHub.onEvent = { [weak self] in
            guard let self else { return }
            Task { @MainActor in
                await self.cache.refresh()
                await self.coordinator?.recordCurrentSystemFocusIfAvailable()
            }
        }
        Logger.info(.observer, "Starting AX/Workspace observers")
        observerHub.start()

        Task { @MainActor in
            await cache.refresh()
        }

        Logger.info(.runtime, "WindNav is running")
    }

    private func apply(config: WindNavConfig) throws {
        Logger.configure(level: config.logging.level, colorMode: config.logging.color)
        Logger.info(.config, "Logging configured (level=\(config.logging.level.rawValue), color=\(config.logging.color.rawValue))")
        applyLaunchAtLogin(config.startup.launchOnLogin)

        let parsedBindings = try parseBindings(config.hotkeys)
        Logger.info(.hotkey, "Parsed hotkey bindings")

        if coordinator == nil {
            coordinator = NavigationCoordinator(
                cache: cache,
                focusedWindowProvider: windowProvider,
                focusPerformer: focusPerformer,
                navigator: navigator,
                mruOrderStore: mruOrderStore,
                appRingStateStore: appRingStateStore,
                appFocusMemoryStore: appFocusMemoryStore,
                hudController: hudController,
                navigationConfig: config.navigation,
                hudConfig: config.hud
            )
        } else {
            coordinator?.updateConfig(navigation: config.navigation, hud: config.hud)
            Logger.info(.navigation, "Navigation config updated")
        }

        try hotkeys.register(bindings: parsedBindings) { [weak self] direction in
            self?.coordinator?.enqueue(direction)
        }
        Logger.info(.hotkey, "Hotkeys registered")
    }

    private func parseBindings(_ hotkeys: HotkeysConfig) throws -> [Direction: ParsedHotkey] {
        [
            .left: try HotkeyParser.parse(hotkeys.focusLeft),
            .right: try HotkeyParser.parse(hotkeys.focusRight),
        ]
    }

    private static func defaultConfigURL() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appending(path: ".config", directoryHint: .isDirectory)
            .appending(path: "windnav", directoryHint: .isDirectory)
            .appending(path: "config.toml", directoryHint: .notDirectory)
    }

    func applyLaunchAtLogin(_ enabled: Bool) {
        let requested = enabled ? "true" : "false"
        let statusBefore = launchAtLoginManager.statusDescription

        if launchAtLoginManager.isEnabled == enabled {
            Logger.info(
                .startup,
                "Launch-on-login already \(enabled ? "enabled" : "disabled") (status=\(statusBefore))"
            )
            return
        }

        Logger.info(.startup, "Applying launch-on-login=\(requested) (status-before=\(statusBefore))")

        do {
            try launchAtLoginManager.setEnabled(enabled)
        } catch {
            Logger.error(.startup, "Failed to apply launch-on-login=\(requested); continuing startup: \(error.localizedDescription)")
        }
    }
}
