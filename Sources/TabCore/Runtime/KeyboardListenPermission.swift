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

    static func presentMissingAccessAlert() {
        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = "Input Monitoring Permission Required"
        alert.informativeText =
            "WindNav needs Input Monitoring to detect modifier release and arrow keys during Cmd+Tab. " +
            "Without this permission, app switching can get stuck."
        alert.addButton(withTitle: "Open Settings")
        alert.addButton(withTitle: "Quit")

        let response = alert.runModal()
        guard response == .alertFirstButtonReturn else { return }
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent") else { return }
        NSWorkspace.shared.open(url)
    }
}
