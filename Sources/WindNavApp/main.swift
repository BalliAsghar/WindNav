import AppKit
import Foundation
import Darwin
import WindNavCore

// MARK: - Emergency Exit Handlers

private func emergencyExit(_ logs: Any?...) {
    SystemHotkeyOverride.restoreSystemCmdTab()
    print("EMERGENCY EXIT:", logs)
    Thread.callStackSymbols.forEach { print($0) }
    exit(0)
}

// MARK: - Application Delegate

@MainActor
private final class WindNavAppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillTerminate(_ notification: Notification) {
        SystemHotkeyOverride.restoreSystemCmdTab()
    }
}

// MARK: - Main Entry Point

@main
struct WindNavMain {
    @MainActor
    fileprivate static var appDelegate: WindNavAppDelegate?
    
    static func main() {
        // If the app is quit/force-quit from Activity Monitor, it receives SIGTERM and applicationWillTerminate won't be called
        // If the app crashes in Swift code (e.g. unexpected nil), SIGTRAP is sent
        // SIGKILL cannot be intercepted
        [SIGTERM, SIGTRAP, SIGINT, SIGHUP].forEach {
            signal($0) { signal in
                emergencyExit("Exiting after receiving signal", signal)
            }
        }
        
        // If the app crashes in Objective-C code, an NSException may be sent
        NSSetUncaughtExceptionHandler { exception in
            emergencyExit("Exiting after receiving uncaught NSException", exception)
        }
        
        if isRunningFromAppBundle {
            redirectStdoutAndStderr(to: "/tmp/windnav.log")
        }

        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        appDelegate = WindNavAppDelegate()
        app.delegate = appDelegate

        let runtime = WindNavRuntime()
        runtime.start()

        app.run()
    }
}

private var isRunningFromAppBundle: Bool {
    Bundle.main.bundlePath.hasSuffix(".app")
}

private func redirectStdoutAndStderr(to path: String) {
    let flags = O_CREAT | O_WRONLY | O_APPEND
    let fd = open(path, flags, S_IRUSR | S_IWUSR | S_IRGRP | S_IROTH)
    guard fd >= 0 else { return }
    _ = dup2(fd, STDOUT_FILENO)
    _ = dup2(fd, STDERR_FILENO)
    close(fd)
}
