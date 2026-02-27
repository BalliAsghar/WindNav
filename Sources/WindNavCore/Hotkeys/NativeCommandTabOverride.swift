import Carbon
import Darwin
import Foundation

protocol NativeCommandTabOverrideManaging: AnyObject {
    func apply(for triggerBinding: ParsedHotkey?)
    func restore()
}

protocol SymbolicHotKeyControlling {
    func isSymbolicHotKeyEnabled(_ hotKeyID: Int32) -> Bool?
    @discardableResult
    func setSymbolicHotKeyEnabled(_ hotKeyID: Int32, enabled: Bool) -> Bool
}

final class SkylightSymbolicHotKeyController: SymbolicHotKeyControlling {
    private typealias IsEnabledFn = @convention(c) (Int32) -> Bool
    private typealias SetEnabledFn = @convention(c) (Int32, Bool) -> Int32

    private let handle: UnsafeMutableRawPointer?
    private let isEnabledFn: IsEnabledFn?
    private let setEnabledFn: SetEnabledFn?

    init() {
        handle = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_NOW)
        if let handle {
            let isEnabledSymbol = dlsym(handle, "CGSIsSymbolicHotKeyEnabled")
            let setEnabledSymbol = dlsym(handle, "CGSSetSymbolicHotKeyEnabled")
            isEnabledFn = isEnabledSymbol.map { unsafeBitCast($0, to: IsEnabledFn.self) }
            setEnabledFn = setEnabledSymbol.map { unsafeBitCast($0, to: SetEnabledFn.self) }
        } else {
            isEnabledFn = nil
            setEnabledFn = nil
        }
    }

    deinit {
        if let handle {
            dlclose(handle)
        }
    }

    func isSymbolicHotKeyEnabled(_ hotKeyID: Int32) -> Bool? {
        guard let isEnabledFn else { return nil }
        return isEnabledFn(hotKeyID)
    }

    func setSymbolicHotKeyEnabled(_ hotKeyID: Int32, enabled: Bool) -> Bool {
        guard let setEnabledFn else { return false }
        return setEnabledFn(hotKeyID, enabled) == 0
    }
}

final class NativeCommandTabOverride: NativeCommandTabOverrideManaging {
    private enum SymbolicHotKey {
        static let commandTab: Int32 = 1
        static let commandShiftTab: Int32 = 2
        static let all: [Int32] = [commandTab, commandShiftTab]
    }

    private let controller: SymbolicHotKeyControlling
    private var savedStates: [Int32: Bool] = [:]
    private var isOverriding = false

    init(controller: SymbolicHotKeyControlling = SkylightSymbolicHotKeyController()) {
        self.controller = controller
    }

    func apply(for triggerBinding: ParsedHotkey?) {
        if Self.requiresCommandTabOverride(triggerBinding) {
            enableIfNeeded()
        } else {
            restore()
        }
    }

    func restore() {
        guard isOverriding else { return }

        for hotKeyID in SymbolicHotKey.all {
            guard let previousState = savedStates[hotKeyID] else { continue }
            if !controller.setSymbolicHotKeyEnabled(hotKeyID, enabled: previousState) {
                Logger.error(.hotkey, "Failed to restore native symbolic hotkey id=\(hotKeyID)")
            }
        }

        savedStates = [:]
        isOverriding = false
        Logger.info(.hotkey, "Restored native Command-Tab symbolic hotkeys")
    }

    static func requiresCommandTabOverride(_ triggerBinding: ParsedHotkey?) -> Bool {
        guard let triggerBinding else { return false }
        let commandMask: UInt32 = 1 << 8
        return triggerBinding.keyCode == UInt32(kVK_Tab) && (triggerBinding.modifiers & commandMask) != 0
    }

    private func enableIfNeeded() {
        guard !isOverriding else { return }

        var captured: [Int32: Bool] = [:]
        for hotKeyID in SymbolicHotKey.all {
            guard let current = controller.isSymbolicHotKeyEnabled(hotKeyID) else {
                Logger.error(.hotkey, "Unable to read native symbolic hotkey state id=\(hotKeyID); skipping Command-Tab override")
                return
            }
            captured[hotKeyID] = current
        }

        savedStates = captured
        isOverriding = true

        for hotKeyID in SymbolicHotKey.all {
            if !controller.setSymbolicHotKeyEnabled(hotKeyID, enabled: false) {
                Logger.error(.hotkey, "Failed to disable native symbolic hotkey id=\(hotKeyID)")
            }
        }
        Logger.info(.hotkey, "Disabled native Command-Tab symbolic hotkeys while WindNav is running")
    }
}
