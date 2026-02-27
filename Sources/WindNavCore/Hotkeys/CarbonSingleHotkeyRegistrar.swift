import Carbon
import Foundation

@MainActor
final class CarbonSingleHotkeyRegistrar {
    typealias HotkeyHandler = (UInt32) -> Void

    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private var callback: HotkeyHandler?
    private var registeredHotKeyID: UInt32?
    private var registeredModifiers: UInt32 = 0

    private lazy var eventHandler: EventHandlerUPP = { _, event, userData in
        guard let event, let userData else { return noErr }
        let me = Unmanaged<CarbonSingleHotkeyRegistrar>.fromOpaque(userData).takeUnretainedValue()
        return me.handleHotKeyEvent(event)
    }

    func register(binding: ParsedHotkey?, handler: @escaping HotkeyHandler) throws {
        callback = handler
        installEventHandlerIfNeeded()
        unregisterCurrent()

        guard let binding else {
            Logger.info(.hotkey, "HUD trigger hotkey disabled")
            return
        }

        var hotKeyRef: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: Self.signature, id: Self.hotKeyID)
        let status = RegisterEventHotKey(
            binding.keyCode,
            binding.modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )

        guard status == noErr else {
            throw NSError(
                domain: "WindNav.Hotkeys",
                code: Int(status),
                userInfo: [NSLocalizedDescriptionKey: "Failed to register hud-trigger hotkey. OSStatus=\(status)"]
            )
        }

        self.hotKeyRef = hotKeyRef
        registeredHotKeyID = hotKeyID.id
        registeredModifiers = binding.modifiers
        Logger.info(.hotkey, "Registered hud-trigger (keyCode=\(binding.keyCode), modifiers=\(binding.modifiers))")
    }

    private func installEventHandlerIfNeeded() {
        guard handlerRef == nil else { return }

        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            eventHandler,
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &handlerRef
        )

        if status != noErr {
            Logger.error(.hotkey, "Failed to install Carbon hud-trigger event handler. OSStatus=\(status)")
        } else {
            Logger.info(.hotkey, "Installed Carbon hud-trigger event handler")
        }
    }

    private func unregisterCurrent() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
        registeredHotKeyID = nil
        registeredModifiers = 0
    }

    private func handleHotKeyEvent(_ event: EventRef) -> OSStatus {
        var hotKeyID = EventHotKeyID()
        let status = GetEventParameter(
            event,
            EventParamName(kEventParamDirectObject),
            EventParamType(typeEventHotKeyID),
            nil,
            MemoryLayout<EventHotKeyID>.size,
            nil,
            &hotKeyID
        )

        guard status == noErr else {
            Logger.error(.hotkey, "Failed to read hud-trigger hotkey payload. OSStatus=\(status)")
            return status
        }

        guard hotKeyID.signature == Self.signature else {
            #if DEBUG
            Logger.info(.hotkey, "HUD trigger registrar pass-through signature=\(hotKeyID.signature)")
            #endif
            return OSStatus(eventNotHandledErr)
        }

        guard registeredHotKeyID == hotKeyID.id else {
            #if DEBUG
            Logger.info(.hotkey, "HUD trigger registrar pass-through id=\(hotKeyID.id)")
            #endif
            return OSStatus(eventNotHandledErr)
        }

        Logger.info(.hotkey, "Hotkey pressed: hud-trigger")
        callback?(registeredModifiers)
        return noErr
    }

    private static let hotKeyID: UInt32 = 1
    private static let signature: OSType = {
        var value: UInt32 = 0
        for byte in "WNHT".utf8 {
            value = (value << 8) + UInt32(byte)
        }
        return OSType(value)
    }()
}
