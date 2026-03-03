import Carbon
import Foundation

protocol HotkeyRegistrar: AnyObject {
    @MainActor
    func register(bindings: [HotkeyAction: ParsedHotkey], handler: @escaping (HotkeyAction, UInt32) -> Void) throws

    @MainActor
    func unregisterAll()
}

@MainActor
final class CarbonHotkeyRegistrar: HotkeyRegistrar {
    private var hotKeyRefs: [HotkeyAction: EventHotKeyRef?] = [:]
    private var idToAction: [UInt32: HotkeyAction] = [:]
    private var actionToModifiers: [HotkeyAction: UInt32] = [:]
    private var handlerRef: EventHandlerRef?
    private var callback: ((HotkeyAction, UInt32) -> Void)?

    private lazy var eventHandler: EventHandlerUPP = { _, event, userData in
        guard let event, let userData else { return noErr }
        let me = Unmanaged<CarbonHotkeyRegistrar>.fromOpaque(userData).takeUnretainedValue()
        return me.handleHotKeyEvent(event)
    }

    func register(bindings: [HotkeyAction: ParsedHotkey], handler: @escaping (HotkeyAction, UInt32) -> Void) throws {
        callback = handler
        installEventHandlerIfNeeded()

        unregisterAll()
        idToAction = [:]
        actionToModifiers = [:]

        for action in HotkeyAction.allCases {
            guard let binding = bindings[action] else { continue }

            var hotKeyRef: EventHotKeyRef?
            let hotKeyID = EventHotKeyID(signature: Self.signature, id: hotkeyID(for: action))
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
                    userInfo: [NSLocalizedDescriptionKey: "Failed to register hotkey for \(action.rawValue). OSStatus=\(status)"]
                )
            }

            hotKeyRefs[action] = hotKeyRef
            idToAction[hotKeyID.id] = action
            actionToModifiers[action] = binding.modifiers
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

    func action(forHotkeyID hotkeyID: UInt32) -> HotkeyAction? {
        idToAction[hotkeyID] ?? Self.action(forHotkeyID: hotkeyID)
    }

    func hotkeyID(for action: HotkeyAction) -> UInt32 {
        Self.hotkeyID(for: action)
    }

    nonisolated static func hotkeyID(for action: HotkeyAction) -> UInt32 {
        UInt32(HotkeyAction.allCases.firstIndex(of: action)! + 1)
    }

    nonisolated static func action(forHotkeyID hotkeyID: UInt32) -> HotkeyAction? {
        guard hotkeyID > 0, hotkeyID <= UInt32(HotkeyAction.allCases.count) else { return nil }
        return HotkeyAction.allCases[Int(hotkeyID - 1)]
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

        if let action = idToAction[hotKeyID.id] {
            callback?(action, actionToModifiers[action] ?? 0)
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
