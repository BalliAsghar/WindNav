import Foundation

enum HotkeyAction: String, CaseIterable, Sendable {
    case activationForward = "activation-forward"
    case directionalLeft = "directional-left"
    case directionalRight = "directional-right"
    case directionalBrowseUp = "directional-browse-up"
    case directionalBrowseDown = "directional-browse-down"
}
