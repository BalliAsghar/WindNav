import Foundation
import CoreGraphics

// MARK: - SkyLight Private API
// Source: https://github.com/lwouis/alt-tab-macos
// SkyLight.framework is a private framework that provides low-level window management APIs

enum CGSSymbolicHotKey: Int, CaseIterable {
    case commandTab = 1
    case commandShiftTab = 2
    case commandKeyAboveTab = 6
}

/// Enables/disables a symbolic hotkey. These are system shortcuts such as Cmd+Tab or Spotlight.
/// It is possible to find all the existing hotkey IDs by using CGSGetSymbolicHotKeyValue on the first few hundred numbers.
/// WARNING: The effect of enabling/disabling persists after the app is quit!
@_silgen_name("CGSSetSymbolicHotKeyEnabled") @discardableResult
func CGSSetSymbolicHotKeyEnabled(_ hotKey: CGSSymbolicHotKey.RawValue, _ isEnabled: Bool) -> CGError

// MARK: - System Hotkey Override

public enum SystemHotkeyOverride {
    private static let lock = NSLock()
    private nonisolated(unsafe) static var hasDisabledSystemCmdTab = false
    
    /// Disables the macOS built-in Cmd+Tab and Cmd+Shift+Tab app switcher.
    /// CRITICAL: Must call restoreSystemCmdTab() before app terminates!
    /// Thread-safe: Can be called from any thread.
    public static func disableSystemCmdTab() {
        lock.lock()
        defer { lock.unlock() }
        
        guard !hasDisabledSystemCmdTab else { return }
        
        CGSSetSymbolicHotKeyEnabled(CGSSymbolicHotKey.commandTab.rawValue, false)
        CGSSetSymbolicHotKeyEnabled(CGSSymbolicHotKey.commandShiftTab.rawValue, false)
        
        hasDisabledSystemCmdTab = true
        Logger.info(.hotkey, "Disabled system Cmd+Tab switcher (symbolic hotkeys 1, 2)")
    }
    
    /// Restores the macOS built-in Cmd+Tab and Cmd+Shift+Tab app switcher.
    /// Safe to call multiple times (idempotent).
    /// Thread-safe: Can be called from any thread, including signal handlers.
    public static func restoreSystemCmdTab() {
        lock.lock()
        defer { lock.unlock() }
        
        guard hasDisabledSystemCmdTab else { return }
        
        CGSSetSymbolicHotKeyEnabled(CGSSymbolicHotKey.commandTab.rawValue, true)
        CGSSetSymbolicHotKeyEnabled(CGSSymbolicHotKey.commandShiftTab.rawValue, true)
        
        hasDisabledSystemCmdTab = false
        Logger.info(.hotkey, "Restored system Cmd+Tab switcher (symbolic hotkeys 1, 2)")
    }
}
