import AppKit
import Carbon
import Foundation

enum CycleKeyRouter {
    static func routeDirection(
        keyCode: UInt16,
        flags: NSEvent.ModifierFlags,
        cycleActive: Bool
    ) -> Direction? {
        guard cycleActive else { return nil }
        guard flags.contains(.command) else { return nil }

        switch keyCode {
            case UInt16(kVK_LeftArrow):
                return .left
            case UInt16(kVK_RightArrow):
                return .right
            default:
                return nil
        }
    }
}
