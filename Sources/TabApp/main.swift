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
    var settingsStore: FileSettingsStateStore?
    var menuController: MenuBarSettingsController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard let runtime, let settingsStore else { return }
        do {
            menuController = try MenuBarSettingsController(runtime: runtime, settingsStore: settingsStore)
        } catch {
            Logger.error(.runtime, "Failed to create menu bar controller: \(error.localizedDescription)")
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        runtime?.stop()
        SystemHotkeyOverride.restoreSystemCmdTab()
    }
}

private var appDelegate: TabAppDelegate?

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
let settingsStore = FileSettingsStateStore()
private let delegate = TabAppDelegate()
delegate.runtime = runtime
delegate.settingsStore = settingsStore
appDelegate = delegate
app.delegate = delegate

runtime.start()
app.run()
