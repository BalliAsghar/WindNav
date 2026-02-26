import AppKit
import Foundation

struct CycleHUDItem: Sendable {
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

@MainActor
final class CycleHUDController {
    private var panel: NSPanel?
    private var labelField: NSTextField?
    private var hideWorkItem: DispatchWorkItem?
    private var iconCache: [String: NSImage] = [:]

    func show(model: CycleHUDModel, config: HUDConfig, timeoutMs: Int) {
        guard config.enabled, !model.items.isEmpty else {
            hide()
            return
        }

        let panel = ensurePanel()
        let labelField = ensureLabelField(in: panel)
        labelField.attributedStringValue = attributedString(for: model, config: config)
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

    private func attributedString(for model: CycleHUDModel, config: HUDConfig) -> NSAttributedString {
        let result = NSMutableAttributedString()
        for (index, item) in model.items.enumerated() {
            if index > 0 {
                result.append(NSAttributedString(string: "  |  ", attributes: [
                    .foregroundColor: NSColor.tertiaryLabelColor,
                    .font: NSFont.systemFont(ofSize: 13, weight: .regular),
                ]))
            }

            let text = item.label
            if config.showIcons, let icon = iconAttachment(for: item) {
                result.append(icon)
                result.append(NSAttributedString(string: " ", attributes: [
                    .font: NSFont.monospacedSystemFont(ofSize: 13, weight: .regular),
                ]))
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
                self?.panel?.orderOut(nil)
                Logger.info(.navigation, "HUD hidden")
            }
        }
        hideWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(timeoutMs), execute: item)
    }

    private func iconAttachment(for item: CycleHUDItem) -> NSAttributedString? {
        guard let icon = resolvedAppIcon(for: item) else { return nil }
        let attachment = NSTextAttachment()
        attachment.image = icon
        attachment.bounds = NSRect(x: 0, y: -2, width: 16, height: 16)
        return NSAttributedString(attachment: attachment)
    }

    private func resolvedAppIcon(for item: CycleHUDItem) -> NSImage? {
        let cacheKey = item.iconBundleId.map { "bundle:\($0)" } ?? "pid:\(item.iconPID)"
        if let cached = iconCache[cacheKey] {
            return cached
        }

        guard let app = NSRunningApplication(processIdentifier: item.iconPID),
              let image = app.icon else {
            return nil
        }

        let scaled = scaledIcon(image, size: 16)
        iconCache[cacheKey] = scaled
        return scaled
    }

    private func scaledIcon(_ image: NSImage, size: CGFloat) -> NSImage {
        let scaled = NSImage(size: NSSize(width: size, height: size))
        scaled.lockFocus()
        defer { scaled.unlockFocus() }
        image.draw(
            in: NSRect(x: 0, y: 0, width: size, height: size),
            from: NSRect(origin: .zero, size: image.size),
            operation: .sourceOver,
            fraction: 1.0
        )
        return scaled
    }
}
