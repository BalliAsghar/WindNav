import AppKit
import Foundation

@MainActor
public final class WindNavRuntime {
    private let configLoader: ConfigLoader
    private let windowProvider: AXWindowProvider
    private let focusPerformer: AXFocusPerformer
    private let observerHub: AXEventObserverHub
    private let cache: WindowStateCache
    private let appRingStateStore: AppRingStateStore
    private let appFocusMemoryStore: AppFocusMemoryStore
    private let hotkeys: CarbonHotkeyRegistrar
    private let launchAtLoginManager: any LaunchAtLoginManaging
    private let hudController: CycleHUDController

    private var coordinator: NavigationCoordinator?
    private var modifierMonitor: Any?
    private var holdCycleUntilModifierRelease = false
    private var activeCycleModifierFlags: NSEvent.ModifierFlags = []

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
        windowProvider.updateNavigationConfig(config.navigation)
        Logger.info(
            .navigation,
            "Navigation visibility configured (include-minimized=\(config.navigation.includeMinimized), include-hidden-apps=\(config.navigation.includeHiddenApps))"
        )

        let parsedBindings = try parseBindings(config.hotkeys)
        Logger.info(.hotkey, "Parsed hotkey bindings")

        if coordinator == nil {
            coordinator = NavigationCoordinator(
                cache: cache,
                focusedWindowProvider: windowProvider,
                focusPerformer: focusPerformer,
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

        holdCycleUntilModifierRelease = config.navigation.cycleTimeoutMs == 0
        if holdCycleUntilModifierRelease {
            installModifierMonitorIfNeeded()
        } else {
            activeCycleModifierFlags = []
            uninstallModifierMonitorIfNeeded()
        }

        try hotkeys.register(bindings: parsedBindings) { [weak self] direction, carbonModifiers in
            guard let self else { return }
            if self.holdCycleUntilModifierRelease {
                self.activeCycleModifierFlags = Self.eventModifierFlags(fromCarbonModifiers: carbonModifiers)
            }
            self.coordinator?.enqueue(direction)
        }
        Logger.info(.hotkey, "Hotkeys registered")
    }

    private func parseBindings(_ hotkeys: HotkeysConfig) throws -> [Direction: ParsedHotkey] {
        [
            .left: try HotkeyParser.parse(hotkeys.focusLeft),
            .right: try HotkeyParser.parse(hotkeys.focusRight),
            .up: try HotkeyParser.parse(hotkeys.focusUp),
            .down: try HotkeyParser.parse(hotkeys.focusDown),
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

    private func installModifierMonitorIfNeeded() {
        guard modifierMonitor == nil else { return }
        modifierMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            guard let self else { return }
            Task { @MainActor in
                self.handleModifierFlagsChanged(event.modifierFlags)
            }
        }
    }

    private func uninstallModifierMonitorIfNeeded() {
        guard let modifierMonitor else { return }
        NSEvent.removeMonitor(modifierMonitor)
        self.modifierMonitor = nil
    }

    private func handleModifierFlagsChanged(_ flags: NSEvent.ModifierFlags) {
        guard holdCycleUntilModifierRelease else { return }
        let required = activeCycleModifierFlags
        guard !required.isEmpty else { return }

        let current = flags.intersection([.command, .option, .control, .shift])
        guard current.isSuperset(of: required) else {
            activeCycleModifierFlags = []
            coordinator?.endCycleSessionOnModifierRelease()
            return
        }
    }

    private static func eventModifierFlags(fromCarbonModifiers modifiers: UInt32) -> NSEvent.ModifierFlags {
        let cmdMask: UInt32 = 1 << 8
        let shiftMask: UInt32 = 1 << 9
        let optionMask: UInt32 = 1 << 11
        let controlMask: UInt32 = 1 << 12

        var flags: NSEvent.ModifierFlags = []
        if modifiers & cmdMask != 0 {
            flags.insert(.command)
        }
        if modifiers & optionMask != 0 {
            flags.insert(.option)
        }
        if modifiers & controlMask != 0 {
            flags.insert(.control)
        }
        if modifiers & shiftMask != 0 {
            flags.insert(.shift)
        }
        return flags
    }
}
