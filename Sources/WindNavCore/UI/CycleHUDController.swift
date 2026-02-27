import AppKit
import Foundation
import SwiftUI

struct CycleHUDItem: Sendable, Identifiable {
    let id = UUID()
    let label: String
    let iconPID: pid_t
    let iconBundleId: String?
    let isPinned: Bool
    let isCurrent: Bool
}

struct CycleHUDModel: Sendable {
    let items: [CycleHUDItem]
    let selectedIndex: Int
    let monitorID: NSNumber
}

// MARK: - SwiftUI HUD View

private struct ModernHUDView: View {
    let model: CycleHUDModel
    let config: HUDConfig

    var body: some View {
        HStack(spacing: 8) {
            ForEach(model.items) { item in
                HStack(spacing: 0) {
                    if let image = resolvedAppIcon(for: item) {
                        Image(nsImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 22, height: 22)
                    } else {
                        Image(systemName: "app.fill")
                            .font(.system(size: 18, weight: .medium))
                            .frame(width: 22, height: 22)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background {
                    if item.isCurrent {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color(NSColor.controlAccentColor))
                            .shadow(color: .black.opacity(0.1), radius: 2, y: 1)
                    }
                }
                .foregroundColor(
                    item.isCurrent ? .white :
                    (item.isPinned ? .primary : .secondary)
                )
                .scaleEffect(item.isCurrent ? 1.02 : 1.0)
                .animation(.spring(response: 0.3, dampingFraction: 0.6), value: item.isCurrent)
            }
        }
        .padding(8)
        .background(VisualEffectBackground(material: .hudWindow, blendingMode: .withinWindow))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color(NSColor.separatorColor).opacity(0.5), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.15), radius: 10, x: 0, y: 5)
    }

    private func resolvedAppIcon(for item: CycleHUDItem) -> NSImage? {
        guard let app = NSRunningApplication(processIdentifier: item.iconPID),
              let image = app.icon else {
            return nil
        }
        return image
    }
}

private struct VisualEffectBackground: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}

// MARK: - AppKit Controller

@MainActor
final class CycleHUDController {
    private var panel: NSPanel?
    private var hideWorkItem: DispatchWorkItem?

    func show(model: CycleHUDModel, config: HUDConfig, timeoutMs: Int) {
        guard config.enabled, !model.items.isEmpty else {
            hide()
            return
        }

        let panel = ensurePanel()

        let hostingView = NSHostingView(rootView: ModernHUDView(model: model, config: config))
        hostingView.sizingOptions = [.preferredContentSize]
        panel.contentView = hostingView

        hostingView.layout()
        let fittingSize = hostingView.fittingSize
        let contentSize = CGSize(
            width: max(fittingSize.width, 220),
            height: max(fittingSize.height, 44)
        )

        panel.setContentSize(contentSize)
        position(panel: panel, monitorID: model.monitorID, position: config.position)

        if !panel.isVisible {
            panel.alphaValue = 0
            panel.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.15
                panel.animator().alphaValue = 1.0
            }
        } else {
            panel.orderFrontRegardless()
        }

        if timeoutMs > 0 {
            scheduleHide(afterMs: timeoutMs)
        } else {
            hideWorkItem?.cancel()
            hideWorkItem = nil
        }
        Logger.info(.navigation, "HUD shown items=\(model.items.count) selected=\(model.selectedIndex)")
    }

    func hide() {
        hideWorkItem?.cancel()
        hideWorkItem = nil

        guard let panel = panel, panel.isVisible else { return }

        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.15
            panel.animator().alphaValue = 0.0
        }, completionHandler: { [weak panel] in
            Task { @MainActor in
                panel?.orderOut(nil)
            }
        })
        Logger.info(.navigation, "HUD hidden")
    }

    private func ensurePanel() -> NSPanel {
        if let panel { return panel }

        let panel = NSPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = true
        panel.isMovableByWindowBackground = false
        panel.becomesKeyOnlyIfNeeded = false
        panel.worksWhenModal = true

        self.panel = panel
        return panel
    }

    private func position(panel: NSPanel, monitorID: NSNumber, position: HUDPosition) {
        let screen = screen(for: monitorID) ?? NSScreen.main
        guard let screen else { return }

        let frame = screen.visibleFrame
        let x = frame.midX - panel.frame.width / 2
        let y: CGFloat
        switch position {
            case .topCenter:
                y = frame.maxY - panel.frame.height - 24
            case .middleCenter:
                y = frame.midY - panel.frame.height / 2
            case .bottomCenter:
                y = frame.minY + 24
        }
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }

    private func screen(for monitorID: NSNumber) -> NSScreen? {
        NSScreen.screens.first {
            ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber) == monitorID
        }
    }

    private func scheduleHide(afterMs timeoutMs: Int) {
        hideWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            Task { @MainActor [weak self] in
                self?.hide()
            }
        }
        hideWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(timeoutMs), execute: item)
    }
}
