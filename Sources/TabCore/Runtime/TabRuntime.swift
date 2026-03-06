import AppKit
import Carbon
import Foundation

@MainActor
public final class TabRuntime {
    private enum InputSessionFlow {
        case activationCycle
        case directionalNavigation
        case directionalBrowse
    }

    enum CycleInputCommand: Equatable {
        case move(Direction)
        case quitSelectedApp
        case closeSelectedWindow
    }

    private struct InputSession {
        let requiredModifiers: NSEvent.ModifierFlags
        let flow: InputSessionFlow
    }

    private let configLoader: ConfigLoader
    private let hotkeys: CarbonHotkeyRegistrar
    private let windowProvider: AXWindowProvider
    private let focusPerformer: FocusPerformer
    private let hudController: any HUDControlling
    private let permissionService: PermissionService
    private let thumbnailService: any WindowThumbnailProviding

    private var navigationCoordinator: NavigationCoordinator?
    private var directionalCoordinator: DirectionalCoordinator?
    private var modifierEventTap: CFMachPort?
    private var arrowKeyEventTap: CFMachPort?
    private var config: TabConfig?
    private var inputSession: InputSession?
    nonisolated(unsafe) private let captureState = SessionCaptureState()

    public convenience init(configURL: URL? = nil) {
        self.init(
            configLoader: ConfigLoader(configURL: configURL ?? ConfigLoader.defaultConfigURL()),
            hotkeys: CarbonHotkeyRegistrar(),
            windowProvider: AXWindowProvider(),
            focusPerformer: AXFocusPerformer(),
            hudController: MinimalHUDController(),
            permissionService: PermissionService(),
            thumbnailService: WindowThumbnailService()
        )
    }

    init(
        configLoader: ConfigLoader,
        hotkeys: CarbonHotkeyRegistrar,
        windowProvider: AXWindowProvider,
        focusPerformer: FocusPerformer,
        hudController: any HUDControlling,
        permissionService: PermissionService = PermissionService(),
        thumbnailService: any WindowThumbnailProviding = WindowThumbnailService()
    ) {
        self.configLoader = configLoader
        self.hotkeys = hotkeys
        self.windowProvider = windowProvider
        self.focusPerformer = focusPerformer
        self.hudController = hudController
        self.permissionService = permissionService
        self.thumbnailService = thumbnailService
    }

    public func start() {
        Logger.configure(level: .info, colorMode: .auto)
        Logger.info(.runtime, "Starting Tab++ runtime")

        do {
            let loaded = try configLoader.loadOrCreate()
            Logger.configure(level: loaded.performance.logLevel, colorMode: loaded.performance.logColor)
            Logger.info(.config, "Loaded config at \(configLoader.configURL.path)")
            try configureRuntime(with: loaded)
            Logger.info(.runtime, "Tab++ runtime started")
        } catch {
            Logger.error(.runtime, "Failed to start runtime: \(error.localizedDescription)")
            Logger.error(.runtime, "Startup aborted: initialization error")
            NSApp.terminate(nil)
        }
    }

    public func applyConfig(_ updated: TabConfig) throws {
        try configureRuntime(with: updated)
    }

    public func currentConfig() -> TabConfig? {
        config
    }

    public func permissionStatus(for permission: PermissionKind) -> PermissionStatus {
        permissionService.status(for: permission)
    }

    public func requestPermission(_ permission: PermissionKind) -> PermissionRequestResult {
        permissionService.request(permission)
    }

    public func openSystemSettings(for permission: PermissionKind) {
        permissionService.openSystemSettings(for: permission)
    }

    public func stop() {
        navigationCoordinator?.cancelCycleSession()
        directionalCoordinator?.cancelSession()
        thumbnailService.clear()
        captureState.set(activation: false, directional: false)
        inputSession = nil
        removeModifierMonitor()
        removeArrowKeyMonitor()
        hotkeys.unregisterAll()
        SystemHotkeyOverride.restoreSystemCmdTab()
        Logger.info(.runtime, "Tab++ runtime stopped")
    }

    private func configureRuntime(with loaded: TabConfig) throws {
        navigationCoordinator?.cancelCycleSession()
        directionalCoordinator?.cancelSession()
        captureState.set(activation: false, directional: false)
        inputSession = nil
        removeModifierMonitor()
        removeArrowKeyMonitor()
        hotkeys.unregisterAll()
        SystemHotkeyOverride.restoreSystemCmdTab()

        config = loaded
        windowProvider.updateConfig(loaded)
        navigationCoordinator = NavigationCoordinator(
            windowProvider: windowProvider,
            focusedWindowProvider: windowProvider,
            focusPerformer: focusPerformer,
            hudController: hudController,
            thumbnailService: thumbnailService,
            config: loaded
        )
        directionalCoordinator = DirectionalCoordinator(
            windowProvider: windowProvider,
            focusedWindowProvider: windowProvider,
            focusPerformer: focusPerformer,
            hudController: hudController,
            thumbnailService: thumbnailService,
            config: loaded
        )

        let bindings = try parseBindings(loaded)
        try hotkeys.register(bindings: bindings) { [weak self] action, carbonModifiers in
            self?.handleHotkeyAction(action, carbonModifiers: carbonModifiers)
        }
        refreshPermissionDependentCapabilities(config: loaded)
    }

    private func parseBindings(_ config: TabConfig) throws -> [HotkeyAction: ParsedHotkey] {
        var bindings: [HotkeyAction: ParsedHotkey] = [:]

        bindings[.activationForward] = try HotkeyParser.parse(config.activation.trigger)
        bindings[.activationBackward] = try HotkeyParser.parse(config.activation.reverseTrigger)

        if config.directional.enabled {
            bindings[.directionalLeft] = try HotkeyParser.parse(config.directional.left)
            bindings[.directionalRight] = try HotkeyParser.parse(config.directional.right)
            bindings[.directionalBrowseUp] = try HotkeyParser.parse(config.directional.up)
            bindings[.directionalBrowseDown] = try HotkeyParser.parse(config.directional.down)
        }

        return bindings
    }

    private func refreshPermissionDependentCapabilities(config: TabConfig) {
        let accessibilityGranted = permissionService.status(for: .accessibility) == .granted
        let shouldEnableAdvancedInput = Self.shouldEnableAdvancedInput(
            accessibilityGranted: accessibilityGranted
        )

        if !accessibilityGranted {
            Logger.info(.runtime, "Accessibility permission missing; running in limited mode")
        }

        if shouldEnableAdvancedInput {
            SystemHotkeyOverride.disableSystemCmdTab()
        } else {
            SystemHotkeyOverride.restoreSystemCmdTab()
        }

        let needsEventTaps = shouldEnableAdvancedInput
        if needsEventTaps {
            if !installModifierMonitorIfNeeded() {
                Logger.error(.hotkey, "Failed to install modifier monitor; continuing without event taps")
                removeModifierMonitor()
            }
            if !installArrowKeyMonitorIfNeeded() {
                Logger.error(.hotkey, "Failed to install arrow key monitor; continuing without event taps")
                removeArrowKeyMonitor()
            }
        } else {
            removeModifierMonitor()
            removeArrowKeyMonitor()
        }
    }

    static func shouldEnableAdvancedInput(accessibilityGranted: Bool) -> Bool {
        accessibilityGranted
    }

    private func handleHotkeyAction(_ action: HotkeyAction, carbonModifiers: UInt32) {
        let flow: InputSessionFlow
        let direction: Direction

        switch action {
            case .activationForward:
                flow = .activationCycle
                direction = .right
            case .activationBackward:
                flow = .activationCycle
                direction = .left
            case .directionalLeft:
                flow = .directionalNavigation
                direction = .left
            case .directionalRight:
                flow = .directionalNavigation
                direction = .right
            case .directionalBrowseUp:
                flow = .directionalBrowse
                direction = .up
            case .directionalBrowseDown:
                flow = .directionalBrowse
                direction = .down
        }

        if inputSession == nil {
            var required = Self.eventModifierFlags(fromCarbonModifiers: carbonModifiers)
            if flow == .activationCycle {
                required = [.command]
            }
            inputSession = InputSession(requiredModifiers: required, flow: flow)
        } else if inputSession?.flow == .activationCycle && flow != .activationCycle {
            return
        }

        switch flow {
            case .activationCycle:
                captureState.set(activation: true, directional: false)
                Task { @MainActor in
                    await navigationCoordinator?.startOrAdvanceCycle(direction: direction, hotkeyTimestamp: .now())
                    syncCaptureStateFromCoordinators()
                }
            case .directionalNavigation, .directionalBrowse:
                captureState.set(activation: false, directional: true)
                Task { @MainActor in
                    await directionalCoordinator?.handleHotkey(direction: direction, hotkeyTimestamp: .now())
                    syncCaptureStateFromCoordinators()
                }
        }
    }

    private func handleCycleInputCommand(_ command: CycleInputCommand) {
        captureState.set(activation: true, directional: false)

        Task { @MainActor in
            switch command {
                case .move(let direction):
                    Logger.info(.hotkey, "cycle-input=arrow direction=\(direction.rawValue)")
                    await navigationCoordinator?.startOrAdvanceCycle(direction: direction, hotkeyTimestamp: .now())
                case .quitSelectedApp:
                    await navigationCoordinator?.requestQuitSelectedAppInCycle()
                case .closeSelectedWindow:
                    await navigationCoordinator?.requestCloseSelectedWindowInCycle()
            }
            syncCaptureStateFromCoordinators()
        }
    }

    private func handleDirectionalMutationCommand(_ command: CycleInputCommand) {
        captureState.set(activation: false, directional: true)

        Task { @MainActor in
            switch command {
                case .quitSelectedApp:
                    await directionalCoordinator?.requestQuitSelectedAppInSession()
                case .closeSelectedWindow:
                    await directionalCoordinator?.requestCloseSelectedWindowInSession()
                case .move:
                    return
            }
            syncCaptureStateFromCoordinators()
        }
    }

    private func installModifierMonitorIfNeeded() -> Bool {
        guard modifierEventTap == nil else { return true }

        let eventMask = CGEventMask(1 << CGEventType.flagsChanged.rawValue)
        let callback: CGEventTapCallBack = { _, type, event, userInfo in
            guard let userInfo else { return Unmanaged.passUnretained(event) }
            let runtime = Unmanaged<TabRuntime>.fromOpaque(userInfo).takeUnretainedValue()

            if type == .flagsChanged {
                DispatchQueue.main.async {
                    let modifiers = NSEvent.ModifierFlags(rawValue: UInt(event.flags.rawValue))
                    runtime.handleModifierFlagsChanged(modifiers)
                }
            } else if type == .tapDisabledByUserInput || type == .tapDisabledByTimeout {
                if let tap = runtime.modifierEventTap {
                    CGEvent.tapEnable(tap: tap, enable: true)
                }
            }
            return Unmanaged.passUnretained(event)
        }

        modifierEventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: eventMask,
            callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        )

        guard let tap = modifierEventTap else {
            Logger.error(.hotkey, "Failed to install modifier monitor")
            return false
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    private func removeModifierMonitor() {
        guard let tap = modifierEventTap else { return }
        CFMachPortInvalidate(tap)
        modifierEventTap = nil
    }

    private func installArrowKeyMonitorIfNeeded() -> Bool {
        guard arrowKeyEventTap == nil else { return true }

        let eventMask = CGEventMask(1 << CGEventType.keyDown.rawValue)
        let callback: CGEventTapCallBack = { _, type, event, userInfo in
            guard let userInfo else { return Unmanaged.passUnretained(event) }
            let runtime = Unmanaged<TabRuntime>.fromOpaque(userInfo).takeUnretainedValue()

            if type == .keyDown {
                let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
                let flags = NSEvent.ModifierFlags(rawValue: UInt(event.flags.rawValue))

                if runtime.captureState.isActivationActive, flags.contains(.command) {
                    let command = TabRuntime.cycleCommand(keyCode: keyCode, flags: flags)
                    if let command {
                        DispatchQueue.main.async {
                            runtime.handleCycleInputCommand(command)
                        }
                        return nil
                    }
                }

                if runtime.captureState.isDirectionalActive, flags.contains(.command) {
                    let command = TabRuntime.directionalMutationCommand(keyCode: keyCode, flags: flags)
                    if let command {
                        DispatchQueue.main.async {
                            runtime.handleDirectionalMutationCommand(command)
                        }
                        return nil
                    }
                }
            } else if type == .tapDisabledByUserInput || type == .tapDisabledByTimeout {
                if let tap = runtime.arrowKeyEventTap {
                    CGEvent.tapEnable(tap: tap, enable: true)
                }
            }

            return Unmanaged.passUnretained(event)
        }

        arrowKeyEventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        )

        guard let tap = arrowKeyEventTap else {
            Logger.error(.hotkey, "Failed to install arrow key monitor")
            return false
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    private func removeArrowKeyMonitor() {
        guard let tap = arrowKeyEventTap else { return }
        CFMachPortInvalidate(tap)
        arrowKeyEventTap = nil
    }

    private func handleModifierFlagsChanged(_ flags: NSEvent.ModifierFlags) {
        guard let inputSession else { return }
        guard !inputSession.requiredModifiers.isEmpty else { return }

        let current = flags.intersection([.command, .option, .control, .shift])
        if !current.isSuperset(of: inputSession.requiredModifiers) {
            let endedFlow = inputSession.flow
            self.inputSession = nil
            captureState.set(activation: false, directional: false)
            let commitTimestamp = DispatchTime.now()
            Task { @MainActor in
                switch endedFlow {
                    case .activationCycle:
                        await navigationCoordinator?.commitCycleOnModifierRelease(commitTimestamp: commitTimestamp)
                    case .directionalNavigation, .directionalBrowse:
                        await directionalCoordinator?.commitOrEndSessionOnModifierRelease(commitTimestamp: commitTimestamp)
                }
                syncCaptureStateFromCoordinators()
            }
        }
    }

    private func syncCaptureStateFromCoordinators() {
        let activation = navigationCoordinator?.hasActiveCycleSession() ?? false
        let directional = directionalCoordinator?.hasActiveSession() ?? false
        captureState.set(activation: activation, directional: directional)
    }

    static func cycleCommand(keyCode: UInt16, flags: NSEvent.ModifierFlags) -> CycleInputCommand? {
        guard flags.contains(.command) else { return nil }
        switch keyCode {
            case UInt16(kVK_LeftArrow):
                return .move(.left)
            case UInt16(kVK_RightArrow):
                return .move(.right)
            case UInt16(kVK_ANSI_Q):
                return .quitSelectedApp
            case UInt16(kVK_ANSI_W):
                return .closeSelectedWindow
            default:
                return nil
        }
    }

    static func directionalMutationCommand(keyCode: UInt16, flags: NSEvent.ModifierFlags) -> CycleInputCommand? {
        guard flags.contains(.command) else { return nil }
        switch keyCode {
            case UInt16(kVK_ANSI_Q):
                return .quitSelectedApp
            case UInt16(kVK_ANSI_W):
                return .closeSelectedWindow
            default:
                return nil
        }
    }

    private static func eventModifierFlags(fromCarbonModifiers modifiers: UInt32) -> NSEvent.ModifierFlags {
        let cmdMask: UInt32 = 1 << 8
        let shiftMask: UInt32 = 1 << 9
        let optionMask: UInt32 = 1 << 11
        let controlMask: UInt32 = 1 << 12

        var flags: NSEvent.ModifierFlags = []
        if modifiers & cmdMask != 0 { flags.insert(.command) }
        if modifiers & optionMask != 0 { flags.insert(.option) }
        if modifiers & controlMask != 0 { flags.insert(.control) }
        if modifiers & shiftMask != 0 { flags.insert(.shift) }
        return flags
    }
}

private final class SessionCaptureState {
    private let lock = NSLock()
    private var activation = false
    private var directional = false

    var isActivationActive: Bool {
        lock.lock()
        defer { lock.unlock() }
        return activation
    }

    var isDirectionalActive: Bool {
        lock.lock()
        defer { lock.unlock() }
        return directional
    }

    func set(activation: Bool, directional: Bool) {
        lock.lock()
        self.activation = activation
        self.directional = directional
        lock.unlock()
    }
}
