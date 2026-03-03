import AppKit
import Darwin
import Foundation
import TabCore

private func emergencyExit(_ logs: Any?...) {
    SystemHotkeyOverride.restoreSystemCmdTab()
    print("EMERGENCY EXIT:", logs)
    exit(0)
}

@MainActor
private final class TabAppDelegate: NSObject, NSApplicationDelegate {
    var runtime: TabRuntime?

    func applicationWillTerminate(_ notification: Notification) {
        runtime?.stop()
        SystemHotkeyOverride.restoreSystemCmdTab()
    }
}

@main
struct TabMain {
    @MainActor
    fileprivate static var appDelegate: TabAppDelegate?

    static func main() {
        [SIGTERM, SIGTRAP, SIGINT, SIGHUP].forEach {
            signal($0) { signal in
                emergencyExit("Received signal", signal)
            }
        }

        NSSetUncaughtExceptionHandler { exception in
            emergencyExit("Uncaught NSException", exception)
        }

        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)

        let runtime = TabRuntime()
        let delegate = TabAppDelegate()
        delegate.runtime = runtime
        appDelegate = delegate
        app.delegate = delegate

        runtime.start()
        app.run()
    }
}
