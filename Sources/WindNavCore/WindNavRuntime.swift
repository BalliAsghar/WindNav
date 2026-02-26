import AppKit
import Foundation

@MainActor
public final class WindNavRuntime {
    private let configLoader: ConfigLoader
    private let configWatcher: ConfigWatcher
    private let windowProvider: AXWindowProvider
    private let focusPerformer: AXFocusPerformer
    private let observerHub: AXEventObserverHub
    private let cache: WindowStateCache
    private let navigator: LogicalCycleNavigator
    private let mruOrderStore: MRUWindowOrderStore
    private let hotkeys: CarbonHotkeyRegistrar

    private var coordinator: NavigationCoordinator?

    public init(configURL: URL? = nil) {
        let resolvedURL = configURL ?? Self.defaultConfigURL()
        configLoader = ConfigLoader(configURL: resolvedURL)
        configWatcher = ConfigWatcher(configURL: resolvedURL)
        windowProvider = AXWindowProvider()
        focusPerformer = AXFocusPerformer()
        observerHub = AXEventObserverHub()
        cache = WindowStateCache(provider: windowProvider)
        navigator = LogicalCycleNavigator()
        mruOrderStore = MRUWindowOrderStore()
        hotkeys = CarbonHotkeyRegistrar()
    }

    public func start() {
        Logger.configure(level: .info, colorMode: .auto)
        Logger.info(.runtime, "Starting WindNav")

        do {
            let config = try configLoader.loadOrCreate()
            Logger.info(.config, "Loaded config from \(configLoader.configURL.path)")
            try apply(config: config)
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
            }
        }
        Logger.info(.observer, "Starting AX/Workspace observers")
        observerHub.start()

        Task { @MainActor in
            await cache.refresh()
        }

        Logger.info(.config, "Starting config watcher")
        configWatcher.start { [weak self] in
            guard let self else { return }
            Logger.info(.config, "Config file change detected")
            self.reloadConfig()
        }

        Logger.info(.runtime, "WindNav is running")
    }

    private func reloadConfig() {
        do {
            let config = try configLoader.loadOrCreate()
            try apply(config: config)
            Logger.info(.config, "Config reloaded")
        } catch {
            Logger.error(.config, "Config reload failed: \(error.localizedDescription)")
        }
    }

    private func apply(config: WindNavConfig) throws {
        Logger.configure(level: config.logging.level, colorMode: config.logging.color)
        Logger.info(.config, "Logging configured (level=\(config.logging.level.rawValue), color=\(config.logging.color.rawValue))")

        let parsedBindings = try parseBindings(config.hotkeys)
        Logger.info(.hotkey, "Parsed hotkey bindings")

        if coordinator == nil {
            coordinator = NavigationCoordinator(
                cache: cache,
                focusedWindowProvider: windowProvider,
                focusPerformer: focusPerformer,
                navigator: navigator,
                mruOrderStore: mruOrderStore,
                navigationConfig: config.navigation
            )
        } else {
            coordinator?.updateConfig(config.navigation)
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
}
