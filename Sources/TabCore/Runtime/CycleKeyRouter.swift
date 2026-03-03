import AppKit
import Carbon
import Foundation

enum CycleInputCommand: Equatable {
    case move(Direction)
    case quitSelectedApp
}

enum CycleKeyRouter {
    static func routeCommand(
        keyCode: UInt16,
        flags: NSEvent.ModifierFlags,
        cycleActive: Bool
    ) -> CycleInputCommand? {
        guard cycleActive else { return nil }
        guard flags.contains(.command) else { return nil }

        switch keyCode {
            case UInt16(kVK_LeftArrow):
                return .move(.left)
            case UInt16(kVK_RightArrow):
                return .move(.right)
            case UInt16(kVK_ANSI_Q):
                return .quitSelectedApp
            default:
                return nil
        }
    }
}
