import AppKit
import CoreGraphics
import Foundation
import SwiftUI

@MainActor
final class MinimalHUDController: HUDControlling {
    private var panel: NSPanel?
    private var hostingView: NSHostingView<MinimalHUDView>?

    func show(model: HUDModel, appearance: AppearanceConfig) {
        let renderItems = model.items.map {
            HUDRenderItem(
                id: $0.id,
                label: $0.label,
                icon: NSRunningApplication(processIdentifier: $0.pid)?.icon,
                thumbnail: $0.thumbnail,
                isSelected: $0.isSelected,
                isWindowlessApp: $0.isWindowlessApp,
                windowIndexInApp: $0.windowIndexInApp
            )
        }

        let hasThumbnails = appearance.showThumbnails && renderItems.contains { $0.thumbnail != nil }
        let maxPanelWidth = (NSScreen.main?.frame.width ?? 1200) * 0.9
        let effectiveThumbnailWidth = effectiveThumbnailWidth(
            itemCount: renderItems.count,
            appearance: appearance,
            hasThumbnails: hasThumbnails,
            maxPanelWidth: maxPanelWidth
        )

        let view = MinimalHUDView(
            items: renderItems,
            appearance: appearance,
            showThumbnails: hasThumbnails,
            thumbnailWidth: effectiveThumbnailWidth
        )

        if let hostingView {
            hostingView.rootView = view
        } else {
            let host = NSHostingView(rootView: view)
            hostingView = host
            let panel = makePanel(contentView: host)
            self.panel = panel
        }

        guard let panel else { return }
        let contentSize = estimateSize(
            itemCount: renderItems.count,
            appearance: appearance,
            hasThumbnails: hasThumbnails,
            thumbnailWidth: effectiveThumbnailWidth
        )

        let clampedWidth = min(contentSize.width, maxPanelWidth)
        panel.setContentSize(CGSize(width: clampedWidth, height: contentSize.height))

        if let screen = NSScreen.main {
            let x = screen.frame.midX - (clampedWidth / 2)
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

    private func effectiveThumbnailWidth(
        itemCount: Int,
        appearance: AppearanceConfig,
        hasThumbnails: Bool,
        maxPanelWidth: CGFloat
    ) -> CGFloat {
        guard hasThumbnails else { return CGFloat(appearance.thumbnailWidth) }
        guard itemCount > 0 else { return CGFloat(appearance.thumbnailWidth) }

        let spacing = CGFloat(appearance.itemSpacing)
        let padding = CGFloat(appearance.itemPadding)
        let panelInsets: CGFloat = 16
        let totalSpacing = CGFloat(max(itemCount - 1, 0)) * spacing
        let fixedHorizontal = panelInsets + totalSpacing + (CGFloat(itemCount) * padding * 2)
        let availablePerItem = max(120, (maxPanelWidth - fixedHorizontal) / CGFloat(itemCount))

        return min(CGFloat(appearance.thumbnailWidth), max(120, floor(availablePerItem)))
    }

    private func estimateSize(
        itemCount: Int,
        appearance: AppearanceConfig,
        hasThumbnails: Bool,
        thumbnailWidth: CGFloat
    ) -> CGSize {
        let icon = CGFloat(appearance.iconSize)
        let spacing = CGFloat(appearance.itemSpacing)
        let padding = CGFloat(appearance.itemPadding)

        if hasThumbnails {
            let thumbnailHeight = max(40, round(thumbnailWidth * 0.625))
            let tileWidth = thumbnailWidth + (padding * 2)
            let tileHeight = thumbnailHeight + icon + 4 + (padding * 2)
            let width = max(220, (CGFloat(itemCount) * tileWidth) + (CGFloat(max(itemCount - 1, 0)) * spacing) + 16)
            let height = tileHeight + 16
            return CGSize(width: width, height: height)
        }

        let width = max(160, (CGFloat(itemCount) * icon) + (CGFloat(max(itemCount - 1, 0)) * spacing) + (padding * 6))
        let height = max(56, icon + (padding * 3))
        return CGSize(width: width, height: height)
    }
}

private struct HUDRenderItem: Identifiable {
    let id: String
    let label: String
    let icon: NSImage?
    let thumbnail: CGImage?
    let isSelected: Bool
    let isWindowlessApp: Bool
    let windowIndexInApp: Int?
}

private struct MinimalHUDView: View {
    let items: [HUDRenderItem]
    let appearance: AppearanceConfig
    let showThumbnails: Bool
    let thumbnailWidth: CGFloat

    var body: some View {
        HStack(spacing: CGFloat(appearance.itemSpacing)) {
            ForEach(items) { item in
                if showThumbnails {
                    thumbnailTile(item: item)
                } else {
                    iconTile(item: item)
                }
            }
        }
        .padding(8)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shadow(color: .black.opacity(0.22), radius: 12, x: 0, y: 4)
        .preferredColorScheme(preferredColorScheme)
    }

    @ViewBuilder
    private func thumbnailTile(item: HUDRenderItem) -> some View {
        let thumbHeight = max(40, round(thumbnailWidth * 0.625))

        VStack(spacing: 4) {
            ZStack {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color(NSColor.controlBackgroundColor).opacity(0.55))
                    .frame(width: thumbnailWidth, height: thumbHeight)

                if let thumbnail = item.thumbnail {
                    Image(decorative: thumbnail, scale: NSScreen.main?.backingScaleFactor ?? 2.0)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: thumbnailWidth, maxHeight: thumbHeight)
                        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                }
            }
            .frame(width: thumbnailWidth, height: thumbHeight)

            HStack(spacing: 4) {
                if let icon = item.icon {
                    Image(nsImage: icon)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: CGFloat(appearance.iconSize), height: CGFloat(appearance.iconSize))
                }

                Text(item.label)
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: thumbnailWidth - CGFloat(appearance.iconSize) - 4, alignment: .leading)
            }
        }
        .overlay(alignment: .topTrailing) {
            badge(for: item)
        }
        .overlay(alignment: .bottomTrailing) {
            windowlessDot(for: item)
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

    @ViewBuilder
    private func iconTile(item: HUDRenderItem) -> some View {
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
        .overlay(alignment: .topTrailing) {
            badge(for: item)
        }
        .overlay(alignment: .bottomTrailing) {
            windowlessDot(for: item)
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

    @ViewBuilder
    private func badge(for item: HUDRenderItem) -> some View {
        if let badgeText = HUDBadgeFormatter.badgeText(for: item.windowIndexInApp) {
            Text(badgeText)
                .font(.system(size: 10, weight: .semibold))
                .padding(.horizontal, 5)
                .frame(minHeight: 14)
                .background(
                    Capsule(style: .continuous)
                        .fill(item.isSelected ? Color.white.opacity(0.95) : Color.black.opacity(0.72))
                )
                .foregroundStyle(item.isSelected ? Color.black : Color.white)
                .offset(x: 6, y: -6)
        }
    }

    @ViewBuilder
    private func windowlessDot(for item: HUDRenderItem) -> some View {
        if item.isWindowlessApp {
            Circle()
                .fill(Color.orange.opacity(0.9))
                .frame(width: 7, height: 7)
                .offset(x: 3, y: 3)
        }
    }

    private var preferredColorScheme: ColorScheme? {
        switch appearance.theme {
            case .light: return .light
            case .dark: return .dark
            case .system: return nil
        }
    }
}

enum HUDBadgeFormatter {
    static func badgeText(for windowIndexInApp: Int?) -> String? {
        guard let windowIndexInApp, windowIndexInApp > 0 else { return nil }
        return "\(windowIndexInApp)"
    }
}
