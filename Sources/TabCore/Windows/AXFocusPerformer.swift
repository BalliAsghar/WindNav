import AppKit
import ApplicationServices
import Foundation

protocol FocusPerformer: AnyObject {
    @MainActor
    func focus(_ target: WindowSnapshot) async throws
}

@MainActor
final class AXFocusPerformer: FocusPerformer {
    private let activationService: AppActivationServicing
    private let windowResolver: FocusWindowResolving

    init(
        activationService: AppActivationServicing = NSWorkspaceAppActivationService(),
        windowResolver: FocusWindowResolving = AXFocusWindowResolver()
    ) {
        self.activationService = activationService
        self.windowResolver = windowResolver
    }

    func focus(_ target: WindowSnapshot) async throws {
        guard let app = activationService.runningApplication(processIdentifier: target.pid) else { return }

        unhideIfNeeded(app)

        if SyntheticWindowID.matches(windowId: target.windowId, pid: target.pid) {
            let activated = activate(app, target: target, reason: "synthetic")
            openWindowlessAppIfNeeded(app, target: target, activated: activated)
            return
        }

        if target.isFullscreen {
            _ = activate(app, target: target, reason: "fullscreen-pre-raise")
        }

        guard let window = windowResolver.windowElement(windowId: target.windowId, pid: target.pid) else {
            _ = activate(app, target: target, reason: "missing-ax-window")
            return
        }

        if window.isMinimized == true {
            window.setMinimized(false)
        }

        window.setMain()
        window.raise()
        _ = activate(
            app,
            target: target,
            reason: target.isFullscreen ? "fullscreen-post-raise" : "window-post-raise"
        )
    }

    private func unhideIfNeeded(_ app: RunningApplicationControlling) {
        guard app.isHidden else { return }
        let unhidden = app.unhide()
        Logger.debug(.navigation, "focus-unhide pid=\(app.processIdentifier) result=\(unhidden)")
    }

    @discardableResult
    private func activate(
        _ app: RunningApplicationControlling,
        target: WindowSnapshot,
        reason: String
    ) -> Bool {
        let options: NSApplication.ActivationOptions = [.activateAllWindows, .activateIgnoringOtherApps]
        let activated = app.activate(options: options)
        let frontmostPID = activationService.frontmostPID.map(String.init) ?? "nil"
        Logger.info(
            .navigation,
            "focus-activate reason=\(reason) pid=\(target.pid) window=\(target.windowId) fullscreen=\(target.isFullscreen) synthetic=\(SyntheticWindowID.matches(windowId: target.windowId, pid: target.pid)) windowless=\(target.isWindowlessApp) result=\(activated) frontmost-pid=\(frontmostPID)"
        )
        return activated
    }

    private func openWindowlessAppIfNeeded(
        _ app: RunningApplicationControlling,
        target: WindowSnapshot,
        activated: Bool
    ) {
        guard target.isWindowlessApp else { return }
        guard activationService.frontmostPID != app.processIdentifier else { return }
        guard let bundleURL = app.bundleURL else { return }

        Logger.info(
            .navigation,
            "focus-open-windowless-fallback pid=\(target.pid) activated=\(activated) bundle=\(bundleURL.path)"
        )
        activationService.openApplication(at: bundleURL)
    }
}

@MainActor
protocol RunningApplicationControlling: AnyObject {
    var processIdentifier: pid_t { get }
    var isHidden: Bool { get }
    var bundleURL: URL? { get }

    func unhide() -> Bool
    func activate(options: NSApplication.ActivationOptions) -> Bool
}

extension NSRunningApplication: RunningApplicationControlling {}

@MainActor
protocol AppActivationServicing {
    var frontmostPID: pid_t? { get }

    func runningApplication(processIdentifier: pid_t) -> RunningApplicationControlling?
    func openApplication(at bundleURL: URL)
}

@MainActor
struct NSWorkspaceAppActivationService: AppActivationServicing {
    var frontmostPID: pid_t? {
        NSWorkspace.shared.frontmostApplication?.processIdentifier
    }

    func runningApplication(processIdentifier: pid_t) -> RunningApplicationControlling? {
        NSRunningApplication(processIdentifier: processIdentifier)
    }

    func openApplication(at bundleURL: URL) {
        NSWorkspace.shared.openApplication(
            at: bundleURL,
            configuration: NSWorkspace.OpenConfiguration()
        ) { _, error in
            if let error {
                Logger.error(.navigation, "focus-open-windowless-fallback failed: \(error.localizedDescription)")
            }
        }
    }
}

@MainActor
protocol FocusWindowElement: AnyObject {
    var isMinimized: Bool? { get }

    func setMinimized(_ minimized: Bool)
    func setMain()
    func raise()
}

@MainActor
protocol FocusWindowResolving {
    func windowElement(windowId: UInt32, pid: pid_t) -> FocusWindowElement?
}

@MainActor
private final class AXFocusWindowElement: FocusWindowElement {
    private let element: AXUIElement

    init(element: AXUIElement) {
        self.element = element
    }

    var isMinimized: Bool? {
        element.tabCopyAttribute(kAXMinimizedAttribute as String) as? Bool
    }

    func setMinimized(_ minimized: Bool) {
        _ = element.tabSetAttribute(kAXMinimizedAttribute as String, minimized ? kCFBooleanTrue : kCFBooleanFalse)
    }

    func setMain() {
        _ = element.tabSetAttribute(kAXMainAttribute as String, kCFBooleanTrue)
    }

    func raise() {
        _ = AXUIElementPerformAction(element, kAXRaiseAction as CFString)
    }
}

@MainActor
private struct AXFocusWindowResolver: FocusWindowResolving {
    func windowElement(windowId: UInt32, pid: pid_t) -> FocusWindowElement? {
        let appElement = AXUIElementCreateApplication(pid)
        guard let windows = appElement.tabCopyAttribute(kAXWindowsAttribute as String) as? [AnyObject] else {
            return nil
        }

        for raw in windows {
            let window = raw as! AXUIElement
            if window.tabWindowID() == windowId {
                return AXFocusWindowElement(element: window)
            }
        }
        return nil
    }
}
