import AppKit
import Foundation
import WindNavCore

@main
struct WindNavMain {
    static func main() {
        if isRunningFromAppBundle {
            redirectStdoutAndStderr(to: "/tmp/windnav.log")
        }

        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)

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
