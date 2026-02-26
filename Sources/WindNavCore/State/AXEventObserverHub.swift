import AppKit
import ApplicationServices
import Foundation

@MainActor
final class AXEventObserverHub {
    var onEvent: (() -> Void)?

    private var appObservers: [pid_t: AppObserverState] = [:]
    private var workspaceTokens: [NSObjectProtocol] = []

    func start() {
        Logger.info(.observer, "Starting observer hub")
        stop()
        subscribeWorkspaceNotifications()
        rebuildObservers()
    }

    func stop() {
        if !workspaceTokens.isEmpty || !appObservers.isEmpty {
            Logger.info(.observer, "Stopping observer hub")
        }
        for token in workspaceTokens {
            NSWorkspace.shared.notificationCenter.removeObserver(token)
        }
        workspaceTokens = []

        for pid in appObservers.keys {
            removeObserver(for: pid)
        }
        appObservers = [:]
    }

    private func subscribeWorkspaceNotifications() {
        let nc = NSWorkspace.shared.notificationCenter
        let names: [Notification.Name] = [
            NSWorkspace.didLaunchApplicationNotification,
            NSWorkspace.didTerminateApplicationNotification,
            NSWorkspace.didHideApplicationNotification,
            NSWorkspace.didUnhideApplicationNotification,
            NSWorkspace.didActivateApplicationNotification,
        ]

        workspaceTokens = names.map { name in
            nc.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    Logger.info(.observer, "Workspace notification: \(name.rawValue)")
                    self.rebuildObservers()
                    self.emitEvent()
                }
            }
        }
    }

    private func rebuildObservers() {
        let runningApps = NSWorkspace.shared.runningApplications.filter {
            $0.activationPolicy == .regular &&
                !$0.isTerminated &&
                $0.processIdentifier != getpid()
        }

        let expected = Set(runningApps.map(\.processIdentifier))

        let stale = appObservers.keys.filter { !expected.contains($0) }
        for pid in stale {
            removeObserver(for: pid)
        }

        for app in runningApps where appObservers[app.processIdentifier] == nil {
            addObserver(for: app)
        }

        syncWindowSubscriptionsForAll()
        Logger.info(.observer, "Observer hub active apps=\(appObservers.count)")
    }

    private func addObserver(for app: NSRunningApplication) {
        var observer: AXObserver?
        let status = AXObserverCreate(app.processIdentifier, Self.axObserverCallback, &observer)
        guard status == .success, let observer else {
            Logger.error(.observer, "Failed to create AXObserver for pid=\(app.processIdentifier), status=\(status.rawValue)")
            return
        }

        let appElement = AXUIElementCreateApplication(app.processIdentifier)

        let appNotifications: [String] = [
            kAXWindowCreatedNotification as String,
            kAXFocusedWindowChangedNotification as String,
            kAXWindowMiniaturizedNotification as String,
            kAXWindowDeminiaturizedNotification as String,
            kAXMovedNotification as String,
            kAXResizedNotification as String,
            kAXUIElementDestroyedNotification as String,
        ]

        let refcon = Unmanaged.passUnretained(self).toOpaque()
        for key in appNotifications {
            _ = AXObserverAddNotification(observer, appElement, key as CFString, refcon)
        }

        let source = AXObserverGetRunLoopSource(observer)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)

        appObservers[app.processIdentifier] = AppObserverState(
            app: app,
            observer: observer,
            appElement: appElement,
            subscribedWindowElements: [:]
        )
        Logger.info(.observer, "Added AX observer for pid=\(app.processIdentifier) app=\(app.localizedName ?? "Unknown")")
    }

    private func removeObserver(for pid: pid_t) {
        guard let state = appObservers.removeValue(forKey: pid) else {
            return
        }

        for key in Self.appNotifications {
            _ = AXObserverRemoveNotification(state.observer, state.appElement, key as CFString)
        }

        for (_, windowElement) in state.subscribedWindowElements {
            for key in Self.windowNotifications {
                _ = AXObserverRemoveNotification(state.observer, windowElement, key as CFString)
            }
        }

        CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(state.observer), .defaultMode)
        Logger.info(.observer, "Removed AX observer for pid=\(pid)")
    }

    private func syncWindowSubscriptionsForAll() {
        for pid in appObservers.keys {
            syncWindowSubscriptions(for: pid)
        }
    }

    private func syncWindowSubscriptions(for pid: pid_t) {
        guard var state = appObservers[pid] else { return }

        let currentElements = windowElements(for: state.appElement)
        let currentIDs = Set(currentElements.keys)
        let knownIDs = Set(state.subscribedWindowElements.keys)

        let newIDs = currentIDs.subtracting(knownIDs)
        let removedIDs = knownIDs.subtracting(currentIDs)

        let refcon = Unmanaged.passUnretained(self).toOpaque()

        for id in newIDs {
            guard let element = currentElements[id] else { continue }
            for key in Self.windowNotifications {
                _ = AXObserverAddNotification(state.observer, element, key as CFString, refcon)
            }
            state.subscribedWindowElements[id] = element
        }

        for id in removedIDs {
            guard let element = state.subscribedWindowElements[id] else { continue }
            for key in Self.windowNotifications {
                _ = AXObserverRemoveNotification(state.observer, element, key as CFString)
            }
            state.subscribedWindowElements.removeValue(forKey: id)
        }

        appObservers[pid] = state
        if !newIDs.isEmpty || !removedIDs.isEmpty {
            Logger.info(.observer, "Window subscriptions updated for pid=\(pid) +\(newIDs.count) -\(removedIDs.count)")
        }
    }

    private func windowElements(for appElement: AXUIElement) -> [UInt32: AXUIElement] {
        guard let rawWindows = appElement.windNavCopyAttribute(kAXWindowsAttribute as String) as? [AnyObject] else {
            return [:]
        }

        var result: [UInt32: AXUIElement] = [:]
        for raw in rawWindows {
            let element = raw as! AXUIElement
            guard let id = element.windNavWindowID() else { continue }
            result[id] = element
        }

        return result
    }

    private func handleAXEvent() {
        syncWindowSubscriptionsForAll()
        emitEvent()
    }

    private func emitEvent() {
        onEvent?()
    }

    private static let axObserverCallback: AXObserverCallback = { _, _, _, refcon in
        guard let refcon else { return }
        let hub = Unmanaged<AXEventObserverHub>.fromOpaque(refcon).takeUnretainedValue()
        hub.handleAXEvent()
    }

    private static let appNotifications: [String] = [
        kAXWindowCreatedNotification as String,
        kAXFocusedWindowChangedNotification as String,
        kAXWindowMiniaturizedNotification as String,
        kAXWindowDeminiaturizedNotification as String,
        kAXMovedNotification as String,
        kAXResizedNotification as String,
        kAXUIElementDestroyedNotification as String,
    ]

    private static let windowNotifications: [String] = [
        kAXUIElementDestroyedNotification as String,
        kAXWindowMiniaturizedNotification as String,
        kAXWindowDeminiaturizedNotification as String,
        kAXMovedNotification as String,
        kAXResizedNotification as String,
    ]
}

private struct AppObserverState {
    let app: NSRunningApplication
    let observer: AXObserver
    let appElement: AXUIElement
    var subscribedWindowElements: [UInt32: AXUIElement]
}
