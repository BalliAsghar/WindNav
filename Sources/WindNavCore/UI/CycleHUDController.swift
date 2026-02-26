import AppKit
import Foundation

struct CycleHUDItem: Sendable {
    let label: String
    let count: Int
    let isPinned: Bool
    let isCurrent: Bool
}

struct CycleHUDModel: Sendable {
    let items: [CycleHUDItem]
    let selectedIndex: Int
    let monitorID: NSNumber
}

@MainActor
final class CycleHUDController {
    private var panel: NSPanel?
    private var labelField: NSTextField?
    private var hideWorkItem: DispatchWorkItem?

    func show(model: CycleHUDModel, config: HUDConfig, timeoutMs: Int) {
        guard config.enabled, !model.items.isEmpty else {
            hide()
            return
        }

        let panel = ensurePanel()
        let labelField = ensureLabelField(in: panel)
        labelField.attributedStringValue = attributedString(for: model, showWindowCount: config.showWindowCount)
        labelField.sizeToFit()

        let contentSize = CGSize(
            width: min(max(labelField.fittingSize.width + 32, 220), 900),
            height: 40
        )
        panel.setContentSize(contentSize)
        layoutLabel(in: panel)
        position(panel: panel, monitorID: model.monitorID, position: config.position)

        panel.orderFrontRegardless()
        scheduleHide(afterMs: timeoutMs)
        Logger.info(.navigation, "HUD shown items=\(model.items.count) selected=\(model.selectedIndex)")
    }

    func hide() {
        hideWorkItem?.cancel()
        hideWorkItem = nil
        panel?.orderOut(nil)
    }

    private func ensurePanel() -> NSPanel {
        if let panel { return panel }

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 40),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = true
        panel.isMovableByWindowBackground = false
        panel.becomesKeyOnlyIfNeeded = false
        panel.worksWhenModal = true

        let effect = NSVisualEffectView(frame: panel.contentView?.bounds ?? .zero)
        effect.autoresizingMask = [.width, .height]
        effect.material = .hudWindow
        effect.state = .active
        effect.blendingMode = .withinWindow
        effect.wantsLayer = true
        effect.layer?.cornerRadius = 12
        effect.layer?.masksToBounds = true
        panel.contentView = effect

        self.panel = panel
        return panel
    }

    private func ensureLabelField(in panel: NSPanel) -> NSTextField {
        if let labelField { return labelField }

        let field = NSTextField(labelWithString: "")
        field.alignment = .center
        field.lineBreakMode = .byTruncatingTail
        field.translatesAutoresizingMaskIntoConstraints = true
        field.backgroundColor = .clear
        field.textColor = .labelColor

        panel.contentView?.addSubview(field)
        labelField = field
        layoutLabel(in: panel)
        return field
    }

    private func layoutLabel(in panel: NSPanel) {
        guard let field = labelField, let contentView = panel.contentView else { return }
        let inset: CGFloat = 16
        field.frame = contentView.bounds.insetBy(dx: inset, dy: 8)
    }

    private func attributedString(for model: CycleHUDModel, showWindowCount: Bool) -> NSAttributedString {
        let result = NSMutableAttributedString()
        for (index, item) in model.items.enumerated() {
            if index > 0 {
                result.append(NSAttributedString(string: "  |  ", attributes: [
                    .foregroundColor: NSColor.tertiaryLabelColor,
                    .font: NSFont.systemFont(ofSize: 13, weight: .regular),
                ]))
            }

            var text = item.label
            if showWindowCount, item.count > 1 {
                text += " (\(item.count))"
            }

            let attrs: [NSAttributedString.Key: Any] = item.isCurrent
                ? [
                    .foregroundColor: NSColor.white,
                    .font: NSFont.monospacedSystemFont(ofSize: 13, weight: .semibold),
                    .backgroundColor: NSColor.controlAccentColor.withAlphaComponent(0.85),
                ]
                : [
                    .foregroundColor: item.isPinned ? NSColor.labelColor : NSColor.secondaryLabelColor,
                    .font: NSFont.monospacedSystemFont(ofSize: 13, weight: .regular),
                ]

            let rendered = item.isCurrent ? " \(text) " : text
            result.append(NSAttributedString(string: rendered, attributes: attrs))
        }
        return result
    }

    private func position(panel: NSPanel, monitorID: NSNumber, position: HUDPosition) {
        guard position == .topCenter else { return }
        let screen = screen(for: monitorID) ?? NSScreen.main
        guard let screen else { return }

        let frame = screen.visibleFrame
        let x = frame.midX - panel.frame.width / 2
        let y = frame.maxY - panel.frame.height - 24
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
                self?.panel?.orderOut(nil)
                Logger.info(.navigation, "HUD hidden")
            }
        }
        hideWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(timeoutMs), execute: item)
    }
}
