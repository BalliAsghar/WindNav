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
    private var iconCache: [pid_t: NSImage] = [:]
    private var missingIconPIDs = Set<pid_t>()
    private var lastPanelSize: CGSize?
    private var lastPanelOrigin: CGPoint?
    private var lastRenderedState: RenderState?

    func show(model: HUDModel, appearance: AppearanceConfig) {
        let renderItems = model.items.map {
            HUDRenderItem(
                id: $0.id,
                label: $0.label,
                icon: icon(for: $0.pid),
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

        let contentSize = estimateSize(
            itemCount: renderItems.count,
            appearance: appearance,
            hasThumbnails: hasThumbnails,
            thumbnailLayout: thumbnailLayout
        )
        let clampedWidth = min(contentSize.width, maxPanelWidth)
        let panelSize = CGSize(width: clampedWidth, height: contentSize.height)
        let panelOrigin = centeredPanelOrigin(size: panelSize)
        let renderState = RenderState(
            model: model,
            appearance: appearance,
            renderItems: renderItems,
            showThumbnails: hasThumbnails,
            thumbnailLayout: thumbnailLayout,
            panelSize: panelSize,
            panelOrigin: panelOrigin
        )

        if hostingView == nil {
            let view = MinimalHUDView(
                items: renderItems,
                appearance: appearance,
                showThumbnails: hasThumbnails,
                thumbnailLayout: thumbnailLayout
            )
            let host = NSHostingView(rootView: view)
            hostingView = host
            let panel = makePanel(contentView: host)
            self.panel = panel
        } else if lastRenderedState != renderState, let hostingView {
            hostingView.rootView = MinimalHUDView(
                items: renderItems,
                appearance: appearance,
                showThumbnails: hasThumbnails,
                thumbnailLayout: thumbnailLayout
            )
        }

        guard let panel else { return }
        updatePanelGeometryIfNeeded(panel: panel, size: panelSize, origin: panelOrigin)

        panel.orderFrontRegardless()
        lastRenderedState = renderState
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

    private func icon(for pid: pid_t) -> NSImage? {
        if let cached = iconCache[pid] {
            return cached
        }
        if missingIconPIDs.contains(pid) {
            return nil
        }
        if let icon = NSRunningApplication(processIdentifier: pid)?.icon {
            iconCache[pid] = icon
            return icon
        }
        missingIconPIDs.insert(pid)
        return nil
    }

    private func updatePanelGeometryIfNeeded(panel: NSPanel, size: CGSize, origin: CGPoint) {
        if lastPanelSize != size {
            panel.setContentSize(size)
            lastPanelSize = size
        }
        if lastPanelOrigin != origin {
            panel.setFrameOrigin(origin)
            lastPanelOrigin = origin
        }
    }

    private func centeredPanelOrigin(size: CGSize) -> CGPoint {
        guard let screen = NSScreen.main else {
            return .zero
        }
        return CGPoint(
            x: screen.frame.midX - (size.width / 2),
            y: screen.frame.midY - (size.height / 2)
        )
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

private struct RenderState: Equatable {
    let model: HUDModel
    let appearance: AppearanceConfig
    let renderItems: [HUDRenderItem]
    let showThumbnails: Bool
    let thumbnailLayout: ThumbnailLayoutEngine.Layout?
    let panelSize: CGSize
    let panelOrigin: CGPoint

    static func == (lhs: RenderState, rhs: RenderState) -> Bool {
        lhs.model == rhs.model
            && lhs.appearance == rhs.appearance
            && lhs.renderItems == rhs.renderItems
            && lhs.showThumbnails == rhs.showThumbnails
            && lhs.panelSize == rhs.panelSize
            && lhs.panelOrigin == rhs.panelOrigin
            && lhs.thumbnailLayout?.baseThumbnailWidth == rhs.thumbnailLayout?.baseThumbnailWidth
            && lhs.thumbnailLayout?.thumbnailHeight == rhs.thumbnailLayout?.thumbnailHeight
            && lhs.thumbnailLayout?.itemMetrics == rhs.thumbnailLayout?.itemMetrics
            && lhs.thumbnailLayout?.contentSize == rhs.thumbnailLayout?.contentSize
    }
}

private struct HUDRenderItem: Identifiable, Equatable {
    let id: String
    let label: String
    let icon: NSImage?
    let thumbnail: CGImage?
    let thumbnailAspectRatio: CGFloat?
    let isSelected: Bool
    let isWindowlessApp: Bool
    let windowIndexInApp: Int?

    static func == (lhs: HUDRenderItem, rhs: HUDRenderItem) -> Bool {
        lhs.id == rhs.id
            && lhs.label == rhs.label
            && lhs.icon?.tiffRepresentation == rhs.icon?.tiffRepresentation
            && lhs.thumbnail === rhs.thumbnail
            && lhs.thumbnailAspectRatio == rhs.thumbnailAspectRatio
            && lhs.isSelected == rhs.isSelected
            && lhs.isWindowlessApp == rhs.isWindowlessApp
            && lhs.windowIndexInApp == rhs.windowIndexInApp
    }
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
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(panelBackground)
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(Color.white.opacity(preferredColorScheme == .dark ? 0.08 : 0.3), lineWidth: 0.8)
        )
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .shadow(color: .black.opacity(0.18), radius: 16, x: 0, y: 10)
        .preferredColorScheme(preferredColorScheme)
    }

    @ViewBuilder
    private func thumbnailTile(
        item: HUDRenderItem,
        thumbnailMetric: ThumbnailLayoutEngine.ItemMetrics,
        thumbnailHeight: CGFloat
    ) -> some View {
        let thumbnailWidth = thumbnailMetric.thumbnailWidth
        let titleWidth = max(24, thumbnailWidth - CGFloat(appearance.iconSize) - 8)

        VStack(spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(thumbnailBackdrop(for: item))
                    .frame(width: thumbnailWidth, height: thumbnailHeight)

                if let thumbnail = item.thumbnail {
                    Image(decorative: thumbnail, scale: NSScreen.main?.backingScaleFactor ?? 2.0)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: thumbnailWidth, maxHeight: thumbnailHeight)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
            }
            .frame(width: thumbnailWidth, height: thumbnailHeight)
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.white.opacity(item.isSelected ? 0.38 : 0.12), lineWidth: item.isSelected ? 1.2 : 0.8)
            )

            HStack(spacing: 6) {
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
                    .frame(maxWidth: titleWidth, alignment: .leading)
            }
            .frame(width: thumbnailWidth, alignment: .leading)
        }
        .overlay(alignment: .topTrailing) {
            badge(for: item)
        }
        .padding(.horizontal, CGFloat(appearance.itemPadding) + 2)
        .padding(.vertical, CGFloat(appearance.itemPadding) + 1)
        .background(tileBackground(for: item))
        .foregroundStyle(tileForegroundColor(for: item))
    }

    @ViewBuilder
    private func iconTile(item: HUDRenderItem) -> some View {
        VStack(spacing: 7) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(thumbnailBackdrop(for: item))
                    .frame(
                        width: CGFloat(appearance.iconSize) + 24,
                        height: CGFloat(appearance.iconSize) + 20
                    )

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
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.white.opacity(item.isSelected ? 0.38 : 0.12), lineWidth: item.isSelected ? 1.2 : 0.8)
            )

            Text(item.label)
                .font(.system(size: 11, weight: .medium))
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(width: max(56, CGFloat(appearance.iconSize) + 28))
        }
        .overlay(alignment: .topTrailing) {
            badge(for: item)
        }
        .padding(.horizontal, CGFloat(appearance.itemPadding) + 2)
        .padding(.vertical, CGFloat(appearance.itemPadding) + 1)
        .background(tileBackground(for: item))
        .foregroundStyle(tileForegroundColor(for: item))
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
                        .fill(item.isSelected ? Color.white.opacity(0.98) : Color.black.opacity(0.76))
                )
                .foregroundStyle(item.isSelected ? Color.black : Color.white)
                .offset(x: 6, y: -6)
        }
    }

    private var panelBackground: some View {
        RoundedRectangle(cornerRadius: 22, style: .continuous)
            .fill(.regularMaterial)
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(preferredColorScheme == .dark ? 0.04 : 0.22),
                                Color.black.opacity(preferredColorScheme == .dark ? 0.08 : 0.03),
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            )
    }

    private func tileBackground(for item: HUDRenderItem) -> some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(tileBackgroundColor(for: item))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(tileBorderColor(for: item), lineWidth: item.isSelected ? 1.4 : 0.8)
            )
    }

    private func thumbnailBackdrop(for item: HUDRenderItem) -> Color {
        if item.isSelected {
            return Color.white.opacity(preferredColorScheme == .dark ? 0.12 : 0.28)
        }
        return Color(NSColor.controlBackgroundColor).opacity(preferredColorScheme == .dark ? 0.34 : 0.72)
    }

    private func tileBackgroundColor(for item: HUDRenderItem) -> Color {
        if item.isSelected {
            return Color.accentColor.opacity(preferredColorScheme == .dark ? 0.92 : 0.88)
        }
        if item.isWindowlessApp {
            return Color.yellow.opacity(preferredColorScheme == .dark ? 0.84 : 0.92)
        }
        return Color(NSColor.windowBackgroundColor).opacity(preferredColorScheme == .dark ? 0.58 : 0.84)
    }

    private func tileBorderColor(for item: HUDRenderItem) -> Color {
        if item.isSelected {
            return Color.white.opacity(preferredColorScheme == .dark ? 0.42 : 0.7)
        }
        return Color.white.opacity(preferredColorScheme == .dark ? 0.07 : 0.3)
    }

    private func tileForegroundColor(for item: HUDRenderItem) -> Color {
        if item.isSelected {
            return .white
        }
        return item.isWindowlessApp ? Color.black.opacity(0.82) : .primary
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
