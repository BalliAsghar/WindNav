import AppKit
import Foundation
import SwiftUI
import TabCore

@MainActor
final class MenuBarSettingsController: NSObject, NSPopoverDelegate {
    private let statusItem: NSStatusItem
    private let popover = NSPopover()
    private let viewModel: MenuBarViewModel

    private var localClickMonitor: Any?
    private var globalClickMonitor: Any?

    init(runtime: TabRuntime, settingsStore: FileSettingsStateStore) throws {
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let alertPresenter = AppKitMenuBarAlertPresenter()
        self.viewModel = try MenuBarViewModel(
            runtime: runtime,
            settingsStore: settingsStore,
            alertPresenter: alertPresenter
        )
        super.init()

        configureStatusButton()
        configurePopover()
        viewModel.presentOnboardingIfNeeded(appIcon: loadAppIcon())
    }

    func popoverDidClose(_ notification: Notification) {
        removeEventMonitors()
    }

    @objc private func togglePopover(_ sender: Any?) {
        if popover.isShown {
            closePopover(sender)
        } else {
            showPopover()
        }
    }

    private func configureStatusButton() {
        guard let button = statusItem.button else { return }
        button.title = ""
        button.image = loadMenuBarIcon()
            ?? NSImage(
                systemSymbolName: "rectangle.stack.fill",
                accessibilityDescription: "WindNav"
            )
        button.imageScaling = .scaleProportionallyDown
        button.target = self
        button.action = #selector(togglePopover(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    private func configurePopover() {
        popover.animates = false
        popover.behavior = .applicationDefined
        popover.delegate = self
        popover.contentViewController = NSHostingController(
            rootView: MenuBarPanelView(viewModel: viewModel)
        )
    }

    private func showPopover() {
        guard let button = statusItem.button else { return }

        NSApp.activate(ignoringOtherApps: true)
        viewModel.refreshFromDiskIfPossible()
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
        startEventMonitors()
    }

    private func closePopover(_ sender: Any?) {
        popover.performClose(sender)
    }

    private func startEventMonitors() {
        guard localClickMonitor == nil, globalClickMonitor == nil else { return }

        localClickMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] event in
            guard let self else { return event }
            guard self.popover.isShown else { return event }
            if self.isEventOnStatusItemButton(event) || self.isEventInsidePopover(event) {
                return event
            }
            self.closePopover(nil)
            return event
        }

        globalClickMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] _ in
            DispatchQueue.main.async {
                guard let self else { return }
                guard self.popover.isShown else { return }
                self.closePopover(nil)
            }
        }
    }

    private func removeEventMonitors() {
        if let localClickMonitor {
            NSEvent.removeMonitor(localClickMonitor)
            self.localClickMonitor = nil
        }
        if let globalClickMonitor {
            NSEvent.removeMonitor(globalClickMonitor)
            self.globalClickMonitor = nil
        }
    }

    private func isEventInsidePopover(_ event: NSEvent) -> Bool {
        guard let popoverWindow = popover.contentViewController?.view.window else { return false }
        return event.window === popoverWindow
    }

    private func isEventOnStatusItemButton(_ event: NSEvent) -> Bool {
        guard let button = statusItem.button else { return false }
        return event.window === button.window
    }

    private func projectRootURL() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func loadMenuBarIcon() -> NSImage? {
        let iconURL = projectRootURL().appendingPathComponent("Packaging/WindNav-MenuBar.svg")
        guard let icon = NSImage(contentsOf: iconURL) else { return nil }
        icon.isTemplate = true
        icon.size = NSSize(width: 19, height: 19)
        return icon
    }

    private func loadAppIcon() -> NSImage? {
        let iconURL = projectRootURL().appendingPathComponent("Packaging/AppIcon.svg")
        return NSImage(contentsOf: iconURL)
    }
}
