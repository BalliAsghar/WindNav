import CoreGraphics
import Foundation

enum CGSSymbolicHotKey: Int, CaseIterable {
    case commandTab = 1
    case commandShiftTab = 2
}

@_silgen_name("CGSSetSymbolicHotKeyEnabled") @discardableResult
private func CGSSetSymbolicHotKeyEnabled(_ hotKey: CGSSymbolicHotKey.RawValue, _ isEnabled: Bool) -> CGError

public enum SystemHotkeyOverride {
    private static let lock = NSLock()
    private nonisolated(unsafe) static var hasDisabledSystemCmdTab = false
    private nonisolated(unsafe) static var driver: @Sendable (CGSSymbolicHotKey.RawValue, Bool) -> CGError = {
        CGSSetSymbolicHotKeyEnabled($0, $1)
    }

    public static func disableSystemCmdTab() {
        lock.lock()
        defer { lock.unlock() }

        guard !hasDisabledSystemCmdTab else { return }
        _ = driver(CGSSymbolicHotKey.commandTab.rawValue, false)
        _ = driver(CGSSymbolicHotKey.commandShiftTab.rawValue, false)
        hasDisabledSystemCmdTab = true
        Logger.info(.hotkey, "Disabled system Cmd+Tab switcher")
    }

    public static func restoreSystemCmdTab() {
        lock.lock()
        defer { lock.unlock() }

        guard hasDisabledSystemCmdTab else { return }
        _ = driver(CGSSymbolicHotKey.commandTab.rawValue, true)
        _ = driver(CGSSymbolicHotKey.commandShiftTab.rawValue, true)
        hasDisabledSystemCmdTab = false
        Logger.info(.hotkey, "Restored system Cmd+Tab switcher")
    }

    static func _setDriverForTests(_ newDriver: @escaping @Sendable (CGSSymbolicHotKey.RawValue, Bool) -> CGError) {
        lock.lock()
        driver = newDriver
        lock.unlock()
    }

    static func _resetDriverForTests() {
        lock.lock()
        driver = { CGSSetSymbolicHotKeyEnabled($0, $1) }
        hasDisabledSystemCmdTab = false
        lock.unlock()
    }

    static func _isDisabledForTests() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return hasDisabledSystemCmdTab
    }
}
