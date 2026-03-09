import AppKit
import CoreGraphics
import CoreMedia
import CoreVideo
import Foundation
import QuartzCore
import ScreenCaptureKit

final class ThumbnailSurface: @unchecked Sendable {
    enum Storage {
        case pixelBuffer(CVPixelBuffer)
        case cgImage(CGImage)
    }

    let storage: Storage
    let pixelSize: CGSize
    let cost: Int

    init(pixelBuffer: CVPixelBuffer) {
        storage = .pixelBuffer(pixelBuffer)
        pixelSize = CGSize(
            width: CVPixelBufferGetWidth(pixelBuffer),
            height: CVPixelBufferGetHeight(pixelBuffer)
        )
        cost = Int(pixelSize.width * pixelSize.height * 4)
    }

    init(cgImage: CGImage) {
        storage = .cgImage(cgImage)
        pixelSize = CGSize(width: cgImage.width, height: cgImage.height)
        cost = Int(pixelSize.width * pixelSize.height * 4)
    }

    @MainActor
    func apply(to layer: CALayer) {
        switch storage {
            case .pixelBuffer(let pixelBuffer):
                layer.contents = CVPixelBufferGetIOSurface(pixelBuffer)?.takeUnretainedValue()
            case .cgImage(let image):
                layer.contents = image
        }
        layer.contentsGravity = .resize
    }
}

struct ThumbnailUpdate: Sendable {
    let windowId: UInt32
    let revision: UInt64
    let state: ThumbnailState
    let surface: ThumbnailSurface?
}

private struct ThumbnailCacheKey: Hashable, Sendable {
    let windowId: UInt32
    let revisionBucket: UInt64
    let scaleBucket: Int
    let mode: CaptureMode
}

struct ThumbnailLookupResult: Sendable {
    let state: ThumbnailState
    let surface: ThumbnailSurface?
}

struct ThumbnailSizing {
    struct ScreenCandidate: Equatable {
        let frame: CGRect
        let scaleFactor: CGFloat
    }

    static func capturePixelSize(
        logicalWindowSize: CGSize,
        targetSize: CGSize,
        scaleFactor: CGFloat
    ) -> CGSize {
        let safeScaleFactor = scaleFactor.isFinite && scaleFactor > 0 ? scaleFactor : 1
        let sourcePixels = CGSize(
            width: logicalWindowSize.width * safeScaleFactor,
            height: logicalWindowSize.height * safeScaleFactor
        )
        let boundingPixels = CGSize(
            width: targetSize.width * safeScaleFactor,
            height: targetSize.height * safeScaleFactor
        )
        return aspectFitSize(sourceSize: sourcePixels, boundingSize: boundingPixels)
    }

    static func aspectFitSize(
        sourceSize: CGSize,
        boundingSize: CGSize,
        allowUpscaling: Bool = false
    ) -> CGSize {
        guard sourceSize.width > 0,
              sourceSize.height > 0,
              boundingSize.width > 0,
              boundingSize.height > 0 else {
            return CGSize(width: 1, height: 1)
        }

        var scale = min(
            boundingSize.width / sourceSize.width,
            boundingSize.height / sourceSize.height
        )
        if !allowUpscaling {
            scale = min(scale, 1)
        }
        if !scale.isFinite || scale <= 0 {
            scale = 1
        }

        return CGSize(
            width: max(1, (sourceSize.width * scale).rounded()),
            height: max(1, (sourceSize.height * scale).rounded())
        )
    }

    static func aspectFitRect(
        sourceSize: CGSize,
        boundingSize: CGSize,
        allowUpscaling: Bool = false
    ) -> CGRect {
        let fittedSize = aspectFitSize(
            sourceSize: sourceSize,
            boundingSize: boundingSize,
            allowUpscaling: allowUpscaling
        )
        return CGRect(
            x: ((boundingSize.width - fittedSize.width) / 2).rounded(),
            y: ((boundingSize.height - fittedSize.height) / 2).rounded(),
            width: fittedSize.width,
            height: fittedSize.height
        )
    }

    static func bestBackingScaleFactor(
        for windowFrame: CGRect,
        screens: [ScreenCandidate],
        fallbackScaleFactor: CGFloat
    ) -> CGFloat {
        let bestCandidate = screens.max { lhs, rhs in
            intersectionArea(windowFrame, lhs.frame) < intersectionArea(windowFrame, rhs.frame)
        }

        if let bestCandidate,
           intersectionArea(windowFrame, bestCandidate.frame) > 0 {
            return bestCandidate.scaleFactor
        }

        return fallbackScaleFactor.isFinite && fallbackScaleFactor > 0 ? fallbackScaleFactor : 2
    }

    @MainActor
    static func bestBackingScaleFactor(for windowFrame: CGRect) -> CGFloat {
        let screens = NSScreen.screens.map {
            ScreenCandidate(frame: $0.frame, scaleFactor: $0.backingScaleFactor)
        }
        return bestBackingScaleFactor(
            for: windowFrame,
            screens: screens,
            fallbackScaleFactor: NSScreen.main?.backingScaleFactor ?? screens.first?.scaleFactor ?? 2
        )
    }

    private static func intersectionArea(_ lhs: CGRect, _ rhs: CGRect) -> CGFloat {
        let intersection = lhs.intersection(rhs)
        guard !intersection.isNull, !intersection.isEmpty else { return 0 }
        return intersection.width * intersection.height
    }
}

actor ThumbnailCache {
    private struct Entry {
        let key: ThumbnailCacheKey
        let state: ThumbnailState
        let surface: ThumbnailSurface
        var lastAccessTick: UInt64
    }

    private let softCapBytes = 48 * 1024 * 1024
    private let hardCapBytes = 64 * 1024 * 1024

    private var entries: [ThumbnailCacheKey: Entry] = [:]
    private var totalCost = 0
    private var accessTick: UInt64 = 0

    func lookup(
        windowId: UInt32,
        revision: UInt64,
        scaleBucket: Int,
        preferredMode: CaptureMode
    ) -> ThumbnailLookupResult {
        accessTick &+= 1

        let preferredKey = ThumbnailCacheKey(
            windowId: windowId,
            revisionBucket: revision,
            scaleBucket: scaleBucket,
            mode: preferredMode
        )
        if var exact = entries[preferredKey] {
            exact.lastAccessTick = accessTick
            entries[preferredKey] = exact
            return ThumbnailLookupResult(state: exact.state, surface: exact.surface)
        }

        if preferredMode == .live {
            let stillKey = ThumbnailCacheKey(
                windowId: windowId,
                revisionBucket: revision,
                scaleBucket: scaleBucket,
                mode: .still
            )
            if var exactStill = entries[stillKey] {
                exactStill.lastAccessTick = accessTick
                entries[stillKey] = exactStill
                return ThumbnailLookupResult(state: exactStill.state, surface: exactStill.surface)
            }
        }

        let staleEntry = entries.values
            .filter { $0.key.windowId == windowId && $0.key.scaleBucket == scaleBucket }
            .sorted { lhs, rhs in
                if lhs.key.revisionBucket != rhs.key.revisionBucket {
                    return lhs.key.revisionBucket > rhs.key.revisionBucket
                }
                return lhs.lastAccessTick > rhs.lastAccessTick
            }
            .first

        if let staleEntry {
            return ThumbnailLookupResult(state: .stale, surface: staleEntry.surface)
        }

        return ThumbnailLookupResult(state: .placeholder, surface: nil)
    }

    func store(
        surface: ThumbnailSurface,
        windowId: UInt32,
        revision: UInt64,
        scaleBucket: Int,
        mode: CaptureMode,
        state: ThumbnailState
    ) {
        accessTick &+= 1
        let key = ThumbnailCacheKey(
            windowId: windowId,
            revisionBucket: revision,
            scaleBucket: scaleBucket,
            mode: mode
        )

        if let existing = entries[key] {
            totalCost -= existing.surface.cost
        }

        entries[key] = Entry(
            key: key,
            state: state,
            surface: surface,
            lastAccessTick: accessTick
        )
        totalCost += surface.cost
        trimToSoftLimit(visibleWindowIDs: [], selectedWindowID: nil)
    }

    func trim(visibleWindowIDs: Set<UInt32>, selectedWindowID: UInt32?) {
        trimToSoftLimit(visibleWindowIDs: visibleWindowIDs, selectedWindowID: selectedWindowID)
    }

    func reset(keepingWindowID: UInt32?) {
        if let keepingWindowID {
            entries = entries.filter { $0.key.windowId == keepingWindowID && $0.key.mode == .live }
        } else {
            entries.removeAll()
        }
        totalCost = entries.values.reduce(0) { $0 + $1.surface.cost }
    }

    private func trimToSoftLimit(visibleWindowIDs: Set<UInt32>, selectedWindowID: UInt32?) {
        let targetLimit = totalCost > hardCapBytes ? softCapBytes : softCapBytes

        while totalCost > targetLimit, let victimKey = nextVictimKey(
            visibleWindowIDs: visibleWindowIDs,
            selectedWindowID: selectedWindowID
        ) {
            if let victim = entries.removeValue(forKey: victimKey) {
                totalCost -= victim.surface.cost
            }
        }
    }

    private func nextVictimKey(
        visibleWindowIDs: Set<UInt32>,
        selectedWindowID: UInt32?
    ) -> ThumbnailCacheKey? {
        entries.values
            .filter { entry in
                !(entry.key.windowId == selectedWindowID && entry.key.mode == .live)
            }
            .min { lhs, rhs in
                victimRank(lhs, visibleWindowIDs: visibleWindowIDs, selectedWindowID: selectedWindowID)
                    < victimRank(rhs, visibleWindowIDs: visibleWindowIDs, selectedWindowID: selectedWindowID)
            }?
            .key
    }

    private func victimRank(
        _ entry: Entry,
        visibleWindowIDs: Set<UInt32>,
        selectedWindowID: UInt32?
    ) -> (Int, UInt64) {
        if entry.key.windowId == selectedWindowID {
            return (3, entry.lastAccessTick)
        }
        if !visibleWindowIDs.contains(entry.key.windowId) {
            return (0, entry.lastAccessTick)
        }
        if entry.key.mode == .still {
            return (1, entry.lastAccessTick)
        }
        return (2, entry.lastAccessTick)
    }
}

protocol ThumbnailProvider: Sendable {
    func captureStill(snapshot: WindowSnapshot, targetSize: CGSize) async -> ThumbnailSurface?
}

actor ScreenCaptureKitThumbnailProvider: ThumbnailProvider {
    private var scWindowByID: [UInt32: SCWindow] = [:]
    private var lastRefreshAt: Date?

    func captureStill(snapshot: WindowSnapshot, targetSize: CGSize) async -> ThumbnailSurface? {
        guard let scWindow = await shareableWindow(windowId: snapshot.windowId) else {
            return nil
        }

        let captureSize = await capturePixelSize(for: snapshot, targetSize: targetSize)
        let filter = SCContentFilter(desktopIndependentWindow: scWindow)
        let config = SCStreamConfiguration()
        config.width = max(1, Int(captureSize.width.rounded()))
        config.height = max(1, Int(captureSize.height.rounded()))
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.showsCursor = false

        let result = await withCheckedContinuation { (continuation: CheckedContinuation<ThumbnailSurface?, Never>) in
            SCScreenshotManager.captureSampleBuffer(
                contentFilter: filter,
                configuration: config
            ) { sampleBuffer, error in
                guard error == nil, let sampleBuffer, let pixelBuffer = sampleBuffer.tabPixelBuffer() else {
                    continuation.resume(returning: nil)
                    return
                }
                continuation.resume(returning: ThumbnailSurface(pixelBuffer: pixelBuffer))
            }
        }
        return result
    }

    func startLiveCapture(
        snapshot: WindowSnapshot,
        targetSize: CGSize,
        onFrame: @escaping @Sendable (ThumbnailSurface) -> Void,
        onStop: @escaping @Sendable (Error?) -> Void
    ) async -> ScreenCaptureKitLiveStream? {
        guard let scWindow = await shareableWindow(windowId: snapshot.windowId) else {
            return nil
        }

        let captureSize = await capturePixelSize(for: snapshot, targetSize: targetSize)
        let stream = ScreenCaptureKitLiveStream(
            window: scWindow,
            captureSize: captureSize,
            onFrame: onFrame,
            onStop: onStop
        )
        return await stream.start() ? stream : nil
    }

    func invalidateShareableContent() {
        scWindowByID.removeAll()
        lastRefreshAt = nil
    }

    private func shareableWindow(windowId: UInt32) async -> SCWindow? {
        if let cached = scWindowByID[windowId] {
            return cached
        }

        _ = await refreshShareableContent(force: false)
        if let cached = scWindowByID[windowId] {
            return cached
        }

        _ = await refreshShareableContent(force: true)
        return scWindowByID[windowId]
    }

    private func refreshShareableContent(force: Bool) async -> Bool {
        if !force, let lastRefreshAt, Date().timeIntervalSince(lastRefreshAt) < 1 {
            return true
        }

        let result = await withCheckedContinuation { (continuation: CheckedContinuation<ShareableContentBox, Never>) in
            SCShareableContent.getExcludingDesktopWindows(
                true,
                onScreenWindowsOnly: false
            ) { shareableContent, error in
                if let shareableContent, error == nil {
                    continuation.resume(
                        returning: ShareableContentBox(
                            windowsByID: Dictionary(
                                uniqueKeysWithValues: shareableContent.windows.map { (UInt32($0.windowID), $0) }
                            ),
                            success: true
                        )
                    )
                } else {
                    continuation.resume(returning: ShareableContentBox(windowsByID: [:], success: false))
                }
            }
        }

        guard result.success else {
            Logger.error(.capture, "Failed to refresh ScreenCaptureKit shareable content")
            return false
        }

        scWindowByID = result.windowsByID
        lastRefreshAt = Date()
        return true
    }

    private func capturePixelSize(for snapshot: WindowSnapshot, targetSize: CGSize) async -> CGSize {
        let scaleFactor = await MainActor.run {
            ThumbnailSizing.bestBackingScaleFactor(for: snapshot.frame)
        }
        return ThumbnailSizing.capturePixelSize(
            logicalWindowSize: snapshot.frame.size,
            targetSize: targetSize,
            scaleFactor: scaleFactor
        )
    }
}

private final class ShareableContentBox: @unchecked Sendable {
    let windowsByID: [UInt32: SCWindow]
    let success: Bool

    init(windowsByID: [UInt32: SCWindow], success: Bool) {
        self.windowsByID = windowsByID
        self.success = success
    }
}

final class ScreenCaptureKitLiveStream: NSObject, @unchecked Sendable, SCStreamOutput, SCStreamDelegate {
    private let window: SCWindow
    private let captureSize: CGSize
    private let onFrame: @Sendable (ThumbnailSurface) -> Void
    private let onStop: @Sendable (Error?) -> Void
    private let outputQueue = DispatchQueue(label: "windnav.capture.live", qos: .userInitiated)

    private var stream: SCStream?

    init(
        window: SCWindow,
        captureSize: CGSize,
        onFrame: @escaping @Sendable (ThumbnailSurface) -> Void,
        onStop: @escaping @Sendable (Error?) -> Void
    ) {
        self.window = window
        self.captureSize = captureSize
        self.onFrame = onFrame
        self.onStop = onStop
    }

    func start() async -> Bool {
        let filter = SCContentFilter(desktopIndependentWindow: window)
        let config = SCStreamConfiguration()
        config.width = max(1, Int(captureSize.width.rounded()))
        config.height = max(1, Int(captureSize.height.rounded()))
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.showsCursor = false
        config.queueDepth = 3
        config.minimumFrameInterval = CMTime(value: 1, timescale: 30)

        let stream = SCStream(filter: filter, configuration: config, delegate: self)
        do {
            try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: outputQueue)
        } catch {
            onStop(error)
            return false
        }

        self.stream = stream
        return await withCheckedContinuation { continuation in
            stream.startCapture { error in
                if let error {
                    self.onStop(error)
                    continuation.resume(returning: false)
                } else {
                    continuation.resume(returning: true)
                }
            }
        }
    }

    func stop() async {
        guard let stream else { return }
        await withCheckedContinuation { continuation in
            stream.stopCapture { _ in
                continuation.resume(returning: ())
            }
        }
        self.stream = nil
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, let pixelBuffer = sampleBuffer.tabPixelBuffer() else {
            return
        }
        onFrame(ThumbnailSurface(pixelBuffer: pixelBuffer))
    }

    func stream(_ stream: SCStream, didStopWithError error: any Error) {
        onStop(error)
    }
}

final class PrivateWindowCaptureProvider: @unchecked Sendable {
    private let isEnabled: Bool

    init(isEnabled: Bool = ProcessInfo.processInfo.environment["WINDNAV_ENABLE_PRIVATE_CAPTURE"] == "1") {
        self.isEnabled = isEnabled
    }

    func captureStill(snapshot: WindowSnapshot, targetSize: CGSize) async -> ThumbnailSurface? {
        guard isEnabled else { return nil }
        var windowID = CGWindowID(snapshot.windowId)
        let images = CGSHWCaptureWindowList(
            CGSMainConnectionID(),
            &windowID,
            1,
            [.ignoreGlobalClipShape, .bestResolution, .fullSize]
        ).takeRetainedValue() as? [CGImage]
        guard let cgImage = images?.first else { return nil }
        let outputSize = await capturePixelSize(for: snapshot, targetSize: targetSize)
        return scaledSurface(from: cgImage, outputSize: outputSize)
    }

    private func capturePixelSize(for snapshot: WindowSnapshot, targetSize: CGSize) async -> CGSize {
        let scaleFactor = await MainActor.run {
            ThumbnailSizing.bestBackingScaleFactor(for: snapshot.frame)
        }
        return ThumbnailSizing.capturePixelSize(
            logicalWindowSize: snapshot.frame.size,
            targetSize: targetSize,
            scaleFactor: scaleFactor
        )
    }
}

actor CaptureScheduler {
    private enum CapturePriority: Int, Sendable {
        case backgroundWarm = 0
        case visibleWarm = 1
        case liveSelected = 2
    }

    private struct RequestKey: Hashable, Sendable {
        let windowId: UInt32
        let revision: UInt64
        let scaleBucket: Int
        let mode: CaptureMode
    }

    private struct PendingStillRequest: Sendable {
        let key: RequestKey
        let snapshot: WindowSnapshot
        let priority: CapturePriority
        let targetSize: CGSize
    }

    private let cache: ThumbnailCache
    private let primaryProvider: ScreenCaptureKitThumbnailProvider
    private let privateProvider: PrivateWindowCaptureProvider
    private let onUpdate: @MainActor @Sendable (ThumbnailUpdate) -> Void

    private var latestSnapshotsByWindowID: [UInt32: WindowSnapshot] = [:]
    private var visibleWindowIDs = Set<UInt32>()
    private var selectedWindowID: UInt32?
    private var screenRecordingGranted = false
    private var activeScaleBucket = 0
    private var generation: UInt64 = 0

    private var pendingStill: [RequestKey: PendingStillRequest] = [:]
    private var activeStill: [RequestKey: Task<Void, Never>] = [:]
    private var liveStream: ScreenCaptureKitLiveStream?
    private var liveRequestKey: RequestKey?

    init(
        cache: ThumbnailCache,
        primaryProvider: ScreenCaptureKitThumbnailProvider,
        privateProvider: PrivateWindowCaptureProvider,
        onUpdate: @escaping @MainActor @Sendable (ThumbnailUpdate) -> Void
    ) {
        self.cache = cache
        self.primaryProvider = primaryProvider
        self.privateProvider = privateProvider
        self.onUpdate = onUpdate
    }

    func show(model: HUDModel, targetSize: CGSize, screenRecordingGranted: Bool) async {
        generation &+= 1
        self.screenRecordingGranted = screenRecordingGranted
        activeScaleBucket = scaleBucket(for: targetSize)
        visibleWindowIDs = Set(model.items.map(\.snapshot.windowId))
        selectedWindowID = model.selectedIndex.flatMap { index in
            model.items.indices.contains(index) ? model.items[index].snapshot.windowId : nil
        }
        latestSnapshotsByWindowID = Dictionary(
            uniqueKeysWithValues: model.items.map { ($0.snapshot.windowId, $0.snapshot) }
        )

        cancelInactiveRequests()

        guard screenRecordingGranted else {
            await stopLiveStream()
            for item in model.items where item.snapshot.canCaptureThumbnail {
                await onUpdate(
                    ThumbnailUpdate(
                        windowId: item.snapshot.windowId,
                        revision: item.snapshot.revision,
                        state: .unavailable,
                        surface: nil
                    )
                )
            }
            await cache.trim(visibleWindowIDs: visibleWindowIDs, selectedWindowID: nil)
            return
        }

        for (index, item) in model.items.enumerated() {
            let snapshot = item.snapshot
            guard snapshot.canCaptureThumbnail else {
                await onUpdate(
                    ThumbnailUpdate(
                        windowId: snapshot.windowId,
                        revision: snapshot.revision,
                        state: .unavailable,
                        surface: nil
                    )
                )
                continue
            }

            let preferredMode: CaptureMode = item.isSelected ? .live : .still
            let cached = await cache.lookup(
                windowId: snapshot.windowId,
                revision: snapshot.revision,
                scaleBucket: activeScaleBucket,
                preferredMode: preferredMode
            )
            await onUpdate(
                ThumbnailUpdate(
                    windowId: snapshot.windowId,
                    revision: snapshot.revision,
                    state: cached.state,
                    surface: cached.surface
                )
            )

            if item.isSelected {
                enqueueStill(snapshot: snapshot, priority: .liveSelected, targetSize: targetSize)
                await ensureLiveStream(for: snapshot, targetSize: targetSize)
            } else if cached.state == .placeholder || cached.state == .stale {
                let distance = abs(index - (model.selectedIndex ?? 0))
                let priority: CapturePriority = distance <= 3 ? .visibleWarm : .backgroundWarm
                enqueueStill(snapshot: snapshot, priority: priority, targetSize: targetSize)
            }
        }

        if selectedWindowID == nil {
            await stopLiveStream()
        }

        pumpStillQueue()
        await cache.trim(visibleWindowIDs: visibleWindowIDs, selectedWindowID: selectedWindowID)
    }

    func hide() async {
        generation &+= 1
        screenRecordingGranted = false
        visibleWindowIDs.removeAll()
        latestSnapshotsByWindowID.removeAll()
        selectedWindowID = nil
        cancelInactiveRequests()
        await stopLiveStream()
        await cache.trim(visibleWindowIDs: [], selectedWindowID: nil)
    }

    private func cancelInactiveRequests() {
        let allowedWindowIDs = visibleWindowIDs

        pendingStill = pendingStill.filter { allowedWindowIDs.contains($0.key.windowId) }

        let inactiveKeys = activeStill.keys.filter { !allowedWindowIDs.contains($0.windowId) }
        for key in inactiveKeys {
            activeStill[key]?.cancel()
            activeStill.removeValue(forKey: key)
        }
    }

    private func enqueueStill(snapshot: WindowSnapshot, priority: CapturePriority, targetSize: CGSize) {
        let key = RequestKey(
            windowId: snapshot.windowId,
            revision: snapshot.revision,
            scaleBucket: activeScaleBucket,
            mode: .still
        )

        guard activeStill[key] == nil else { return }
        if let existing = pendingStill[key], existing.priority.rawValue >= priority.rawValue {
            return
        }

        pendingStill[key] = PendingStillRequest(
            key: key,
            snapshot: snapshot,
            priority: priority,
            targetSize: targetSize
        )
    }

    private func pumpStillQueue() {
        while activeStill.count < 2,
              let next = pendingStill.values.sorted(by: prioritizeRequest(lhs:rhs:)).first {
            pendingStill.removeValue(forKey: next.key)

            let task = Task.detached(priority: .userInitiated) { [primaryProvider, privateProvider] in
                let primarySurface = await primaryProvider.captureStill(
                    snapshot: next.snapshot,
                    targetSize: next.targetSize
                )
                let privateSurface: ThumbnailSurface?
                if primarySurface == nil && next.snapshot.isMinimized {
                    privateSurface = await privateProvider.captureStill(
                        snapshot: next.snapshot,
                        targetSize: next.targetSize
                    )
                } else {
                    privateSurface = nil
                }

                let publicFallback: ThumbnailSurface?
                if primarySurface == nil && privateSurface == nil {
                    publicFallback = await fallbackWindowSurface(
                        snapshot: next.snapshot,
                        targetSize: next.targetSize
                    )
                } else {
                    publicFallback = nil
                }
                await self.finishStillRequest(next, surface: publicFallback ?? privateSurface ?? primarySurface)
            }
            activeStill[next.key] = task
        }
    }

    private func prioritizeRequest(lhs: PendingStillRequest, rhs: PendingStillRequest) -> Bool {
        if lhs.priority != rhs.priority {
            return lhs.priority.rawValue > rhs.priority.rawValue
        }
        return lhs.snapshot.revision > rhs.snapshot.revision
    }

    private func finishStillRequest(_ request: PendingStillRequest, surface: ThumbnailSurface?) async {
        activeStill.removeValue(forKey: request.key)
        defer { pumpStillQueue() }

        guard !Task.isCancelled else { return }
        guard let surface else {
            if let current = latestSnapshotsByWindowID[request.snapshot.windowId],
               current.revision == request.snapshot.revision {
                let cached = await cache.lookup(
                    windowId: current.windowId,
                    revision: current.revision,
                    scaleBucket: request.key.scaleBucket,
                    preferredMode: .still
                )
                if cached.state == .placeholder {
                    await onUpdate(
                        ThumbnailUpdate(
                            windowId: current.windowId,
                            revision: current.revision,
                            state: .unavailable,
                            surface: nil
                        )
                    )
                }
            }
            return
        }

        await cache.store(
            surface: surface,
            windowId: request.snapshot.windowId,
            revision: request.snapshot.revision,
            scaleBucket: request.key.scaleBucket,
            mode: .still,
            state: .freshStill
        )

        if let current = latestSnapshotsByWindowID[request.snapshot.windowId],
           current.revision == request.snapshot.revision {
            await onUpdate(
                ThumbnailUpdate(
                    windowId: request.snapshot.windowId,
                    revision: request.snapshot.revision,
                    state: .freshStill,
                    surface: surface
                )
            )
        }
    }

    private func ensureLiveStream(for snapshot: WindowSnapshot, targetSize: CGSize) async {
        let requestKey = RequestKey(
            windowId: snapshot.windowId,
            revision: snapshot.revision,
            scaleBucket: activeScaleBucket,
            mode: .live
        )

        if liveRequestKey == requestKey {
            return
        }

        await stopLiveStream()
        guard screenRecordingGranted else { return }

        liveStream = await primaryProvider.startLiveCapture(
            snapshot: snapshot,
            targetSize: targetSize,
            onFrame: { surface in
                Task {
                    await self.handleLiveFrame(
                        windowId: snapshot.windowId,
                        revision: snapshot.revision,
                        scaleBucket: self.activeScaleBucket,
                        surface: surface
                    )
                }
            },
            onStop: { error in
                if let error {
                    Logger.error(.capture, "Live stream stopped: \(error.localizedDescription)")
                }
            }
        )
        liveRequestKey = liveStream == nil ? nil : requestKey
    }

    private func stopLiveStream() async {
        liveRequestKey = nil
        guard let liveStream else { return }
        self.liveStream = nil
        await liveStream.stop()
    }

    private func handleLiveFrame(
        windowId: UInt32,
        revision: UInt64,
        scaleBucket: Int,
        surface: ThumbnailSurface
    ) async {
        guard let current = latestSnapshotsByWindowID[windowId], current.revision == revision else {
            return
        }

        await cache.store(
            surface: surface,
            windowId: windowId,
            revision: revision,
            scaleBucket: scaleBucket,
            mode: .live,
            state: .liveSurface
        )

        await onUpdate(
            ThumbnailUpdate(
                windowId: windowId,
                revision: revision,
                state: .liveSurface,
                surface: surface
            )
        )
    }
}

private func fallbackWindowSurface(snapshot: WindowSnapshot, targetSize: CGSize) async -> ThumbnailSurface? {
    guard snapshot.isOnCurrentSpace || snapshot.isOnCurrentDisplay else { return nil }
    guard !snapshot.isMinimized else { return nil }
    guard let cgImage = LegacyCGWindowListCreateImage(
        .null,
        .optionIncludingWindow,
        CGWindowID(snapshot.windowId),
        [.boundsIgnoreFraming]
    ) else {
        return nil
    }
    let scaleFactor = await MainActor.run {
        ThumbnailSizing.bestBackingScaleFactor(for: snapshot.frame)
    }
    let outputSize = ThumbnailSizing.capturePixelSize(
        logicalWindowSize: snapshot.frame.size,
        targetSize: targetSize,
        scaleFactor: scaleFactor
    )
    return scaledSurface(from: cgImage, outputSize: outputSize)
}

private func scaledSurface(from image: CGImage, outputSize: CGSize) -> ThumbnailSurface? {
    let width = max(1, Int(outputSize.width.rounded()))
    let height = max(1, Int(outputSize.height.rounded()))
    let colorSpace = image.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
    guard let context = CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
        return nil
    }

    context.interpolationQuality = .high
    let destinationRect = ThumbnailSizing.aspectFitRect(
        sourceSize: CGSize(width: image.width, height: image.height),
        boundingSize: CGSize(width: width, height: height)
    )
    context.clear(CGRect(x: 0, y: 0, width: width, height: height))
    context.draw(image, in: destinationRect)
    guard let scaled = context.makeImage() else { return nil }
    return ThumbnailSurface(cgImage: scaled)
}

private func scaleBucket(for targetSize: CGSize) -> Int {
    max(1, Int(max(targetSize.width, targetSize.height).rounded()))
}

private extension CMSampleBuffer {
    func tabPixelBuffer() -> CVPixelBuffer? {
        guard isValid else { return nil }
        return CMSampleBufferGetImageBuffer(self)
    }
}

private typealias CGSConnectionID = UInt32

private struct CGSWindowCaptureOptions: OptionSet {
    let rawValue: UInt32

    static let ignoreGlobalClipShape = CGSWindowCaptureOptions(rawValue: 1 << 11)
    static let bestResolution = CGSWindowCaptureOptions(rawValue: 1 << 8)
    static let fullSize = CGSWindowCaptureOptions(rawValue: 1 << 19)
}

@_silgen_name("CGSMainConnectionID")
private func CGSMainConnectionID() -> CGSConnectionID

@_silgen_name("CGSHWCaptureWindowList")
private func CGSHWCaptureWindowList(
    _ cid: CGSConnectionID,
    _ windowList: UnsafeMutablePointer<CGWindowID>,
    _ windowCount: UInt32,
    _ options: CGSWindowCaptureOptions
) -> Unmanaged<CFArray>

@_silgen_name("CGWindowListCreateImage")
private func LegacyCGWindowListCreateImage(
    _ screenBounds: CGRect,
    _ listOption: CGWindowListOption,
    _ windowID: CGWindowID,
    _ imageOption: CGWindowImageOption
) -> CGImage?
