import Carbon
import Foundation

@MainActor
final class CarbonHotkeyRegistrar {
    typealias HotkeyHandler = (Direction, UInt32) -> Void

    private var hotKeyRefs: [Direction: EventHotKeyRef?] = [:]
    private var idToDirection: [UInt32: Direction] = [:]
    private var directionToModifiers: [Direction: UInt32] = [:]
    private var handlerRef: EventHandlerRef?
    private var callback: HotkeyHandler?

    private lazy var eventHandler: EventHandlerUPP = { _, event, userData in
        guard let event, let userData else { return noErr }
        let me = Unmanaged<CarbonHotkeyRegistrar>.fromOpaque(userData).takeUnretainedValue()
        return me.handleHotKeyEvent(event)
    }

    func register(bindings: [Direction: ParsedHotkey], handler: @escaping HotkeyHandler) throws {
        callback = handler
        installEventHandlerIfNeeded()

        unregisterAll()
        idToDirection = [:]
        directionToModifiers = [:]
        Logger.info(.hotkey, "Registering \(bindings.count) hotkeys")

        for (index, direction) in Direction.allCases.enumerated() {
            guard let binding = bindings[direction] else { continue }

            var hotKeyRef: EventHotKeyRef?
            let hotKeyID = EventHotKeyID(signature: Self.signature, id: UInt32(index + 1))

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
                    userInfo: [NSLocalizedDescriptionKey: "Failed to register hotkey for \(direction.rawValue). OSStatus=\(status)"]
                )
            }

            hotKeyRefs[direction] = hotKeyRef
            idToDirection[hotKeyID.id] = direction
            directionToModifiers[direction] = binding.modifiers
            Logger.info(.hotkey, "Registered \(direction.rawValue) (keyCode=\(binding.keyCode), modifiers=\(binding.modifiers))")
        }
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
            Logger.error(.hotkey, "Failed to install Carbon hotkey event handler. OSStatus=\(status)")
        } else {
            Logger.info(.hotkey, "Installed Carbon hotkey event handler")
        }
    }

    private func unregisterAll() {
        if !hotKeyRefs.isEmpty {
            Logger.info(.hotkey, "Unregistering existing hotkeys")
        }
        for (_, ref) in hotKeyRefs {
            if let ref {
                UnregisterEventHotKey(ref)
            }
        }
        hotKeyRefs = [:]
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
            Logger.error(.hotkey, "Failed to read hotkey event payload. OSStatus=\(status)")
            return status
        }

        guard hotKeyID.signature == Self.signature else {
            #if DEBUG
            Logger.info(.hotkey, "Directional registrar pass-through signature=\(hotKeyID.signature)")
            #endif
            return OSStatus(eventNotHandledErr)
        }

        guard let direction = idToDirection[hotKeyID.id] else {
            #if DEBUG
            Logger.info(.hotkey, "Directional registrar pass-through id=\(hotKeyID.id)")
            #endif
            return OSStatus(eventNotHandledErr)
        }

        Logger.info(.hotkey, "Hotkey pressed: \(direction.rawValue)")
        callback?(direction, directionToModifiers[direction] ?? 0)

        return noErr
    }

    private static let signature: OSType = {
        var value: UInt32 = 0
        for byte in "WNDV".utf8 {
            value = (value << 8) + UInt32(byte)
        }
        return OSType(value)
    }()
}
