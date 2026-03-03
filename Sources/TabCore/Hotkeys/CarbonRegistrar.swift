import Carbon
import Foundation

protocol HotkeyRegistrar: AnyObject {
    @MainActor
    func register(bindings: [Direction: ParsedHotkey], handler: @escaping (Direction, UInt32) -> Void) throws

    @MainActor
    func unregisterAll()
}

@MainActor
final class CarbonHotkeyRegistrar: HotkeyRegistrar {
    private var hotKeyRefs: [Direction: EventHotKeyRef?] = [:]
    private var idToDirection: [UInt32: Direction] = [:]
    private var directionToModifiers: [Direction: UInt32] = [:]
    private var handlerRef: EventHandlerRef?
    private var callback: ((Direction, UInt32) -> Void)?

    private lazy var eventHandler: EventHandlerUPP = { _, event, userData in
        guard let event, let userData else { return noErr }
        let me = Unmanaged<CarbonHotkeyRegistrar>.fromOpaque(userData).takeUnretainedValue()
        return me.handleHotKeyEvent(event)
    }

    func register(bindings: [Direction: ParsedHotkey], handler: @escaping (Direction, UInt32) -> Void) throws {
        callback = handler
        installEventHandlerIfNeeded()

        unregisterAll()
        idToDirection = [:]
        directionToModifiers = [:]

        for direction in Direction.allCases {
            guard let binding = bindings[direction] else { continue }

            var hotKeyRef: EventHotKeyRef?
            let hotKeyID = EventHotKeyID(signature: Self.signature, id: hotkeyID(for: direction))
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
                    domain: "TabPlusPlus.Hotkeys",
                    code: Int(status),
                    userInfo: [NSLocalizedDescriptionKey: "Failed to register hotkey for \(direction.rawValue). OSStatus=\(status)"]
                )
            }

            hotKeyRefs[direction] = hotKeyRef
            idToDirection[hotKeyID.id] = direction
            directionToModifiers[direction] = binding.modifiers
        }
    }

    func unregisterAll() {
        for (_, ref) in hotKeyRefs {
            if let ref {
                UnregisterEventHotKey(ref)
            }
        }
        hotKeyRefs = [:]
    }

    func direction(forHotkeyID hotkeyID: UInt32) -> Direction? {
        idToDirection[hotkeyID] ?? Self.direction(forHotkeyID: hotkeyID)
    }

    func hotkeyID(for direction: Direction) -> UInt32 {
        Self.hotkeyID(for: direction)
    }

    nonisolated static func hotkeyID(for direction: Direction) -> UInt32 {
        UInt32(Direction.allCases.firstIndex(of: direction)! + 1)
    }

    nonisolated static func direction(forHotkeyID hotkeyID: UInt32) -> Direction? {
        guard hotkeyID > 0, hotkeyID <= UInt32(Direction.allCases.count) else { return nil }
        return Direction.allCases[Int(hotkeyID - 1)]
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
            Logger.error(.hotkey, "Failed to install Carbon event handler: OSStatus=\(status)")
        }
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
            Logger.error(.hotkey, "Failed to decode hotkey event payload: OSStatus=\(status)")
            return status
        }

        if let direction = idToDirection[hotKeyID.id] {
            callback?(direction, directionToModifiers[direction] ?? 0)
        }

        return noErr
    }

    private static let signature: OSType = {
        var value: UInt32 = 0
        for byte in "TAPP".utf8 {
            value = (value << 8) + UInt32(byte)
        }
        return OSType(value)
    }()
}
