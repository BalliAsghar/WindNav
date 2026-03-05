import AppKit
import CoreGraphics
import Foundation
import SwiftUI

struct ThumbnailLayoutEngine {
    struct ItemInput {
        let thumbnailPixelSize: CGSize?
        let aspectRatioHint: CGFloat?
    }

    struct ItemMetrics: Equatable {
        let thumbnailWidth: CGFloat
        let aspectRatio: CGFloat
    }

    struct Layout {
        let baseThumbnailWidth: CGFloat
        let thumbnailHeight: CGFloat
        let itemMetrics: [ItemMetrics]
        let contentSize: CGSize

        func itemMetric(at index: Int) -> ItemMetrics {
            guard !itemMetrics.isEmpty else {
                return ItemMetrics(thumbnailWidth: baseThumbnailWidth, aspectRatio: ThumbnailLayoutEngine.fallbackAspectRatio)
            }
            guard itemMetrics.indices.contains(index) else {
                return itemMetrics[itemMetrics.count - 1]
            }
            return itemMetrics[index]
        }
    }

    static let fallbackAspectRatio: CGFloat = 1.6
    static let minAspectRatio: CGFloat = 0.4
    static let maxAspectRatio: CGFloat = 2.4
    static let minimumThumbnailWidth: CGFloat = 96
    static let minimumThumbnailHeight: CGFloat = 40
    static let thumbnailHeightRatio: CGFloat = 0.625
    static let panelInsets: CGFloat = 16
    static let thumbnailToTitleSpacing: CGFloat = 3
    static let titleRowSpacing: CGFloat = 3
    static let titleFontSize: CGFloat = 10

    static func makeLayout(
        items: [ItemInput],
        requestedThumbnailWidth: CGFloat,
        itemSpacing: CGFloat,
        itemPadding: CGFloat,
        iconSize: CGFloat,
        maxPanelWidth: CGFloat
    ) -> Layout {
        let requestedBaseWidth = max(minimumThumbnailWidth, floor(requestedThumbnailWidth))
        let ratios = items.map(resolvedAspectRatio)
        let baseWidth = fittedBaseWidth(
            requestedBaseWidth: requestedBaseWidth,
            ratios: ratios,
            itemSpacing: itemSpacing,
            itemPadding: itemPadding,
            maxPanelWidth: maxPanelWidth
        )
        return makeLayout(
            baseWidth: baseWidth,
            ratios: ratios,
            itemSpacing: itemSpacing,
            itemPadding: itemPadding,
            iconSize: iconSize
        )
    }

    private static func makeLayout(
        baseWidth: CGFloat,
        ratios: [CGFloat],
        itemSpacing: CGFloat,
        itemPadding: CGFloat,
        iconSize: CGFloat
    ) -> Layout {
        let thumbnailHeight = max(minimumThumbnailHeight, round(baseWidth * thumbnailHeightRatio))
        let itemMetrics = ratios.map { ratio in
            ItemMetrics(
                thumbnailWidth: thumbnailWidth(for: ratio, baseWidth: baseWidth, thumbnailHeight: thumbnailHeight),
                aspectRatio: ratio
            )
        }
        let contentWidth = contentWidth(for: itemMetrics, itemSpacing: itemSpacing, itemPadding: itemPadding)
        let titleRowHeight = max(iconSize, titleFontSize + 2)
        let tileHeight = thumbnailHeight + thumbnailToTitleSpacing + titleRowHeight + (itemPadding * 2)
        let contentHeight = tileHeight + panelInsets
        return Layout(
            baseThumbnailWidth: baseWidth,
            thumbnailHeight: thumbnailHeight,
            itemMetrics: itemMetrics,
            contentSize: CGSize(width: contentWidth, height: contentHeight)
        )
    }

    private static func fittedBaseWidth(
        requestedBaseWidth: CGFloat,
        ratios: [CGFloat],
        itemSpacing: CGFloat,
        itemPadding: CGFloat,
        maxPanelWidth: CGFloat
    ) -> CGFloat {
        guard !ratios.isEmpty, maxPanelWidth > 0 else {
            return requestedBaseWidth
        }

        let minWidthInt = Int(minimumThumbnailWidth.rounded(.up))
        var low = minWidthInt
        var high = max(minWidthInt, Int(requestedBaseWidth.rounded(.down)))
        var best = minWidthInt

        while low <= high {
            let mid = (low + high) / 2
            let baseWidth = CGFloat(mid)
            let thumbnailHeight = max(minimumThumbnailHeight, round(baseWidth * thumbnailHeightRatio))
            let metrics = ratios.map { ratio in
                ItemMetrics(
                    thumbnailWidth: thumbnailWidth(for: ratio, baseWidth: baseWidth, thumbnailHeight: thumbnailHeight),
                    aspectRatio: ratio
                )
            }
            let width = contentWidth(for: metrics, itemSpacing: itemSpacing, itemPadding: itemPadding)
            if width <= maxPanelWidth {
                best = mid
                low = mid + 1
            } else {
                high = mid - 1
            }
        }

        return CGFloat(best)
    }

    private static func contentWidth(for metrics: [ItemMetrics], itemSpacing: CGFloat, itemPadding: CGFloat) -> CGFloat {
        let rowWidth = metrics.reduce(CGFloat(0)) { partial, metric in
            partial + metric.thumbnailWidth + (itemPadding * 2)
        }
        let spacing = CGFloat(max(metrics.count - 1, 0)) * itemSpacing
        return panelInsets + rowWidth + spacing
    }

    private static func thumbnailWidth(
        for aspectRatio: CGFloat,
        baseWidth: CGFloat,
        thumbnailHeight: CGFloat
    ) -> CGFloat {
        if aspectRatio >= 1 {
            return baseWidth
        }

        let portraitWidth = round(thumbnailHeight * aspectRatio)
        return max(minimumThumbnailWidth, min(baseWidth, portraitWidth))
    }

    private static func resolvedAspectRatio(_ input: ItemInput) -> CGFloat {
        if let size = input.thumbnailPixelSize, size.width > 1, size.height > 1 {
            return clampRatio(size.width / size.height)
        }
        if let hint = input.aspectRatioHint, hint > 0 {
            return clampRatio(hint)
        }
        return fallbackAspectRatio
    }

    private static func clampRatio(_ value: CGFloat) -> CGFloat {
        max(minAspectRatio, min(maxAspectRatio, value))
    }
}

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
                thumbnailAspectRatio: $0.thumbnailAspectRatio,
                isSelected: $0.isSelected,
                isWindowlessApp: $0.isWindowlessApp,
                windowIndexInApp: $0.windowIndexInApp
            )
        }

        let hasThumbnails = appearance.showThumbnails && renderItems.contains {
            $0.thumbnail != nil || $0.thumbnailAspectRatio != nil
        }
        let maxPanelWidth = (NSScreen.main?.frame.width ?? 1200) * 0.9
        let thumbnailLayout = hasThumbnails ? ThumbnailLayoutEngine.makeLayout(
            items: renderItems.map {
                ThumbnailLayoutEngine.ItemInput(
                    thumbnailPixelSize: $0.thumbnail.map {
                        CGSize(width: CGFloat($0.width), height: CGFloat($0.height))
                    },
                    aspectRatioHint: $0.thumbnailAspectRatio
                )
            },
            requestedThumbnailWidth: CGFloat(appearance.thumbnailWidth),
            itemSpacing: CGFloat(appearance.itemSpacing),
            itemPadding: CGFloat(appearance.itemPadding),
            iconSize: CGFloat(appearance.iconSize),
            maxPanelWidth: maxPanelWidth
        ) : nil

        let view = MinimalHUDView(
            items: renderItems,
            appearance: appearance,
            showThumbnails: hasThumbnails,
            thumbnailLayout: thumbnailLayout
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
            thumbnailLayout: thumbnailLayout
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

    private func estimateSize(
        itemCount: Int,
        appearance: AppearanceConfig,
        hasThumbnails: Bool,
        thumbnailLayout: ThumbnailLayoutEngine.Layout?
    ) -> CGSize {
        if hasThumbnails, let thumbnailLayout {
            return thumbnailLayout.contentSize
        }

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
    let thumbnail: CGImage?
    let thumbnailAspectRatio: CGFloat?
    let isSelected: Bool
    let isWindowlessApp: Bool
    let windowIndexInApp: Int?
}

private struct MinimalHUDView: View {
    let items: [HUDRenderItem]
    let appearance: AppearanceConfig
    let showThumbnails: Bool
    let thumbnailLayout: ThumbnailLayoutEngine.Layout?

    var body: some View {
        HStack(spacing: CGFloat(appearance.itemSpacing)) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                if showThumbnails, let thumbnailLayout {
                    thumbnailTile(
                        item: item,
                        thumbnailMetric: thumbnailLayout.itemMetric(at: index),
                        thumbnailHeight: thumbnailLayout.thumbnailHeight
                    )
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
    private func thumbnailTile(
        item: HUDRenderItem,
        thumbnailMetric: ThumbnailLayoutEngine.ItemMetrics,
        thumbnailHeight: CGFloat
    ) -> some View {
        let thumbnailWidth = thumbnailMetric.thumbnailWidth
        let titleWidth = max(24, thumbnailWidth - CGFloat(appearance.iconSize) - ThumbnailLayoutEngine.titleRowSpacing)

        VStack(spacing: ThumbnailLayoutEngine.thumbnailToTitleSpacing) {
            ZStack {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color(NSColor.controlBackgroundColor).opacity(0.55))
                    .frame(width: thumbnailWidth, height: thumbnailHeight)

                if let thumbnail = item.thumbnail {
                    Image(decorative: thumbnail, scale: NSScreen.main?.backingScaleFactor ?? 2.0)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: thumbnailWidth, maxHeight: thumbnailHeight)
                        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                }
            }
            .frame(width: thumbnailWidth, height: thumbnailHeight)

            HStack(spacing: ThumbnailLayoutEngine.titleRowSpacing) {
                if let icon = item.icon {
                    Image(nsImage: icon)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: CGFloat(appearance.iconSize), height: CGFloat(appearance.iconSize))
                }

                Text(item.label)
                    .font(.system(size: ThumbnailLayoutEngine.titleFontSize, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: titleWidth, alignment: .leading)
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
