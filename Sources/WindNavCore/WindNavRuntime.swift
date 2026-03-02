import AppKit
import Foundation
import Carbon.HIToolbox

private enum ActiveFlowKind: Sendable {
    case navigation
    case browse
}

private enum LocalKeybind {
    case tab
    case shiftTab
    case cmdQ
}

@MainActor
private final class LocalKeybindMonitor {
    private var monitor: Any?
    private let callback: (LocalKeybind, Bool) -> Void
    
    init(callback: @escaping (LocalKeybind, Bool) -> Void) {
        self.callback = callback
    }
    
    func start() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp]) { [weak self] event in
            guard let self else { return event }
            if self.handleKeyEvent(event) {
                return nil
            }
            return event
        }
    }
    
    func stop() {
        if let monitor = monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }
    
    private func handleKeyEvent(_ event: NSEvent) -> Bool {
        let keyCode = UInt16(event.keyCode)
        let modifiers = event.modifierFlags.intersection([.command, .shift, .option, .control])
        let isKeyDown = event.type == .keyDown
        
        if keyCode == UInt16(kVK_Tab) && modifiers == .command {
            callback(.tab, isKeyDown)
            return true
        }
        
        if keyCode == UInt16(kVK_Tab) && modifiers == [.command, .shift] {
            callback(.shiftTab, isKeyDown)
            return true
        }
        
        if keyCode == UInt16(kVK_ANSI_Q) && modifiers == .command && isKeyDown {
            callback(.cmdQ, isKeyDown)
            return true
        }
        
        return false
    }
}

private struct InputSessionState: Sendable {
    let sessionID: UInt64
    let requiredModifierFlags: NSEvent.ModifierFlags
    let flowKind: ActiveFlowKind
}

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

    private var navigationController: NavigationCoordinator?
    private var browseController: BrowseFlowController?
    private var modifierMonitor: Any?
    private var localKeybindMonitor: LocalKeybindMonitor?
    private var holdCycleUntilModifierRelease = false
    private var inputSession: InputSessionState?
    private var nextInputSessionID: UInt64 = 0

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
        
        localKeybindMonitor = LocalKeybindMonitor { [weak self] keybind, isKeyDown in
            guard let self, isKeyDown else { return }
            Task { @MainActor in
                self.handleLocalKeybind(keybind)
            }
        }
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
                await self.navigationController?.recordCurrentSystemFocusIfAvailable()
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
        
        SystemHotkeyOverride.disableSystemCmdTab()

        if navigationController == nil {
            navigationController = NavigationCoordinator(
                cache: cache,
                focusedWindowProvider: windowProvider,
                focusPerformer: focusPerformer,
                appRingStateStore: appRingStateStore,
                appFocusMemoryStore: appFocusMemoryStore,
                hudController: hudController,
                navigationConfig: config.navigation,
                hudConfig: config.hud
            )
            browseController = BrowseFlowController(
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
            navigationController?.updateConfig(navigation: config.navigation, hud: config.hud)
            browseController?.updateConfig(navigation: config.navigation, hud: config.hud)
            Logger.info(.navigation, "Navigation config updated")
        }

        holdCycleUntilModifierRelease = config.navigation.cycleTimeoutMs == 0
        inputSession = nil
        installModifierMonitorIfNeeded()

        try hotkeys.register(bindings: parsedBindings) { [weak self] direction, carbonModifiers in
            guard let self else { return }
            self.handleHotkey(direction, carbonModifiers: carbonModifiers)
        }
        Logger.info(.hotkey, "Hotkeys registered")
    }

    private func parseBindings(_ hotkeys: HotkeysConfig) throws -> [Direction: ParsedHotkey] {
        [
            .left: try HotkeyParser.parse(hotkeys.focusLeft),
            .right: try HotkeyParser.parse(hotkeys.focusRight),
            .up: try HotkeyParser.parse(hotkeys.browseNext),
            .down: try HotkeyParser.parse(hotkeys.browsePrevious),
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

    func handleHotkey(_ direction: Direction, carbonModifiers: UInt32) {
        let requiredFlags = Self.eventModifierFlags(fromCarbonModifiers: carbonModifiers)
        if inputSession == nil {
            let flowKind: ActiveFlowKind = (direction == .left || direction == .right) ? .navigation : .browse
            nextInputSessionID &+= 1
            inputSession = InputSessionState(
                sessionID: nextInputSessionID,
                requiredModifierFlags: requiredFlags,
                flowKind: flowKind
            )
            Logger.info(
                .navigation,
                "Started input session flow=\(flowKind == .navigation ? "nav" : "browse") session-id=\(nextInputSessionID)"
            )
            
            if flowKind == .browse {
                localKeybindMonitor?.start()
            }
        }

        guard let session = inputSession else { return }
        switch session.flowKind {
            case .navigation:
                navigationController?.enqueue(direction)
            case .browse:
                browseController?.startSessionIfNeeded()
                browseController?.handleDirection(direction)
        }
    }
    
    fileprivate func handleLocalKeybind(_ keybind: LocalKeybind) {
        guard let session = inputSession, session.flowKind == .browse else { return }
        
        switch keybind {
            case .tab:
                browseController?.handleDirection(.right)
            case .shiftTab:
                browseController?.handleDirection(.left)
            case .cmdQ:
                quitSelectedApp()
        }
    }
    
    private func quitSelectedApp() {
        guard let selectedPid = browseController?.selectedAppPid() else {
            Logger.error(.navigation, "No app selected to quit")
            return
        }
        
        let apps = NSWorkspace.shared.runningApplications
        guard let app = apps.first(where: { $0.processIdentifier == selectedPid }) else {
            Logger.error(.navigation, "Failed to find app for pid=\(selectedPid)")
            return
        }
        
        let appName = app.localizedName ?? "Unknown"
        Logger.info(.navigation, "Quitting app: \(appName) pid=\(selectedPid)")
        
        if app.bundleIdentifier == "com.apple.finder" {
            Logger.info(.navigation, "Skipping Finder quit for safety")
            return
        }
        
        let terminated = app.terminate()
        if !terminated {
            Logger.error(.navigation, "Failed to terminate app: \(appName)")
        }
    }

    func handleModifierFlagsChanged(_ flags: NSEvent.ModifierFlags) {
        guard let session = inputSession else { return }
        let required = session.requiredModifierFlags
        guard !required.isEmpty else { return }

        let current = flags.intersection([.command, .option, .control, .shift])
        guard current.isSuperset(of: required) else {
            if session.flowKind == .browse {
                localKeybindMonitor?.stop()
            }
            
            switch session.flowKind {
                case .browse:
                    browseController?.commitSessionOnModifierRelease()
                case .navigation:
                    if holdCycleUntilModifierRelease {
                        navigationController?.endCycleSessionOnModifierRelease()
                    }
            }
            inputSession = nil
            Logger.info(
                .navigation,
                "Ended input session on modifier release flow=\(session.flowKind == .navigation ? "nav" : "browse") session-id=\(session.sessionID)"
            )
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

    #if DEBUG
    func _setControllersForTests(navigation: NavigationCoordinator?, browse: BrowseFlowController?) {
        navigationController = navigation
        browseController = browse
    }

    func _setHoldCycleUntilModifierReleaseForTests(_ enabled: Bool) {
        holdCycleUntilModifierRelease = enabled
    }
    #endif
}
