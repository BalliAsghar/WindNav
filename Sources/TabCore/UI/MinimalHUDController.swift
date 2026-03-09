import AppKit
import Foundation
import QuartzCore

@MainActor
final class MinimalHUDController: HUDControlling {
    private let permissionService: PermissionService
    private lazy var captureScheduler: CaptureScheduler = {
        let cache = ThumbnailCache()
        let primaryProvider = ScreenCaptureKitThumbnailProvider()
        let privateProvider = PrivateWindowCaptureProvider()
        return CaptureScheduler(
            cache: cache,
            primaryProvider: primaryProvider,
            privateProvider: privateProvider
        ) { [weak self] update in
            self?.contentView?.apply(update: update)
        }
    }()

    private var panel: NSPanel?
    private var contentView: HUDPanelContentView?

    init(permissionService: PermissionService) {
        self.permissionService = permissionService
    }

    func show(model: HUDModel, appearance: AppearanceConfig) {
        guard !model.items.isEmpty else {
            hide()
            return
        }

        let contentView = ensureContentView()
        let visibleFrame = NSScreen.main?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1280, height: 800)
        let metrics = HUDGridMetrics(appearance: appearance)
        let maximumPanelSize = metrics.maximumPanelSize(for: visibleFrame)
        let contentSize = contentView.apply(
            model: model,
            appearance: appearance,
            maximumSize: maximumPanelSize
        )

        guard let panel else { return }
        panel.setContentSize(contentSize)
        contentView.frame = CGRect(origin: .zero, size: contentSize)
        contentView.layoutSubtreeIfNeeded()
        contentView.revealSelectedTile()

        if let screen = NSScreen.main {
            let x = screen.visibleFrame.midX - (contentSize.width / 2)
            let y = screen.visibleFrame.midY - (contentSize.height / 2)
            panel.setFrameOrigin(CGPoint(x: x, y: y))
        }
        panel.orderFrontRegardless()

        let screenRecordingGranted = permissionService.status(for: .screenRecording) == .granted
        Task {
            await captureScheduler.show(
                model: model,
                targetSize: metrics.thumbnailSize,
                screenRecordingGranted: screenRecordingGranted
            )
        }
    }

    func hide() {
        panel?.orderOut(nil)
        Task {
            await captureScheduler.hide()
        }
    }

    private func ensureContentView() -> HUDPanelContentView {
        if let contentView {
            return contentView
        }

        let contentView = HUDPanelContentView()
        self.contentView = contentView
        let panel = makePanel(contentView: contentView)
        self.panel = panel
        return contentView
    }

    private func makePanel(contentView: NSView) -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 840, height: 240),
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
}

final class HUDPanelContentView: NSVisualEffectView {
    private let scrollView = NSScrollView(frame: .zero)
    private let documentView = NSView(frame: .zero)
    private let tintLayer = CALayer()
    private var tileViews: [HUDThumbnailTileView] = []
    private var currentModel: HUDModel?
    private var currentAppearance: AppearanceConfig = .default
    private var currentLayout = HUDGridLayoutResult.empty
    private var currentVisualStyle = HUDVisualStyle.resolve(appearance: .default)

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        material = .hudWindow
        blendingMode = .behindWindow
        state = .active
        wantsLayer = true
        layer?.masksToBounds = false
        layer?.addSublayer(tintLayer)

        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasHorizontalScroller = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
        scrollView.contentView.postsBoundsChangedNotifications = true
        scrollView.documentView = documentView

        addSubview(scrollView)
        applyPanelStyle(currentVisualStyle.panel)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        tintLayer.frame = bounds
        scrollView.frame = bounds
    }

    @discardableResult
    func apply(model: HUDModel, appearance: AppearanceConfig, maximumSize: CGSize) -> CGSize {
        currentModel = model
        currentAppearance = appearance
        currentVisualStyle = HUDVisualStyle.resolve(appearance: appearance)
        let metrics = HUDGridMetrics(appearance: appearance)
        currentLayout = HUDGridLayout.layout(
            itemCount: model.items.count,
            metrics: metrics,
            maximumSize: maximumSize
        )
        applyPanelStyle(currentVisualStyle.panel)

        ensureTileCount(model.items.count)
        withoutAnimations {
            for (index, item) in model.items.enumerated() {
                let tile = tileViews[index]
                tile.isHidden = false
                tile.frame = currentLayout.tileFrames[index]
                tile.configure(item: item, appearance: appearance)
            }

            for index in model.items.count..<tileViews.count {
                tileViews[index].isHidden = true
            }

            documentView.frame = CGRect(origin: .zero, size: currentLayout.documentSize)
            scrollView.hasVerticalScroller = currentLayout.documentSize.height > currentLayout.viewportSize.height + 1
        }

        return currentLayout.viewportSize
    }

    func apply(update: ThumbnailUpdate) {
        guard let model = currentModel else { return }
        guard let index = model.items.firstIndex(where: {
            $0.snapshot.windowId == update.windowId && $0.snapshot.revision == update.revision
        }) else { return }
        tileViews[index].applyThumbnail(update.state, surface: update.surface)
    }

    func preferredSize(appearance: AppearanceConfig, maximumSize: CGSize) -> CGSize {
        let metrics = HUDGridMetrics(appearance: appearance)
        let itemCount = currentModel?.items.count ?? 0
        return HUDGridLayout.layout(
            itemCount: itemCount,
            metrics: metrics,
            maximumSize: maximumSize
        ).viewportSize
    }

    private func ensureTileCount(_ count: Int) {
        guard tileViews.count < count else { return }
        for _ in tileViews.count..<count {
            let tile = HUDThumbnailTileView()
            tileViews.append(tile)
            documentView.addSubview(tile)
        }
    }

    func revealSelectedTile() {
        guard let model = currentModel, let selectedIndex = model.selectedIndex else { return }
        guard tileViews.indices.contains(selectedIndex) else { return }
        documentView.scrollToVisible(HUDGridLayout.revealRect(for: tileViews[selectedIndex].frame))
    }

    var debugScrollOrigin: CGPoint {
        scrollView.contentView.bounds.origin
    }

    private func applyPanelStyle(_ style: HUDPanelChromeStyle) {
        material = style.material
        blendingMode = style.blendingMode
        tintLayer.backgroundColor = style.tintColor.cgColor
        tintLayer.cornerRadius = style.cornerRadius
        tintLayer.cornerCurve = .continuous
        tintLayer.masksToBounds = true
        layer?.shadowColor = style.shadowColor.cgColor
        layer?.shadowOpacity = style.shadowOpacity
        layer?.shadowRadius = style.shadowRadius
        layer?.shadowOffset = style.shadowOffset
        applyRoundedMask(radius: style.cornerRadius)
    }

    private func applyRoundedMask(radius: CGFloat) {
        guard radius > 0 else {
            maskImage = nil
            return
        }

        let edgeLength = 2.0 * radius + 1.0
        let mask = NSImage(size: NSSize(width: edgeLength, height: edgeLength), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
        mask.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        mask.resizingMode = .stretch
        maskImage = mask
    }
}

private struct ThumbnailTileIdentity: Equatable {
    let windowId: UInt32
    let revision: UInt64
}

final class HUDThumbnailTileView: NSView {
    private let backgroundLayer = CALayer()
    private let previewShadowLayer = CALayer()
    private let previewBackdropLayer = CALayer()
    private let previewLayer = CALayer()
    private let overlayLayer = CALayer()
    private let iconLayer = CALayer()
    private let liveIndicatorLayer = CALayer()
    private let badgeLayer = CATextLayer()
    private let titleLayer = CATextLayer()
    private let subtitleLayer = CATextLayer()

    private var item: HUDItem?
    private var appearanceConfig: AppearanceConfig = .default
    private var iconSurface: CGImage?
    private var representedThumbnailIdentity: ThumbnailTileIdentity?
    private var currentThumbnailState: ThumbnailState = .placeholder
    private var currentVisualStyle = HUDVisualStyle.resolve(appearance: .default)
    private var currentSelectionStyle: HUDTileSelectionStyle = .minimal
    private var isSelected = false
    private var showsSubtitle = true

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.masksToBounds = false
        layer?.addSublayer(backgroundLayer)
        layer?.addSublayer(previewShadowLayer)
        layer?.addSublayer(previewBackdropLayer)
        layer?.addSublayer(previewLayer)
        layer?.addSublayer(overlayLayer)
        layer?.addSublayer(iconLayer)
        layer?.addSublayer(liveIndicatorLayer)
        layer?.addSublayer(badgeLayer)
        layer?.addSublayer(titleLayer)
        layer?.addSublayer(subtitleLayer)

        backgroundLayer.cornerRadius = 14
        backgroundLayer.cornerCurve = .continuous
        backgroundLayer.borderWidth = 0
        backgroundLayer.masksToBounds = false

        previewShadowLayer.backgroundColor = NSColor.clear.cgColor
        previewShadowLayer.cornerRadius = 11
        previewShadowLayer.cornerCurve = .continuous

        previewBackdropLayer.cornerRadius = 10
        previewBackdropLayer.cornerCurve = .continuous
        previewBackdropLayer.masksToBounds = true
        previewBackdropLayer.backgroundColor = NSColor.clear.cgColor

        previewLayer.cornerRadius = 10
        previewLayer.cornerCurve = .continuous
        previewLayer.masksToBounds = true
        previewLayer.contentsGravity = .resizeAspect

        overlayLayer.cornerRadius = 10
        overlayLayer.cornerCurve = .continuous
        overlayLayer.backgroundColor = NSColor.black.withAlphaComponent(0.06).cgColor

        iconLayer.cornerRadius = 7
        iconLayer.cornerCurve = .continuous
        iconLayer.masksToBounds = true
        iconLayer.contentsGravity = .resizeAspectFill
        iconLayer.borderWidth = 0.5
        iconLayer.borderColor = NSColor.white.withAlphaComponent(0.08).cgColor

        liveIndicatorLayer.cornerRadius = 3
        liveIndicatorLayer.isHidden = true

        badgeLayer.alignmentMode = .center
        badgeLayer.contentsScale = NSScreen.main?.backingScaleFactor ?? 2
        badgeLayer.cornerRadius = 6
        badgeLayer.masksToBounds = true
        badgeLayer.font = NSFont.systemFont(ofSize: 9, weight: .semibold)
        badgeLayer.fontSize = 9

        titleLayer.contentsScale = NSScreen.main?.backingScaleFactor ?? 2
        titleLayer.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        titleLayer.fontSize = 12
        titleLayer.alignmentMode = .left
        titleLayer.truncationMode = .end

        subtitleLayer.contentsScale = NSScreen.main?.backingScaleFactor ?? 2
        subtitleLayer.font = NSFont.systemFont(ofSize: 10, weight: .regular)
        subtitleLayer.fontSize = 10
        subtitleLayer.alignmentMode = .left
        subtitleLayer.truncationMode = .end
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        let metrics = HUDGridMetrics(appearance: appearanceConfig)
        backgroundLayer.frame = bounds
        let previewBounds = CGRect(
            x: metrics.innerPadding,
            y: bounds.height - metrics.thumbnailHeight - metrics.innerPadding,
            width: bounds.width - metrics.innerPadding * 2,
            height: metrics.thumbnailHeight
        )
        previewShadowLayer.frame = previewBounds
        previewBackdropLayer.frame = previewBounds
        previewLayer.frame = fittedPreviewFrame(in: previewBounds)
        overlayLayer.frame = previewBounds
        let footerY = metrics.innerPadding
        iconLayer.frame = CGRect(
            x: metrics.innerPadding,
            y: footerY + 3,
            width: metrics.iconSize,
            height: metrics.iconSize
        )
        let textX = iconLayer.frame.maxX + 8
        let textWidth = max(24, bounds.width - textX - metrics.innerPadding - 16)
        if showsSubtitle {
            titleLayer.frame = CGRect(
                x: textX,
                y: footerY + 14,
                width: textWidth,
                height: 16
            )
            subtitleLayer.frame = CGRect(
                x: textX,
                y: footerY + 1,
                width: textWidth,
                height: 14
            )
        } else {
            titleLayer.frame = CGRect(
                x: textX,
                y: footerY + 6,
                width: textWidth,
                height: metrics.iconSize
            )
            subtitleLayer.frame = .zero
        }
        liveIndicatorLayer.frame = CGRect(
            x: bounds.width - metrics.innerPadding - 8,
            y: footerY + 9,
            width: 6,
            height: 6
        )
        badgeLayer.frame = CGRect(
            x: bounds.width - metrics.innerPadding - 20,
            y: bounds.height - metrics.innerPadding - 18,
            width: 18,
            height: 12
        )
    }

    func configure(item: HUDItem, appearance: AppearanceConfig) {
        let newIdentity = ThumbnailTileIdentity(
            windowId: item.snapshot.windowId,
            revision: item.snapshot.revision
        )
        let identityChanged = representedThumbnailIdentity != newIdentity
        let selectionChanged = representedThumbnailIdentity != nil
            && representedThumbnailIdentity == newIdentity
            && isSelected != item.isSelected

        self.item = item
        self.appearanceConfig = appearance
        currentVisualStyle = HUDVisualStyle.resolve(appearance: appearance)
        representedThumbnailIdentity = newIdentity
        isSelected = item.isSelected
        let subtitleText = item.label == item.title ? "" : item.label
        showsSubtitle = !subtitleText.isEmpty
        iconSurface = NSRunningApplication(processIdentifier: item.pid)?
            .icon?
            .cgImage(forProposedRect: nil, context: nil, hints: nil)

        withoutAnimations {
            titleLayer.string = item.title
            subtitleLayer.string = subtitleText
            subtitleLayer.isHidden = !showsSubtitle

            iconLayer.contents = iconSurface

            badgeLayer.isHidden = item.windowIndexInApp == nil
            badgeLayer.string = item.windowIndexInApp.map(String.init)
        }

        needsLayout = true
        applyChrome()
        applySelectionMotion(animated: selectionChanged)
        if identityChanged {
            clearThumbnailContents()
            applyThumbnail(item.thumbnailState, surface: nil)
        } else if item.thumbnailState == .unavailable {
            applyThumbnail(.unavailable, surface: nil)
        }
    }

    func applyThumbnail(_ state: ThumbnailState, surface: ThumbnailSurface?) {
        withoutAnimations {
            switch state {
                case .placeholder:
                    if let surface {
                        surface.apply(to: previewLayer)
                    }
                    let hasContents = previewLayer.contents != nil
                    if !hasContents {
                        previewLayer.contents = nil
                    }
                    currentThumbnailState = hasContents ? .stale : .placeholder
                case .stale:
                    surface?.apply(to: previewLayer)
                    currentThumbnailState = .stale
                case .freshStill:
                    surface?.apply(to: previewLayer)
                    currentThumbnailState = .freshStill
                case .liveSurface:
                    surface?.apply(to: previewLayer)
                    currentThumbnailState = .liveSurface
                case .unavailable:
                    previewLayer.contents = nil
                    currentThumbnailState = .unavailable
            }
            applyChrome()
        }
    }

    var debugPreviewHasContents: Bool {
        previewLayer.contents != nil
    }

    var debugShowsSubtitle: Bool {
        !subtitleLayer.isHidden
    }

    private func clearThumbnailContents() {
        previewLayer.contents = nil
        liveIndicatorLayer.isHidden = true
        currentThumbnailState = .placeholder
    }

    private func applyChrome() {
        guard let item else { return }
        let chrome = currentVisualStyle.tileChrome(
            isSelected: item.isSelected,
            thumbnailState: currentThumbnailState,
            showsSubtitle: showsSubtitle
        )
        currentSelectionStyle = chrome.selectionStyle
        backgroundLayer.backgroundColor = chrome.backgroundColor.cgColor
        backgroundLayer.borderColor = chrome.borderColor.cgColor
        backgroundLayer.borderWidth = chrome.borderWidth
        backgroundLayer.shadowColor = chrome.shadowColor.cgColor
        backgroundLayer.shadowOpacity = chrome.shadowOpacity
        backgroundLayer.shadowRadius = chrome.shadowRadius
        backgroundLayer.shadowOffset = chrome.shadowOffset

        previewShadowLayer.shadowColor = chrome.previewShadowColor.cgColor
        previewShadowLayer.shadowOpacity = chrome.previewShadowOpacity
        previewShadowLayer.shadowRadius = chrome.previewShadowRadius
        previewShadowLayer.shadowOffset = chrome.previewShadowOffset

        previewBackdropLayer.backgroundColor = chrome.previewBackdropColor.cgColor
        overlayLayer.backgroundColor = chrome.overlayColor.cgColor

        titleLayer.foregroundColor = chrome.titleColor.cgColor
        subtitleLayer.foregroundColor = chrome.subtitleColor.cgColor
        badgeLayer.backgroundColor = chrome.badgeFillColor.cgColor
        badgeLayer.foregroundColor = chrome.badgeTextColor.cgColor
        liveIndicatorLayer.backgroundColor = chrome.liveIndicatorColor.cgColor
        liveIndicatorLayer.isHidden = !chrome.showsLiveIndicator
    }

    private func applySelectionMotion(animated: Bool) {
        guard let layer else { return }

        let targetTransform: CATransform3D
        switch currentSelectionStyle {
            case .neutralFocusPlate:
                var transform = CATransform3DIdentity
                transform = CATransform3DTranslate(transform, 0, 3, 0)
                transform = CATransform3DScale(transform, 1.018, 1.018, 1)
                targetTransform = transform
            case .minimal:
                targetTransform = CATransform3DIdentity
        }

        if animated {
            let animation = CABasicAnimation(keyPath: "transform")
            animation.fromValue = layer.presentation()?.transform ?? layer.transform
            animation.toValue = targetTransform
            animation.duration = 0.14
            animation.timingFunction = CAMediaTimingFunction(name: .easeOut)
            layer.add(animation, forKey: "windnav.selection.lift")
        } else {
            layer.removeAnimation(forKey: "windnav.selection.lift")
        }

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.transform = targetTransform
        CATransaction.commit()
    }

    private func fittedPreviewFrame(in bounds: CGRect) -> CGRect {
        guard let item else { return bounds }

        let sourceSize = item.snapshot.frame.size
        guard sourceSize.width > 1, sourceSize.height > 1 else { return bounds }

        let widthScale = bounds.width / sourceSize.width
        let heightScale = bounds.height / sourceSize.height
        let scale = min(widthScale, heightScale, 1)
        let fittedWidth = max(1, (sourceSize.width * scale).rounded())
        let fittedHeight = max(1, (sourceSize.height * scale).rounded())

        return CGRect(
            x: bounds.midX - (fittedWidth / 2),
            y: bounds.midY - (fittedHeight / 2),
            width: fittedWidth,
            height: fittedHeight
        )
    }
}

struct HUDGridRow: Equatable {
    let tileIndices: [Int]
    let frame: CGRect
}

struct HUDGridLayoutResult: Equatable {
    let viewportSize: CGSize
    let documentSize: CGSize
    let tileFrames: [CGRect]
    let rows: [HUDGridRow]

    static let empty = HUDGridLayoutResult(
        viewportSize: .zero,
        documentSize: .zero,
        tileFrames: [],
        rows: []
    )
}

enum HUDTileSelectionStyle: Equatable {
    case neutralFocusPlate
    case minimal
}

struct HUDPanelChromeStyle {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode
    let cornerRadius: CGFloat
    let tintColor: NSColor
    let shadowColor: NSColor
    let shadowOpacity: Float
    let shadowRadius: CGFloat
    let shadowOffset: CGSize
}

struct HUDTileChromeStyle {
    let selectionStyle: HUDTileSelectionStyle
    let backgroundColor: NSColor
    let borderColor: NSColor
    let borderWidth: CGFloat
    let shadowColor: NSColor
    let shadowOpacity: Float
    let shadowRadius: CGFloat
    let shadowOffset: CGSize
    let previewShadowColor: NSColor
    let previewShadowOpacity: Float
    let previewShadowRadius: CGFloat
    let previewShadowOffset: CGSize
    let previewBackdropColor: NSColor
    let overlayColor: NSColor
    let titleColor: NSColor
    let subtitleColor: NSColor
    let badgeFillColor: NSColor
    let badgeTextColor: NSColor
    let liveIndicatorColor: NSColor
    let showsLiveIndicator: Bool
}

struct HUDVisualStyle {
    let panel: HUDPanelChromeStyle

    static func resolve(appearance: AppearanceConfig) -> HUDVisualStyle {
        let panel = HUDPanelChromeStyle(
            material: .hudWindow,
            blendingMode: .behindWindow,
            cornerRadius: 24,
            tintColor: NSColor.black.withAlphaComponent(0.24),
            shadowColor: NSColor.black.withAlphaComponent(0.55),
            shadowOpacity: 0.34,
            shadowRadius: 26,
            shadowOffset: CGSize(width: 0, height: -8)
        )
        return HUDVisualStyle(panel: panel)
    }

    func tileChrome(
        isSelected: Bool,
        thumbnailState: ThumbnailState,
        showsSubtitle: Bool
    ) -> HUDTileChromeStyle {
        let titleColor = isSelected
            ? NSColor.white.withAlphaComponent(0.96)
            : NSColor.white.withAlphaComponent(0.88)
        let subtitleColor = isSelected
            ? NSColor.white.withAlphaComponent(0.68)
            : NSColor.white.withAlphaComponent(showsSubtitle ? 0.52 : 0.0)

        if isSelected {
            return HUDTileChromeStyle(
                selectionStyle: .neutralFocusPlate,
                backgroundColor: NSColor(white: 0.06, alpha: 0.92),
                borderColor: NSColor.white.withAlphaComponent(0.18),
                borderWidth: 1,
                shadowColor: NSColor.black.withAlphaComponent(0.45),
                shadowOpacity: 0.26,
                shadowRadius: 18,
                shadowOffset: CGSize(width: 0, height: -5),
                previewShadowColor: NSColor.black.withAlphaComponent(0.44),
                previewShadowOpacity: 0.20,
                previewShadowRadius: 14,
                previewShadowOffset: CGSize(width: 0, height: -2),
                previewBackdropColor: previewBackdropColor(for: thumbnailState, selected: true),
                overlayColor: overlayColor(for: thumbnailState),
                titleColor: titleColor,
                subtitleColor: subtitleColor,
                badgeFillColor: NSColor.white.withAlphaComponent(0.16),
                badgeTextColor: NSColor.white.withAlphaComponent(0.9),
                liveIndicatorColor: NSColor.systemGreen.withAlphaComponent(0.82),
                showsLiveIndicator: thumbnailState == .liveSurface
            )
        }

        return HUDTileChromeStyle(
            selectionStyle: .minimal,
            backgroundColor: NSColor.clear,
            borderColor: NSColor.clear,
            borderWidth: 0,
            shadowColor: NSColor.clear,
            shadowOpacity: 0,
            shadowRadius: 0,
            shadowOffset: .zero,
            previewShadowColor: NSColor.black.withAlphaComponent(0.38),
            previewShadowOpacity: 0.12,
            previewShadowRadius: 10,
            previewShadowOffset: CGSize(width: 0, height: -1),
            previewBackdropColor: previewBackdropColor(for: thumbnailState, selected: false),
            overlayColor: overlayColor(for: thumbnailState),
            titleColor: titleColor,
            subtitleColor: subtitleColor,
            badgeFillColor: NSColor.white.withAlphaComponent(0.08),
            badgeTextColor: NSColor.white.withAlphaComponent(0.76),
            liveIndicatorColor: NSColor.systemGreen.withAlphaComponent(0.72),
            showsLiveIndicator: thumbnailState == .liveSurface
        )
    }

    private func previewBackdropColor(for state: ThumbnailState, selected: Bool) -> NSColor {
        switch state {
            case .placeholder:
                return NSColor.white.withAlphaComponent(selected ? 0.045 : 0.035)
            case .stale:
                return NSColor.white.withAlphaComponent(selected ? 0.04 : 0.03)
            case .freshStill, .liveSurface:
                return .clear
            case .unavailable:
                return NSColor.white.withAlphaComponent(selected ? 0.06 : 0.05)
        }
    }

    private func overlayColor(for state: ThumbnailState) -> NSColor {
        switch state {
            case .placeholder:
                return NSColor.black.withAlphaComponent(0.05)
            case .stale:
                return NSColor.black.withAlphaComponent(0.08)
            case .freshStill, .liveSurface:
                return .clear
            case .unavailable:
                return NSColor.black.withAlphaComponent(0.18)
        }
    }
}

enum HUDGridLayout {
    static func layout(
        itemCount: Int,
        metrics: HUDGridMetrics,
        maximumSize: CGSize
    ) -> HUDGridLayoutResult {
        guard itemCount > 0 else {
            let emptySize = CGSize(
                width: metrics.tileWidth + metrics.outerPadding * 2,
                height: metrics.tileHeight + metrics.outerPadding * 2
            )
            return HUDGridLayoutResult(
                viewportSize: emptySize,
                documentSize: emptySize,
                tileFrames: [],
                rows: []
            )
        }

        let usableWidth = max(metrics.tileWidth, maximumSize.width - metrics.outerPadding * 2)
        let maxColumns = max(
            1,
            Int(((usableWidth + metrics.tileSpacing) / (metrics.tileWidth + metrics.tileSpacing)).rounded(.down))
        )

        var rowTileIndices: [[Int]] = []
        var nextIndex = 0
        while nextIndex < itemCount {
            let endIndex = min(itemCount, nextIndex + maxColumns)
            rowTileIndices.append(Array(nextIndex..<endIndex))
            nextIndex = endIndex
        }

        let rowWidths = rowTileIndices.map { indices in
            CGFloat(indices.count) * metrics.tileWidth
                + CGFloat(max(indices.count - 1, 0)) * metrics.tileSpacing
        }
        let contentWidth = min(
            maximumSize.width,
            (rowWidths.max() ?? metrics.tileWidth) + metrics.outerPadding * 2
        )

        var tileFrames = Array(repeating: CGRect.zero, count: itemCount)
        var rows: [HUDGridRow] = []
        var currentY = metrics.outerPadding

        for (rowIndex, indices) in rowTileIndices.enumerated() {
            let rowWidth = rowWidths[rowIndex]
            let rowX = metrics.outerPadding + max(
                0,
                ((contentWidth - metrics.outerPadding * 2 - rowWidth) / 2).rounded()
            )
            let rowFrame = CGRect(
                x: rowX,
                y: currentY,
                width: rowWidth,
                height: metrics.tileHeight
            )
            rows.append(HUDGridRow(tileIndices: indices, frame: rowFrame))

            for (columnIndex, tileIndex) in indices.enumerated() {
                tileFrames[tileIndex] = CGRect(
                    x: rowX + CGFloat(columnIndex) * (metrics.tileWidth + metrics.tileSpacing),
                    y: currentY,
                    width: metrics.tileWidth,
                    height: metrics.tileHeight
                )
            }

            currentY += metrics.tileHeight + metrics.rowSpacing
        }

        let documentHeight = metrics.outerPadding * 2
            + CGFloat(rowTileIndices.count) * metrics.tileHeight
            + CGFloat(max(rowTileIndices.count - 1, 0)) * metrics.rowSpacing
        let viewportSize = CGSize(
            width: contentWidth,
            height: min(maximumSize.height, documentHeight)
        )

        return HUDGridLayoutResult(
            viewportSize: viewportSize,
            documentSize: CGSize(width: contentWidth, height: documentHeight),
            tileFrames: tileFrames,
            rows: rows
        )
    }

    static func revealRect(for tileFrame: CGRect) -> CGRect {
        tileFrame.insetBy(dx: -14, dy: -10)
    }
}

struct HUDGridMetrics {
    let outerPadding: CGFloat = 18
    let innerPadding: CGFloat
    let tileSpacing: CGFloat
    let rowSpacing: CGFloat
    let tileWidth: CGFloat
    let tileHeight: CGFloat
    let thumbnailHeight: CGFloat
    let iconSize: CGFloat
    let thumbnailSize: CGSize

    init(appearance: AppearanceConfig) {
        iconSize = max(18, min(22, CGFloat(appearance.iconSize)))
        innerPadding = max(8, CGFloat(appearance.itemPadding + 1))
        tileSpacing = max(8, CGFloat(appearance.itemSpacing))
        rowSpacing = max(12, tileSpacing + 2)
        tileWidth = max(144, iconSize * 6.45)
        thumbnailHeight = max(82, tileWidth * 0.57)
        tileHeight = thumbnailHeight + innerPadding * 2 + iconSize + 18
        thumbnailSize = CGSize(
            width: tileWidth - innerPadding * 2,
            height: thumbnailHeight
        )
    }

    func maximumPanelSize(for visibleFrame: CGRect) -> CGSize {
        CGSize(
            width: max(tileWidth + outerPadding * 2, visibleFrame.width * 0.8),
            height: max(tileHeight + outerPadding * 2, visibleFrame.height * 0.64)
        )
    }
}

private func withoutAnimations(_ updates: () -> Void) {
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    updates()
    CATransaction.commit()
}

enum HUDBadgeFormatter {
    static func badgeText(for windowIndexInApp: Int?) -> String? {
        guard let windowIndexInApp, windowIndexInApp > 0 else { return nil }
        return "\(windowIndexInApp)"
    }
}
