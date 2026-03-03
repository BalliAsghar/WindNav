import AppKit
import Foundation
import SwiftUI

@MainActor
final class MinimalHUDController: HUDControlling {
    private var panel: NSPanel?
    private var hostingView: NSHostingView<MinimalHUDView>?

    func show(model: HUDModel, appearance: AppearanceConfig) {
        let renderItems = model.items.map {
            HUDRenderItem(id: $0.id, label: $0.label, icon: NSRunningApplication(processIdentifier: $0.pid)?.icon, isSelected: $0.isSelected)
        }

        let view = MinimalHUDView(items: renderItems, appearance: appearance)
        if let hostingView {
            hostingView.rootView = view
        } else {
            let host = NSHostingView(rootView: view)
            hostingView = host
            let panel = makePanel(contentView: host)
            self.panel = panel
        }

        guard let panel else { return }
        let contentSize = estimateSize(itemCount: renderItems.count, appearance: appearance)
        panel.setContentSize(contentSize)
        if let screen = NSScreen.main {
            let x = screen.frame.midX - (contentSize.width / 2)
            let y = screen.frame.midY - (contentSize.height / 2)
            panel.setFrameOrigin(CGPoint(x: x, y: y))
        }
        panel.orderFrontRegardless()
    }

    func hide() {
        panel?.orderOut(nil)
    }

    private func makePanel(contentView: NSView) -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 84),
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )
        panel.level = .statusBar
        panel.isOpaque = false
        panel.hasShadow = true
        panel.backgroundColor = .clear
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.ignoresMouseEvents = true
        panel.contentView = contentView
        return panel
    }

    private func estimateSize(itemCount: Int, appearance: AppearanceConfig) -> CGSize {
        let icon = CGFloat(appearance.iconSize)
        let spacing = CGFloat(appearance.itemSpacing)
        let padding = CGFloat(appearance.itemPadding)
        let width = max(160, (CGFloat(itemCount) * icon) + (CGFloat(max(itemCount - 1, 0)) * spacing) + (padding * 6))
        let height = max(56, icon + (padding * 3))
        return CGSize(width: width, height: height)
    }
}

private struct HUDRenderItem: Identifiable {
    let id: String
    let label: String
    let icon: NSImage?
    let isSelected: Bool
}

private struct MinimalHUDView: View {
    let items: [HUDRenderItem]
    let appearance: AppearanceConfig

    var body: some View {
        HStack(spacing: CGFloat(appearance.itemSpacing)) {
            ForEach(items) { item in
                ZStack {
                    if let icon = item.icon {
                        Image(nsImage: icon)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: CGFloat(appearance.iconSize), height: CGFloat(appearance.iconSize))
                    } else {
                        Text(String(item.label.prefix(1)).uppercased())
                            .font(.system(size: max(12, CGFloat(appearance.iconSize) * 0.45), weight: .semibold))
                            .frame(width: CGFloat(appearance.iconSize), height: CGFloat(appearance.iconSize))
                    }
                }
                .padding(CGFloat(appearance.itemPadding))
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(item.isSelected ? Color.accentColor : Color(NSColor.windowBackgroundColor).opacity(0.8))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color(NSColor.separatorColor).opacity(item.isSelected ? 0.0 : 0.45), lineWidth: 0.5)
                )
                .foregroundStyle(item.isSelected ? Color.white : Color.primary)
            }
        }
        .padding(8)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shadow(color: .black.opacity(0.22), radius: 12, x: 0, y: 4)
        .preferredColorScheme(preferredColorScheme)
    }

    private var preferredColorScheme: ColorScheme? {
        switch appearance.theme {
            case .light: return .light
            case .dark: return .dark
            case .system: return nil
        }
    }
}
