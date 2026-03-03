import Foundation

public enum Direction: String, CaseIterable, Sendable {
    case left
    case right
    case up
    case down
    case windowUp = "window-up"
    case windowDown = "window-down"
}
