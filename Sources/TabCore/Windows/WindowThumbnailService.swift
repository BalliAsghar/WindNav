import AppKit
import CoreGraphics
import Foundation
@preconcurrency import ScreenCaptureKit

protocol WindowThumbnailProviding: AnyObject {
    func canCaptureThumbnails() -> Bool
    func cachedThumbnails(for windowIDs: [UInt32]) -> [UInt32: CGImage]
    func requestThumbnails(
        for snapshots: [WindowSnapshot],
        thumbnailWidth: Int,
        onUpdate: @escaping @MainActor (_ windowID: UInt32, _ image: CGImage) -> Void
    )
    func clear()
}

struct WindowThumbnailServiceDependencies: @unchecked Sendable {
    var now: () -> Date
    var backingScaleFactor: () -> CGFloat
    var isScreenRecordingGranted: () -> Bool
    var fetchShareableWindows: () -> [UInt32: SCWindow]
    var captureWithScreenCaptureKit: (_ windowID: UInt32, _ scWindow: SCWindow?, _ targetSize: CGSize) -> CGImage?
    var captureWithSkyLight: (_ windowID: UInt32) -> CGImage?

    static let live = WindowThumbnailServiceDependencies(
        now: Date.init,
        backingScaleFactor: { NSScreen.main?.backingScaleFactor ?? 2.0 },
        isScreenRecordingGranted: { ScreenRecordingPermission.isGranted() },
        fetchShareableWindows: {
            let semaphore = DispatchSemaphore(value: 0)
            nonisolated(unsafe) var windowsByID: [UInt32: SCWindow] = [:]

            SCShareableContent.getExcludingDesktopWindows(true, onScreenWindowsOnly: false) {
                content, error in
                defer { semaphore.signal() }
                guard let content, error == nil else { return }
                for window in content.windows {
                    windowsByID[window.windowID] = window
                }
            }

            _ = semaphore.wait(timeout: .now() + 1.0)
            return windowsByID
        },
        captureWithScreenCaptureKit: { _, scWindow, targetSize in
            guard let scWindow else { return nil }

            let config = SCStreamConfiguration()
            config.width = max(1, Int(targetSize.width.rounded()))
            config.height = max(1, Int(targetSize.height.rounded()))
            config.showsCursor = false

            let filter = SCContentFilter(desktopIndependentWindow: scWindow)
            let semaphore = DispatchSemaphore(value: 0)
            nonisolated(unsafe) var result: CGImage?

            SCScreenshotManager.captureImage(contentFilter: filter, configuration: config) { image, error in
                defer { semaphore.signal() }
                guard error == nil else { return }
                result = image
            }

            let timedOut = semaphore.wait(timeout: .now() + 1.0) == .timedOut
            return timedOut ? nil : result
        },
        captureWithSkyLight: { windowID in
            SkyLightCapture.captureWindow(CGWindowID(windowID))
        }
    )
}

final class WindowThumbnailService: WindowThumbnailProviding, @unchecked Sendable {
    private struct CacheEntry {
        var image: CGImage
        var updatedAt: Date
        var lastAccessedAt: Date
    }

    private let maxEntries: Int
    private let ttl: TimeInterval
    private let scWindowRefreshInterval: TimeInterval
    private let dependencies: WindowThumbnailServiceDependencies

    private let lock = NSLock()
    private let captureQueue: OperationQueue
    private let shareableRefreshQueue = DispatchQueue(label: "windnav.thumbnail.shareable-refresh")

    private var cache: [UInt32: CacheEntry] = [:]
    private var inflightWindowIDs = Set<UInt32>()
    private var shareableWindowsByID: [UInt32: SCWindow] = [:]
    private var lastShareableRefreshAt: Date = .distantPast

    init(
        maxEntries: Int = 120,
        ttl: TimeInterval = 30,
        scWindowRefreshInterval: TimeInterval = 2,
        maxConcurrentOperationCount: Int = WindowThumbnailService.defaultConcurrentOperationCount,
        dependencies: WindowThumbnailServiceDependencies = .live
    ) {
        self.maxEntries = max(1, maxEntries)
        self.ttl = max(0, ttl)
        self.scWindowRefreshInterval = max(0.1, scWindowRefreshInterval)
        self.dependencies = dependencies

        let queue = OperationQueue()
        queue.name = "windnav.window-thumbnails"
        queue.qualityOfService = .userInitiated
        queue.maxConcurrentOperationCount = max(1, maxConcurrentOperationCount)
        self.captureQueue = queue
    }

    func canCaptureThumbnails() -> Bool {
        dependencies.isScreenRecordingGranted()
    }

    func cachedThumbnails(for windowIDs: [UInt32]) -> [UInt32: CGImage] {
        let now = dependencies.now()
        return lock.withLock {
            var output: [UInt32: CGImage] = [:]
            for windowID in windowIDs {
                guard var entry = cache[windowID] else { continue }
                entry.lastAccessedAt = now
                cache[windowID] = entry
                output[windowID] = entry.image
            }
            return output
        }
    }

    func requestThumbnails(
        for snapshots: [WindowSnapshot],
        thumbnailWidth: Int,
        onUpdate: @escaping @MainActor (_ windowID: UInt32, _ image: CGImage) -> Void
    ) {
        guard canCaptureThumbnails() else { return }

        let sanitizedWidth = max(120, thumbnailWidth)
        let eligible = snapshots.filter(Self.isCaptureEligible)
        guard !eligible.isEmpty else { return }

        let now = dependencies.now()
        let toCapture = lock.withLock { () -> [WindowSnapshot] in
            var pending: [WindowSnapshot] = []
            for snapshot in eligible {
                if inflightWindowIDs.contains(snapshot.windowId) {
                    continue
                }
                let isStale = cache[snapshot.windowId].map {
                    now.timeIntervalSince($0.updatedAt) > ttl
                } ?? true
                if isStale {
                    inflightWindowIDs.insert(snapshot.windowId)
                    pending.append(snapshot)
                }
            }
            return pending
        }

        guard !toCapture.isEmpty else { return }

        captureQueue.addOperation { [weak self] in
            guard let self else { return }
            self.refreshShareableWindowsIfNeeded(requiredWindowIDs: Set(toCapture.map(\.windowId)))

            for snapshot in toCapture {
                self.captureQueue.addOperation { [weak self] in
                    self?.captureSingle(snapshot: snapshot, thumbnailWidth: sanitizedWidth, onUpdate: onUpdate)
                }
            }
        }
    }

    func clear() {
        lock.withLock {
            cache.removeAll()
            inflightWindowIDs.removeAll()
            shareableWindowsByID.removeAll()
            lastShareableRefreshAt = .distantPast
        }
        captureQueue.cancelAllOperations()
    }

    private func captureSingle(
        snapshot: WindowSnapshot,
        thumbnailWidth: Int,
        onUpdate: @escaping @MainActor (_ windowID: UInt32, _ image: CGImage) -> Void
    ) {
        defer {
            lock.withLock {
                inflightWindowIDs.remove(snapshot.windowId)
            }
        }

        let backingScale = dependencies.backingScaleFactor()
        let targetSize = Self.targetPixelSize(for: snapshot, thumbnailWidth: thumbnailWidth, backingScale: backingScale)

        var shareableWindow = lock.withLock { shareableWindowsByID[snapshot.windowId] }
        if shareableWindow == nil {
            refreshShareableWindowsIfNeeded(requiredWindowIDs: [snapshot.windowId])
            shareableWindow = lock.withLock { shareableWindowsByID[snapshot.windowId] }
        }

        var captured = dependencies.captureWithScreenCaptureKit(snapshot.windowId, shareableWindow, targetSize)
        if captured == nil {
            captured = dependencies.captureWithSkyLight(snapshot.windowId)
        }

        guard let captured else { return }
        let downscaled = Self.downscaleIfNeeded(captured, targetSize: targetSize)
        let now = dependencies.now()

        lock.withLock {
            cache[snapshot.windowId] = CacheEntry(image: downscaled, updatedAt: now, lastAccessedAt: now)
            enforceCacheLimitLocked()
        }

        Task { @MainActor in
            onUpdate(snapshot.windowId, downscaled)
        }
    }

    private func refreshShareableWindowsIfNeeded(requiredWindowIDs: Set<UInt32>) {
        guard !requiredWindowIDs.isEmpty else { return }

        shareableRefreshQueue.sync {
            let shouldRefresh = lock.withLock { () -> Bool in
                let now = dependencies.now()
                let missingRequiredWindow = requiredWindowIDs.contains { shareableWindowsByID[$0] == nil }
                if missingRequiredWindow {
                    return true
                }
                return now.timeIntervalSince(lastShareableRefreshAt) >= scWindowRefreshInterval
            }

            guard shouldRefresh else { return }
            let refreshed = dependencies.fetchShareableWindows()
            let now = dependencies.now()

            lock.withLock {
                shareableWindowsByID = refreshed
                lastShareableRefreshAt = now
            }
        }
    }

    private func enforceCacheLimitLocked() {
        guard cache.count > maxEntries else { return }
        let overflow = cache.count - maxEntries
        let windowIDsToRemove = cache
            .sorted { lhs, rhs in
                lhs.value.lastAccessedAt < rhs.value.lastAccessedAt
            }
            .prefix(overflow)
            .map(\.key)

        for windowID in windowIDsToRemove {
            cache.removeValue(forKey: windowID)
        }
    }

    private static func isCaptureEligible(_ snapshot: WindowSnapshot) -> Bool {
        !snapshot.isWindowlessApp
            && snapshot.frame.width > 1
            && snapshot.frame.height > 1
    }

    private static func targetPixelSize(
        for snapshot: WindowSnapshot,
        thumbnailWidth: Int,
        backingScale: CGFloat
    ) -> CGSize {
        let pixelWidth = max(1, Int(round(CGFloat(thumbnailWidth) * backingScale)))
        let ratio = max(0.2, min(4.0, snapshot.frame.height / max(snapshot.frame.width, 1)))
        let pixelHeight = max(1, Int(round(CGFloat(pixelWidth) * ratio)))
        return CGSize(width: pixelWidth, height: pixelHeight)
    }

    private static func downscaleIfNeeded(_ image: CGImage, targetSize: CGSize) -> CGImage {
        let widthScale = targetSize.width / CGFloat(max(image.width, 1))
        let heightScale = targetSize.height / CGFloat(max(image.height, 1))
        let scale = min(1, min(widthScale, heightScale))
        guard scale < 1 else { return image }

        let outputWidth = max(1, Int(round(CGFloat(image.width) * scale)))
        let outputHeight = max(1, Int(round(CGFloat(image.height) * scale)))

        guard let context = CGContext(
            data: nil,
            width: outputWidth,
            height: outputHeight,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else {
            return image
        }

        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: outputWidth, height: outputHeight))
        return context.makeImage() ?? image
    }

    private static var defaultConcurrentOperationCount: Int {
        let processors = ProcessInfo.processInfo.activeProcessorCount
        return min(8, max(2, processors))
    }
}

private extension NSLock {
    @discardableResult
    func withLock<T>(_ body: () -> T) -> T {
        lock()
        defer { unlock() }
        return body()
    }
}
