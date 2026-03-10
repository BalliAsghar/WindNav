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

    func show(model: HUDModel, appearance: AppearanceConfig, hud: HUDConfig) {
        guard !model.items.isEmpty else {
            hide()
            return
        }

        let contentView = ensureContentView()
        let visibleFrame = NSScreen.main?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1280, height: 800)
        let presentationMode = HUDPresentationMode(hud: hud)
        let thumbnailMetrics = HUDGridMetrics(appearance: appearance, hud: hud)
        let maximumPanelSize = Self.maximumPanelSize(
            itemCount: model.items.count,
            for: presentationMode,
            appearance: appearance,
            hud: hud,
            visibleFrame: visibleFrame
        )
        let contentSize = contentView.apply(
            model: model,
            appearance: appearance,
            hud: hud,
            maximumSize: maximumPanelSize,
            presentationMode: presentationMode
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
        let shouldCaptureThumbnails = Self.shouldCaptureThumbnails(
            hud: hud,
            screenRecordingGranted: screenRecordingGranted
        )
        Task {
            await captureScheduler.show(
                model: model,
                targetSize: thumbnailMetrics.thumbnailSize,
                screenRecordingGranted: shouldCaptureThumbnails
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

    static func shouldCaptureThumbnails(
        hud: HUDConfig,
        screenRecordingGranted: Bool
    ) -> Bool {
        hud.thumbnails && screenRecordingGranted
    }

    private static func maximumPanelSize(
        itemCount: Int,
        for presentationMode: HUDPresentationMode,
        appearance: AppearanceConfig,
        hud: HUDConfig,
        visibleFrame: CGRect
    ) -> CGSize {
        HUDPanelSizePolicy.maximumPanelSize(
            itemCount: itemCount,
            appearance: appearance,
            hud: hud,
            visibleFrame: visibleFrame,
            presentationMode: presentationMode
        )
    }
}

private enum HUDPanelSizePolicy {
    static func maximumPanelSize(
        itemCount: Int,
        appearance: AppearanceConfig,
        hud: HUDConfig,
        visibleFrame: CGRect,
        presentationMode: HUDPresentationMode
    ) -> CGSize {
        let sharedBudget = HUDGridMetrics(appearance: appearance, hud: hud).maximumPanelSize(for: visibleFrame)
        guard presentationMode == .iconOnly else {
            return sharedBudget
        }

        let iconMetrics = HUDIconStripMetrics(appearance: appearance)
        let minimumWidth = iconMetrics.tileWidth + iconMetrics.outerPadding * 2
        let estimatedRowWidth = CGFloat(itemCount) * iconMetrics.tileWidth
            + CGFloat(max(itemCount - 1, 0)) * iconMetrics.tileSpacing
            + iconMetrics.outerPadding * 2

        return CGSize(
            width: min(sharedBudget.width, max(minimumWidth, estimatedRowWidth)),
            height: sharedBudget.height
        )
    }
}

extension MinimalHUDController {
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
    private let iconProvider = HUDIconProvider()
    private var tileViews: [HUDThumbnailTileView] = []
    private var currentModel: HUDModel?
    private var currentAppearance: AppearanceConfig = .default
    private var currentHUD: HUDConfig = .default
    private var currentLayout = HUDLayoutResult.empty
    private var currentVisualStyle = HUDVisualStyle.resolve(appearance: .default)
    private var currentPresentationMode: HUDPresentationMode = .thumbnails

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
        scrollView.hasVerticalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
        scrollView.contentView.postsBoundsChangedNotifications = true
        scrollView.documentView = documentView

        addSubview(scrollView)
        applyPanelStyle(currentVisualStyle.panel(for: .thumbnails))
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
    func apply(
        model: HUDModel,
        appearance: AppearanceConfig,
        hud: HUDConfig,
        maximumSize: CGSize,
        presentationMode: HUDPresentationMode
    ) -> CGSize {
        let modeChanged = currentPresentationMode != presentationMode
        currentModel = model
        currentAppearance = appearance
        currentHUD = hud
        currentPresentationMode = presentationMode
        currentVisualStyle = HUDVisualStyle.resolve(appearance: appearance)
        currentLayout = layoutResult(
            itemCount: model.items.count,
            appearance: appearance,
            hud: hud,
            maximumSize: maximumSize,
            presentationMode: presentationMode
        )
        applyPanelStyle(currentVisualStyle.panel(for: presentationMode))

        ensureTileCount(model.items.count)
        withoutAnimations {
            if modeChanged {
                scrollView.contentView.scroll(to: .zero)
                scrollView.reflectScrolledClipView(scrollView.contentView)
            }

            for (index, item) in model.items.enumerated() {
                let tile = tileViews[index]
                tile.isHidden = false
                tile.frame = currentLayout.tileFrames[index]
                tile.configure(
                    item: item,
                    appearance: appearance,
                    hud: hud,
                    presentationMode: presentationMode,
                    iconProvider: iconProvider
                )
            }

            for index in model.items.count..<tileViews.count {
                tileViews[index].isHidden = true
            }

            documentView.frame = CGRect(origin: .zero, size: currentLayout.documentSize)
            scrollView.hasVerticalScroller = presentationMode == .thumbnails
                && currentLayout.documentSize.height > currentLayout.viewportSize.height + 1
        }

        return currentLayout.viewportSize
    }

    func apply(update: ThumbnailUpdate) {
        guard currentPresentationMode == .thumbnails else { return }
        guard let model = currentModel else { return }
        guard let index = model.items.firstIndex(where: {
            $0.snapshot.windowId == update.windowId && $0.snapshot.revision == update.revision
        }) else { return }
        tileViews[index].applyThumbnail(update.state, surface: update.surface)
    }

    func preferredSize(
        appearance: AppearanceConfig,
        hud: HUDConfig,
        maximumSize: CGSize,
        presentationMode: HUDPresentationMode
    ) -> CGSize {
        let itemCount = currentModel?.items.count ?? 0
        return layoutResult(
            itemCount: itemCount,
            appearance: appearance,
            hud: hud,
            maximumSize: maximumSize,
            presentationMode: presentationMode
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
        let tileFrame = tileViews[selectedIndex].frame
        let revealRect = switch currentPresentationMode {
        case .thumbnails:
            HUDGridLayout.revealRect(for: tileFrame)
        case .iconOnly:
            HUDIconStripLayout.revealRect(for: tileFrame)
        }
        documentView.scrollToVisible(revealRect)
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

    private func layoutResult(
        itemCount: Int,
        appearance: AppearanceConfig,
        hud: HUDConfig,
        maximumSize: CGSize,
        presentationMode: HUDPresentationMode
    ) -> HUDLayoutResult {
        switch presentationMode {
        case .thumbnails:
            let result = HUDGridLayout.layout(
                itemCount: itemCount,
                metrics: HUDGridMetrics(appearance: appearance, hud: hud),
                maximumSize: maximumSize
            )
            return HUDLayoutResult(
                viewportSize: result.viewportSize,
                documentSize: result.documentSize,
                tileFrames: result.tileFrames
            )
        case .iconOnly:
            let result = HUDIconStripLayout.layout(
                itemCount: itemCount,
                metrics: HUDIconStripMetrics(appearance: appearance),
                maximumSize: maximumSize
            )
            return HUDLayoutResult(
                viewportSize: result.viewportSize,
                documentSize: result.documentSize,
                tileFrames: result.tileFrames
            )
        }
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
    private var hudConfig: HUDConfig = .default
    private var iconSurface: CGImage?
    private var representedThumbnailIdentity: ThumbnailTileIdentity?
    private var currentThumbnailState: ThumbnailState = .placeholder
    private var currentVisualStyle = HUDVisualStyle.resolve(appearance: .default)
    private var currentSelectionStyle: HUDTileSelectionStyle = .minimal
    private var currentPresentationMode: HUDPresentationMode = .thumbnails
    private var isSelected = false
    private var footerLayout = HUDFooterLayout.zero

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
        switch currentPresentationMode {
        case .thumbnails:
            let metrics = HUDGridMetrics(appearance: appearanceConfig, hud: hudConfig)
            backgroundLayer.frame = bounds
            let headerY = metrics.innerPadding
            let headerFrame = CGRect(
                x: metrics.innerPadding,
                y: bounds.height - headerY - metrics.headerHeight,
                width: bounds.width - metrics.innerPadding * 2,
                height: metrics.headerHeight
            )
            let thumbnailBounds = CGRect(
                x: metrics.innerPadding,
                y: metrics.innerPadding,
                width: bounds.width - metrics.innerPadding * 2,
                height: metrics.thumbnailHeight
            )
            previewShadowLayer.frame = thumbnailBounds
            previewBackdropLayer.frame = thumbnailBounds
            previewLayer.frame = fittedPreviewFrame(in: thumbnailBounds)
            overlayLayer.frame = thumbnailBounds
            footerLayout = makeHeaderLayout(metrics: metrics, headerFrame: headerFrame)
            iconLayer.frame = footerLayout.iconFrame
            titleLayer.frame = footerLayout.titleFrame
            subtitleLayer.frame = footerLayout.subtitleFrame
            liveIndicatorLayer.frame = CGRect(
                x: bounds.width - metrics.innerPadding - 8,
                y: headerY + 9,
                width: 6,
                height: 6
            )
            badgeLayer.frame = CGRect(
                x: bounds.width - metrics.innerPadding - 20,
                y: headerY + metrics.headerHeight - 12,
                width: 18,
                height: 12
            )
        case .iconOnly:
            let metrics = HUDIconStripMetrics(appearance: appearanceConfig)
            let plateFrame = CGRect(
                x: bounds.midX - (metrics.selectionPlateSize / 2),
                y: metrics.labelHeight + metrics.labelSpacing,
                width: metrics.selectionPlateSize,
                height: metrics.selectionPlateSize
            )
            let iconFrame = CGRect(
                x: bounds.midX - (metrics.iconSize / 2),
                y: plateFrame.midY - (metrics.iconSize / 2),
                width: metrics.iconSize,
                height: metrics.iconSize
            )
            backgroundLayer.frame = isSelected ? plateFrame : .zero
            previewShadowLayer.frame = .zero
            previewBackdropLayer.frame = .zero
            previewLayer.frame = .zero
            overlayLayer.frame = .zero
            iconLayer.frame = iconFrame
            titleLayer.frame = CGRect(
                x: 0,
                y: 0,
                width: bounds.width,
                height: metrics.labelHeight
            )
            subtitleLayer.frame = .zero
            liveIndicatorLayer.frame = .zero
            let badgeSize = CGSize(width: 18, height: 14)
            let badgeAnchorFrame = isSelected ? plateFrame : iconFrame
            badgeLayer.frame = CGRect(
                x: min(bounds.width - badgeSize.width, badgeAnchorFrame.maxX - badgeSize.width * 0.45),
                y: min(bounds.height - badgeSize.height, badgeAnchorFrame.maxY - badgeSize.height * 0.25),
                width: badgeSize.width,
                height: badgeSize.height
            ).integral
        }
    }

    func configure(
        item: HUDItem,
        appearance: AppearanceConfig,
        hud: HUDConfig,
        presentationMode: HUDPresentationMode,
        iconProvider: HUDIconProvider
    ) {
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
        self.hudConfig = hud
        self.currentPresentationMode = presentationMode
        currentVisualStyle = HUDVisualStyle.resolve(appearance: appearance)
        representedThumbnailIdentity = newIdentity
        isSelected = item.isSelected
        let titleText: String
        switch presentationMode {
        case .thumbnails:
            titleText = item.title
        case .iconOnly:
            titleText = item.isSelected ? WindowSnapshotSupport.appLabel(for: [item.snapshot]) : ""
        }
        let iconPointSize = switch presentationMode {
        case .thumbnails:
            HUDGridMetrics(appearance: appearance, hud: hud).iconSize
        case .iconOnly:
            HUDIconStripMetrics(appearance: appearance).iconSize
        }
        let scale = window?.backingScaleFactor
            ?? NSScreen.main?.backingScaleFactor
            ?? 2
        iconSurface = iconProvider.icon(
            for: item.snapshot,
            pointSize: iconPointSize,
            scale: scale
        )

        withoutAnimations {
            titleLayer.string = titleText
            subtitleLayer.string = ""
            titleLayer.isHidden = presentationMode == .iconOnly && !item.isSelected
            subtitleLayer.isHidden = true
            if presentationMode == .iconOnly {
                titleLayer.font = NSFont.systemFont(ofSize: 15, weight: .medium)
                titleLayer.fontSize = 15
            } else {
                titleLayer.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
                titleLayer.fontSize = 12
            }

            iconLayer.contents = iconSurface

            badgeLayer.string = HUDBadgeFormatter.badgeText(for: item.windowIndexInApp)
            badgeLayer.isHidden = badgeLayer.string == nil
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

    var debugTitleFrame: CGRect {
        titleLayer.frame
    }

    var debugSubtitleFrame: CGRect {
        subtitleLayer.frame
    }

    var debugIconFrame: CGRect {
        iconLayer.frame
    }

    var debugTitleIsHidden: Bool {
        titleLayer.isHidden
    }

    var debugTitleString: String {
        (titleLayer.string as? String) ?? ""
    }

    var debugBadgeIsHidden: Bool {
        badgeLayer.isHidden
    }

    var debugBadgeString: String {
        (badgeLayer.string as? String) ?? ""
    }

    var debugBadgeFrame: CGRect {
        badgeLayer.frame
    }

    private func clearThumbnailContents() {
        previewLayer.contents = nil
        liveIndicatorLayer.isHidden = true
        currentThumbnailState = .placeholder
    }

    private func applyChrome() {
        guard let item else { return }
        switch currentPresentationMode {
        case .thumbnails:
            let chrome = currentVisualStyle.tileChrome(
                isSelected: item.isSelected,
                thumbnailState: currentThumbnailState
            )
            currentSelectionStyle = chrome.selectionStyle
            backgroundLayer.cornerRadius = 14
            backgroundLayer.cornerCurve = .continuous
            backgroundLayer.backgroundColor = chrome.backgroundColor.cgColor
            backgroundLayer.borderColor = chrome.borderColor.cgColor
            backgroundLayer.borderWidth = chrome.borderWidth
            backgroundLayer.shadowColor = chrome.shadowColor.cgColor
            backgroundLayer.shadowOpacity = chrome.shadowOpacity
            backgroundLayer.shadowRadius = chrome.shadowRadius
            backgroundLayer.shadowOffset = chrome.shadowOffset

            previewShadowLayer.isHidden = false
            previewBackdropLayer.isHidden = false
            previewLayer.isHidden = false
            overlayLayer.isHidden = false
            previewShadowLayer.shadowColor = chrome.previewShadowColor.cgColor
            previewShadowLayer.shadowOpacity = chrome.previewShadowOpacity
            previewShadowLayer.shadowRadius = chrome.previewShadowRadius
            previewShadowLayer.shadowOffset = chrome.previewShadowOffset
            previewBackdropLayer.backgroundColor = chrome.previewBackdropColor.cgColor
            overlayLayer.backgroundColor = chrome.overlayColor.cgColor

            iconLayer.cornerRadius = 7
            iconLayer.cornerCurve = .continuous
            iconLayer.masksToBounds = true
            iconLayer.contentsGravity = .resizeAspectFill
            iconLayer.borderWidth = 0.5
            iconLayer.borderColor = NSColor.white.withAlphaComponent(0.08).cgColor

            titleLayer.alignmentMode = .left
            titleLayer.foregroundColor = chrome.titleColor.cgColor
            subtitleLayer.foregroundColor = chrome.subtitleColor.cgColor
            badgeLayer.backgroundColor = chrome.badgeFillColor.cgColor
            badgeLayer.foregroundColor = chrome.badgeTextColor.cgColor
            liveIndicatorLayer.backgroundColor = chrome.liveIndicatorColor.cgColor
            liveIndicatorLayer.isHidden = !chrome.showsLiveIndicator
        case .iconOnly:
            let chrome = currentVisualStyle.iconTileChrome(isSelected: item.isSelected)
            currentSelectionStyle = chrome.selectionStyle
            backgroundLayer.backgroundColor = chrome.plateColor.cgColor
            backgroundLayer.borderColor = chrome.plateBorderColor.cgColor
            backgroundLayer.borderWidth = chrome.plateBorderWidth
            backgroundLayer.shadowColor = chrome.plateShadowColor.cgColor
            backgroundLayer.shadowOpacity = chrome.plateShadowOpacity
            backgroundLayer.shadowRadius = chrome.plateShadowRadius
            backgroundLayer.shadowOffset = chrome.plateShadowOffset
            backgroundLayer.cornerRadius = chrome.plateCornerRadius
            backgroundLayer.cornerCurve = .continuous

            previewShadowLayer.isHidden = true
            previewBackdropLayer.isHidden = true
            previewLayer.isHidden = true
            overlayLayer.isHidden = true

            iconLayer.cornerRadius = 0
            iconLayer.borderWidth = 0
            iconLayer.borderColor = NSColor.clear.cgColor
            iconLayer.masksToBounds = false
            iconLayer.contentsGravity = .resizeAspect

            titleLayer.alignmentMode = .center
            titleLayer.foregroundColor = chrome.labelColor.cgColor
            subtitleLayer.foregroundColor = NSColor.clear.cgColor
            badgeLayer.backgroundColor = chrome.badgeFillColor.cgColor
            badgeLayer.foregroundColor = chrome.badgeTextColor.cgColor
            liveIndicatorLayer.isHidden = true
        }
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
            case .nativeIconPlate:
                var transform = CATransform3DIdentity
                transform = CATransform3DTranslate(transform, 0, 4, 0)
                transform = CATransform3DScale(transform, 1.024, 1.024, 1)
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

    private func makeHeaderLayout(metrics: HUDGridMetrics, headerFrame: CGRect) -> HUDFooterLayout {
        let iconFrame = CGRect(
            x: headerFrame.minX,
            y: headerFrame.minY + (headerFrame.height - metrics.iconSize) / 2,
            width: metrics.iconSize,
            height: metrics.iconSize
        )
        let textX = iconFrame.maxX + 8
        let textWidth = max(24, headerFrame.width - textX - 16)
        let titleFrame = CGRect(
            x: textX,
            y: headerFrame.minY + (headerFrame.height - 16) / 2,
            width: textWidth,
            height: 16
        )
        let subtitleFrame = CGRect(
            x: textX,
            y: headerFrame.minY + 2,
            width: 0,
            height: 0
        )
        return HUDFooterLayout(
            iconFrame: iconFrame,
            titleFrame: titleFrame,
            subtitleFrame: subtitleFrame
        )
    }
}

private struct HUDFooterLayout {
    let iconFrame: CGRect
    let titleFrame: CGRect
    let subtitleFrame: CGRect

    static let zero = HUDFooterLayout(iconFrame: .zero, titleFrame: .zero, subtitleFrame: .zero)
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

struct HUDLayoutResult: Equatable {
    let viewportSize: CGSize
    let documentSize: CGSize
    let tileFrames: [CGRect]

    static let empty = HUDLayoutResult(
        viewportSize: .zero,
        documentSize: .zero,
        tileFrames: []
    )
}

enum HUDTileSelectionStyle: Equatable {
    case neutralFocusPlate
    case nativeIconPlate
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

struct HUDIconTileChromeStyle {
    let selectionStyle: HUDTileSelectionStyle
    let plateColor: NSColor
    let plateBorderColor: NSColor
    let plateBorderWidth: CGFloat
    let plateShadowColor: NSColor
    let plateShadowOpacity: Float
    let plateShadowRadius: CGFloat
    let plateShadowOffset: CGSize
    let plateCornerRadius: CGFloat
    let labelColor: NSColor
    let badgeFillColor: NSColor
    let badgeTextColor: NSColor
}

struct HUDVisualStyle {
    static func resolve(appearance: AppearanceConfig) -> HUDVisualStyle {
        HUDVisualStyle()
    }

    func panel(for presentationMode: HUDPresentationMode) -> HUDPanelChromeStyle {
        switch presentationMode {
        case .thumbnails:
            return HUDPanelChromeStyle(
                material: .hudWindow,
                blendingMode: .behindWindow,
                cornerRadius: 24,
                tintColor: NSColor.black.withAlphaComponent(0.24),
                shadowColor: NSColor.black.withAlphaComponent(0.55),
                shadowOpacity: 0.34,
                shadowRadius: 26,
                shadowOffset: CGSize(width: 0, height: -8)
            )
        case .iconOnly:
            return HUDPanelChromeStyle(
                material: .hudWindow,
                blendingMode: .behindWindow,
                cornerRadius: 30,
                tintColor: NSColor.black.withAlphaComponent(0.18),
                shadowColor: NSColor.black.withAlphaComponent(0.48),
                shadowOpacity: 0.28,
                shadowRadius: 24,
                shadowOffset: CGSize(width: 0, height: -6)
            )
        }
    }

    func tileChrome(
        isSelected: Bool,
        thumbnailState: ThumbnailState
    ) -> HUDTileChromeStyle {
        let titleColor = isSelected
            ? NSColor.white.withAlphaComponent(0.96)
            : NSColor.white.withAlphaComponent(0.88)
        let subtitleColor = NSColor.white.withAlphaComponent(0.0)

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

    func iconTileChrome(isSelected: Bool) -> HUDIconTileChromeStyle {
        if isSelected {
            return HUDIconTileChromeStyle(
                selectionStyle: .nativeIconPlate,
                plateColor: NSColor(white: 0.02, alpha: 0.94),
                plateBorderColor: NSColor.white.withAlphaComponent(0.08),
                plateBorderWidth: 0.6,
                plateShadowColor: NSColor.black.withAlphaComponent(0.4),
                plateShadowOpacity: 0.24,
                plateShadowRadius: 16,
                plateShadowOffset: CGSize(width: 0, height: -4),
                plateCornerRadius: 18,
                labelColor: NSColor.white.withAlphaComponent(0.82),
                badgeFillColor: NSColor.white.withAlphaComponent(0.18),
                badgeTextColor: NSColor.white.withAlphaComponent(0.92)
            )
        }

        return HUDIconTileChromeStyle(
            selectionStyle: .minimal,
            plateColor: .clear,
            plateBorderColor: .clear,
            plateBorderWidth: 0,
            plateShadowColor: .clear,
            plateShadowOpacity: 0,
            plateShadowRadius: 0,
            plateShadowOffset: .zero,
            plateCornerRadius: 18,
            labelColor: NSColor.clear,
            badgeFillColor: NSColor.black.withAlphaComponent(0.68),
            badgeTextColor: NSColor.white.withAlphaComponent(0.88)
        )
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

struct HUDIconStripLayoutResult: Equatable {
    let viewportSize: CGSize
    let documentSize: CGSize
    let tileFrames: [CGRect]

    static let empty = HUDIconStripLayoutResult(
        viewportSize: .zero,
        documentSize: .zero,
        tileFrames: []
    )
}

enum HUDIconStripLayout {
    static func layout(
        itemCount: Int,
        metrics: HUDIconStripMetrics,
        maximumSize: CGSize
    ) -> HUDIconStripLayoutResult {
        guard itemCount > 0 else {
            let emptySize = CGSize(
                width: metrics.tileWidth + metrics.outerPadding * 2,
                height: metrics.tileHeight + metrics.outerPadding * 2
            )
            return HUDIconStripLayoutResult(
                viewportSize: emptySize,
                documentSize: emptySize,
                tileFrames: []
            )
        }

        let rowWidth = CGFloat(itemCount) * metrics.tileWidth
            + CGFloat(max(itemCount - 1, 0)) * metrics.tileSpacing
        let contentWidth = rowWidth + metrics.outerPadding * 2
        let viewportWidth = min(maximumSize.width, contentWidth)
        let rowOriginX = metrics.outerPadding + max(
            0,
            ((viewportWidth - metrics.outerPadding * 2 - rowWidth) / 2).rounded()
        )
        let y = metrics.outerPadding

        let tileFrames = (0..<itemCount).map { index in
            CGRect(
                x: rowOriginX + CGFloat(index) * (metrics.tileWidth + metrics.tileSpacing),
                y: y,
                width: metrics.tileWidth,
                height: metrics.tileHeight
            )
        }

        return HUDIconStripLayoutResult(
            viewportSize: CGSize(
                width: viewportWidth,
                height: min(maximumSize.height, metrics.tileHeight + metrics.outerPadding * 2)
            ),
            documentSize: CGSize(
                width: max(contentWidth, viewportWidth),
                height: metrics.tileHeight + metrics.outerPadding * 2
            ),
            tileFrames: tileFrames
        )
    }

    static func revealRect(for tileFrame: CGRect) -> CGRect {
        tileFrame.insetBy(dx: -22, dy: -6)
    }
}

struct HUDGridMetrics {
    let outerPadding: CGFloat
    let innerPadding: CGFloat
    let tileSpacing: CGFloat
    let rowSpacing: CGFloat
    let tileWidth: CGFloat
    let tileHeight: CGFloat
    let thumbnailHeight: CGFloat
    let headerHeight: CGFloat
    let iconSize: CGFloat
    let thumbnailSize: CGSize

    init(appearance _: AppearanceConfig, hud: HUDConfig) {
        let preset = HUDThumbnailMetricsPreset(hud.size)
        outerPadding = preset.outerPadding
        iconSize = preset.iconSize
        headerHeight = preset.headerHeight
        innerPadding = preset.innerPadding
        tileSpacing = preset.tileSpacing
        rowSpacing = preset.rowSpacing
        tileWidth = preset.tileWidth
        thumbnailHeight = preset.thumbnailHeight
        tileHeight = preset.tileHeight
        thumbnailSize = CGSize(
            width: tileWidth - innerPadding * 2,
            height: thumbnailHeight
        )
    }

    func maximumPanelSize(for visibleFrame: CGRect) -> CGSize {
        CGSize(
            width: max(tileWidth + outerPadding * 2, visibleFrame.width * 0.8),
            height: max(tileHeight + outerPadding * 2, visibleFrame.height * 0.8)
        )
    }
}

private struct HUDThumbnailMetricsPreset {
    let outerPadding: CGFloat
    let innerPadding: CGFloat
    let tileSpacing: CGFloat
    let rowSpacing: CGFloat
    let tileWidth: CGFloat
    let thumbnailHeight: CGFloat
    let tileHeight: CGFloat
    let iconSize: CGFloat
    let headerHeight: CGFloat

    init(_ size: HUDThumbnailSizePreset) {
        switch size {
        case .small:
            outerPadding = 18
            innerPadding = 12
            tileSpacing = 1
            rowSpacing = 12
            iconSize = 16
            let headerHeight = iconSize + 13
            self.headerHeight = headerHeight
            tileWidth = 220
            thumbnailHeight = 140
            tileHeight = headerHeight + innerPadding + thumbnailHeight + innerPadding
        case .medium:
            outerPadding = 18
            innerPadding = 12
            tileSpacing = 1
            rowSpacing = 12
            iconSize = 26
            let headerHeight = iconSize + 14
            self.headerHeight = headerHeight
            tileWidth = 280
            thumbnailHeight = 180
            tileHeight = headerHeight + innerPadding + thumbnailHeight + innerPadding
        case .large:
            outerPadding = 28
            innerPadding = 12
            tileSpacing = 1
            rowSpacing = 12
            iconSize = 28
            let headerHeight = iconSize + 16
            self.headerHeight = headerHeight
            tileWidth = 340
            thumbnailHeight = 220
            tileHeight = headerHeight + innerPadding + thumbnailHeight + innerPadding
        }
    }

    private static func scaled(_ value: CGFloat, by scale: CGFloat) -> CGFloat {
        (value * scale).rounded()
    }
}

struct HUDIconStripMetrics {
    let outerPadding: CGFloat = 18
    let tileSpacing: CGFloat = 12
    let tileWidth: CGFloat = 114
    let tileHeight: CGFloat = 124
    let iconSize: CGFloat = 82
    let selectionPlateSize: CGFloat = 98
    let labelHeight: CGFloat = 24
    let labelSpacing: CGFloat = 6

    init(appearance _: AppearanceConfig) {}

    func maximumPanelSize(for visibleFrame: CGRect) -> CGSize {
        CGSize(
            width: max(tileWidth + outerPadding * 2, visibleFrame.width * 0.72),
            height: min(visibleFrame.height * 0.34, tileHeight + outerPadding * 2)
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
