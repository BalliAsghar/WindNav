import ApplicationServices
import Foundation

@_silgen_name("_AXUIElementGetWindow")
private func _AXUIElementGetWindow(_ element: AXUIElement, _ identifier: UnsafeMutablePointer<CGWindowID>) -> AXError

extension AXUIElement {
    func windNavWindowID() -> UInt32? {
        var id: CGWindowID = 0
        return _AXUIElementGetWindow(self, &id) == .success ? UInt32(id) : nil
    }

    func windNavCopyAttribute(_ key: String) -> AnyObject? {
        var raw: AnyObject?
        return AXUIElementCopyAttributeValue(self, key as CFString, &raw) == .success ? raw : nil
    }

    func windNavSetAttribute(_ key: String, _ value: CFTypeRef) -> Bool {
        AXUIElementSetAttributeValue(self, key as CFString, value) == .success
    }
}

enum AXPermission {
    @MainActor
    static func ensureTrusted(prompt: Bool = true) -> Bool {
        let options: [String: Bool] = ["AXTrustedCheckOptionPrompt": prompt]
        return AXIsProcessTrustedWithOptions(options as CFDictionary)
    }
}
