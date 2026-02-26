import AppKit
import WindNavCore

@main
struct WindNavMain {
    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)

        let runtime = WindNavRuntime()
        runtime.start()

        app.run()
    }
}
