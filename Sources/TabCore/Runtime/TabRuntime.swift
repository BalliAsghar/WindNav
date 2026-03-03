import AppKit
import Foundation

@MainActor
public final class TabRuntime {
    private let configLoader: ConfigLoader
    private let hotkeys: any HotkeyRegistrar
    private let windowProvider: AXWindowProvider
    private let focusPerformer: FocusPerformer
    private let hudController: any HUDControlling

    private var navigationCoordinator: NavigationCoordinator?
    private var modifierEventTap: CFMachPort?
    private var arrowKeyEventTap: CFMachPort?
    private var config: TabConfig?
    private var inputSession: InputSession?
    nonisolated(unsafe) private let cycleCaptureState = CycleCaptureState()

    public convenience init(configURL: URL? = nil) {
        self.init(
            configLoader: ConfigLoader(configURL: configURL ?? ConfigLoader.defaultConfigURL()),
            hotkeys: CarbonHotkeyRegistrar(),
            windowProvider: AXWindowProvider(),
            focusPerformer: AXFocusPerformer(),
            hudController: MinimalHUDController()
        )
    }

    init(
        configLoader: ConfigLoader,
        hotkeys: any HotkeyRegistrar,
        windowProvider: AXWindowProvider,
        focusPerformer: FocusPerformer,
        hudController: any HUDControlling
    ) {
        self.configLoader = configLoader
        self.hotkeys = hotkeys
        self.windowProvider = windowProvider
        self.focusPerformer = focusPerformer
        self.hudController = hudController
    }

    public func start() {
        Logger.configure(level: .info, colorMode: .auto)
        Logger.info(.runtime, "Starting Tab++ runtime")

        do {
            let loaded = try configLoader.loadOrCreate()
            config = loaded
            Logger.configure(level: loaded.performance.logLevel, colorMode: loaded.performance.logColor)
            Logger.info(.config, "Loaded config at \(configLoader.configURL.path)")

            guard AXPermission.ensureTrusted(prompt: true) else {
                Logger.error(.runtime, "Accessibility permission is required")
                NSApp.terminate(nil)
                return
            }

            windowProvider.updateConfig(loaded)
            navigationCoordinator = NavigationCoordinator(
                windowProvider: windowProvider,
                focusedWindowProvider: windowProvider,
                focusPerformer: focusPerformer,
                hudController: hudController,
                config: loaded
            )

            if loaded.activation.overrideSystemCmdTab {
                SystemHotkeyOverride.disableSystemCmdTab()
            }

            let bindings = try parseActivationBindings(loaded.activation)
            try hotkeys.register(bindings: bindings) { [weak self] direction, carbonModifiers in
                guard let self else { return }
                self.handleHotkey(direction, carbonModifiers: carbonModifiers)
            }
            installModifierMonitorIfNeeded()
            installArrowKeyMonitorIfNeeded()
            Logger.info(.runtime, "Tab++ runtime started")
        } catch {
            Logger.error(.runtime, "Failed to start runtime: \(error.localizedDescription)")
            NSApp.terminate(nil)
        }
    }

    public func stop() {
        navigationCoordinator?.cancelCycleSession()
        cycleCaptureState.setActive(false)
        inputSession = nil
        removeModifierMonitor()
        removeArrowKeyMonitor()
        hotkeys.unregisterAll()
        SystemHotkeyOverride.restoreSystemCmdTab()
        Logger.info(.runtime, "Tab++ runtime stopped")
    }

    private func parseActivationBindings(_ activation: ActivationConfig) throws -> [Direction: ParsedHotkey] {
        [
            .right: try HotkeyParser.parse(activation.trigger),
            .left: try HotkeyParser.parse(activation.reverseTrigger),
        ]
    }

    private func handleHotkey(_ direction: Direction, carbonModifiers: UInt32) {
        if inputSession == nil {
            var required = Self.eventModifierFlags(fromCarbonModifiers: carbonModifiers)
            if required.contains(.command), direction == .left || direction == .right {
                required = [.command]
            }
            inputSession = InputSession(requiredModifiers: required)
        }
        cycleCaptureState.setActive(true)

        Task { @MainActor in
            await navigationCoordinator?.startOrAdvanceCycle(direction: direction, hotkeyTimestamp: DispatchTime.now())
            cycleCaptureState.setActive(navigationCoordinator?.hasActiveCycleSession() ?? false)
        }
    }

    private func handleArrowCycleInput(_ direction: Direction) {
        Logger.info(.hotkey, "cycle-input=arrow direction=\(direction.rawValue)")
        cycleCaptureState.setActive(true)
        Task { @MainActor in
            await navigationCoordinator?.startOrAdvanceCycle(direction: direction, hotkeyTimestamp: DispatchTime.now())
            cycleCaptureState.setActive(navigationCoordinator?.hasActiveCycleSession() ?? false)
        }
    }

    private func installModifierMonitorIfNeeded() {
        guard modifierEventTap == nil else { return }

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
            return
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    private func removeModifierMonitor() {
        guard let tap = modifierEventTap else { return }
        CFMachPortInvalidate(tap)
        modifierEventTap = nil
    }

    private func installArrowKeyMonitorIfNeeded() {
        guard arrowKeyEventTap == nil else { return }

        let eventMask = CGEventMask(1 << CGEventType.keyDown.rawValue)
        let callback: CGEventTapCallBack = { _, type, event, userInfo in
            guard let userInfo else { return Unmanaged.passUnretained(event) }
            let runtime = Unmanaged<TabRuntime>.fromOpaque(userInfo).takeUnretainedValue()

            if type == .keyDown {
                let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
                let flags = NSEvent.ModifierFlags(rawValue: UInt(event.flags.rawValue))
                if let direction = CycleKeyRouter.routeDirection(
                    keyCode: keyCode,
                    flags: flags,
                    cycleActive: runtime.cycleCaptureState.isActive
                ) {
                    DispatchQueue.main.async {
                        runtime.handleArrowCycleInput(direction)
                    }
                    return nil
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
            return
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
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
            self.inputSession = nil
            cycleCaptureState.setActive(false)
            let commitTimestamp = DispatchTime.now()
            Task { @MainActor in
                await navigationCoordinator?.commitCycleOnModifierRelease(commitTimestamp: commitTimestamp)
            }
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

private struct InputSession {
    let requiredModifiers: NSEvent.ModifierFlags
}

private final class CycleCaptureState {
    private let lock = NSLock()
    private var active = false

    var isActive: Bool {
        lock.lock()
        defer { lock.unlock() }
        return active
    }

    func setActive(_ newValue: Bool) {
        lock.lock()
        active = newValue
        lock.unlock()
    }
}
