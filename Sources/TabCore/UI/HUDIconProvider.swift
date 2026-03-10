import AppKit
import Foundation

@MainActor
protocol HUDIconSourcing {
    func image(for snapshot: WindowSnapshot) -> NSImage?
}

@MainActor
struct LiveHUDIconSource: HUDIconSourcing {
    func image(for snapshot: WindowSnapshot) -> NSImage? {
        if let app = NSRunningApplication(processIdentifier: snapshot.pid) {
            if let icon = app.icon {
                return icon
            }
            if let bundleURL = app.bundleURL {
                return NSWorkspace.shared.icon(forFile: bundleURL.path)
            }
        }

        if let bundleId = snapshot.bundleId,
           let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) {
            return NSWorkspace.shared.icon(forFile: url.path)
        }

        return nil
    }
}

@MainActor
final class HUDIconProvider {
    private struct CacheKey: Hashable {
        let appIdentity: String
        let pointSizeBucket: Int
        let scaleBucket: Int
    }

    private let source: any HUDIconSourcing
    private var cache: [CacheKey: CGImage] = [:]

    init(source: any HUDIconSourcing = LiveHUDIconSource()) {
        self.source = source
    }

    func icon(for snapshot: WindowSnapshot, pointSize: CGFloat, scale: CGFloat) -> CGImage? {
        let key = CacheKey(
            appIdentity: appIdentity(for: snapshot),
            pointSizeBucket: Int((pointSize * 10).rounded()),
            scaleBucket: Int((scale * 100).rounded())
        )

        if let cached = cache[key] {
            return cached
        }

        guard let image = source.image(for: snapshot),
              let rendered = rasterize(image: image, pointSize: pointSize, scale: scale) else {
            return nil
        }

        cache[key] = rendered
        return rendered
    }

    func cachedIconCount() -> Int {
        cache.count
    }

    private func appIdentity(for snapshot: WindowSnapshot) -> String {
        if let bundleId = snapshot.bundleId, !bundleId.isEmpty {
            return "bundle:\(bundleId)"
        }
        return "pid:\(snapshot.pid)"
    }

    private func rasterize(image: NSImage, pointSize: CGFloat, scale: CGFloat) -> CGImage? {
        let pixelSize = max(1, Int((pointSize * scale).rounded()))
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        guard let context = CGContext(
            data: nil,
            width: pixelSize,
            height: pixelSize,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }

        context.interpolationQuality = .high
        context.setShouldAntialias(true)
        context.setAllowsAntialiasing(true)
        let graphicsContext = NSGraphicsContext(cgContext: context, flipped: false)
        let targetRect = NSRect(x: 0, y: 0, width: pixelSize, height: pixelSize)

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = graphicsContext
        if let representation = bestRepresentation(for: image, pixelSize: pixelSize) {
            representation.draw(in: targetRect)
        } else {
            image.draw(
                in: targetRect,
                from: .zero,
                operation: .copy,
                fraction: 1
            )
        }
        graphicsContext.flushGraphics()
        NSGraphicsContext.restoreGraphicsState()

        return context.makeImage()
    }

    private func bestRepresentation(for image: NSImage, pixelSize: Int) -> NSImageRep? {
        let proposedRect = NSRect(x: 0, y: 0, width: pixelSize, height: pixelSize)
        if let representation = image.bestRepresentation(for: proposedRect, context: nil, hints: nil) {
            return representation
        }

        return image.representations.max { lhs, rhs in
            let lhsPixels = Int(lhs.pixelsWide) * Int(lhs.pixelsHigh)
            let rhsPixels = Int(rhs.pixelsWide) * Int(rhs.pixelsHigh)
            return lhsPixels < rhsPixels
        }
    }
}
