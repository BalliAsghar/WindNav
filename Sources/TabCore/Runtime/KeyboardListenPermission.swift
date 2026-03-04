import AppKit
import CoreGraphics
import Foundation

struct KeyboardListenAccessEvaluator {
    let preflight: () -> Bool
    let request: () -> Bool

    func ensureAccess(prompt: Bool) -> Bool {
        if preflight() {
            return true
        }
        if prompt {
            _ = request()
        }
        return preflight()
    }

    @MainActor
    static let live = KeyboardListenAccessEvaluator(
        preflight: { CGPreflightListenEventAccess() },
        request: { CGRequestListenEventAccess() }
    )
}

@MainActor
enum KeyboardListenPermission {
    static func ensureAccess(prompt: Bool = true) -> Bool {
        KeyboardListenAccessEvaluator.live.ensureAccess(prompt: prompt)
    }
}
