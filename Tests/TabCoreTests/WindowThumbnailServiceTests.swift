@testable import TabCore
import CoreGraphics
import Foundation
import ScreenCaptureKit
import XCTest

final class WindowThumbnailServiceTests: XCTestCase {
    func testInFlightDedupeForSameWindowID() {
        var screenCaptureCalls = 0
        let deps = makeDependencies(
            isScreenRecordingGranted: { true },
            captureWithScreenCaptureKit: { windowID, _, _ in
                screenCaptureCalls += 1
                usleep(60_000)
                return Self.makeImage(seed: Int(windowID))
            }
        )

        let service = WindowThumbnailService(
            maxEntries: 120,
            ttl: 30,
            maxConcurrentOperationCount: 2,
            dependencies: deps
        )

        let snapshot = makeSnapshot(windowID: 42)
        let updated = expectation(description: "thumbnail updated")
        updated.expectedFulfillmentCount = 1

        service.requestThumbnails(for: [snapshot], thumbnailWidth: 140) { _, _ in
            updated.fulfill()
        }
        service.requestThumbnails(for: [snapshot], thumbnailWidth: 140) { _, _ in
            updated.fulfill()
        }

        wait(for: [updated], timeout: 1.0)
        XCTAssertEqual(screenCaptureCalls, 1)
    }

    func testLRUEvictsOldestEntriesBeyondLimit() {
        let deps = makeDependencies(
            isScreenRecordingGranted: { true },
            captureWithScreenCaptureKit: { windowID, _, _ in
                Self.makeImage(seed: Int(windowID))
            }
        )

        let service = WindowThumbnailService(
            maxEntries: 2,
            ttl: 30,
            maxConcurrentOperationCount: 1,
            dependencies: deps
        )

        for windowID in [1, 2, 3] {
            let updated = expectation(description: "update-\(windowID)")
            service.requestThumbnails(for: [makeSnapshot(windowID: UInt32(windowID))], thumbnailWidth: 140) { _, _ in
                updated.fulfill()
            }
            wait(for: [updated], timeout: 1.0)
        }

        let cached = service.cachedThumbnails(for: [1, 2, 3])
        XCTAssertEqual(cached.count, 2)
        XCTAssertNil(cached[1])
        XCTAssertNotNil(cached[2])
        XCTAssertNotNil(cached[3])
    }

    func testStaleEntryRefreshesAfterTTL() {
        var now = Date()
        var screenCaptureCalls = 0
        let deps = makeDependencies(
            now: { now },
            isScreenRecordingGranted: { true },
            captureWithScreenCaptureKit: { windowID, _, _ in
                screenCaptureCalls += 1
                return Self.makeImage(seed: Int(windowID) + screenCaptureCalls)
            }
        )

        let service = WindowThumbnailService(
            maxEntries: 10,
            ttl: 0.05,
            maxConcurrentOperationCount: 1,
            dependencies: deps
        )

        let snapshot = makeSnapshot(windowID: 99)

        let initial = expectation(description: "initial-update")
        service.requestThumbnails(for: [snapshot], thumbnailWidth: 140) { _, _ in
            initial.fulfill()
        }
        wait(for: [initial], timeout: 1.0)
        XCTAssertEqual(screenCaptureCalls, 1)

        let noRefresh = expectation(description: "no-refresh")
        noRefresh.isInverted = true
        service.requestThumbnails(for: [snapshot], thumbnailWidth: 140) { _, _ in
            noRefresh.fulfill()
        }
        wait(for: [noRefresh], timeout: 0.2)
        XCTAssertEqual(screenCaptureCalls, 1)

        now = now.addingTimeInterval(0.2)
        let refreshed = expectation(description: "refreshed-update")
        service.requestThumbnails(for: [snapshot], thumbnailWidth: 140) { _, _ in
            refreshed.fulfill()
        }
        wait(for: [refreshed], timeout: 1.0)

        XCTAssertEqual(screenCaptureCalls, 2)
    }

    func testSkyLightFallbackUsedOnlyWhenScreenCaptureFails() {
        var screenCaptureCalls = 0
        var fallbackCalls = 0

        let deps = makeDependencies(
            isScreenRecordingGranted: { true },
            captureWithScreenCaptureKit: { windowID, _, _ in
                screenCaptureCalls += 1
                if windowID == 1 {
                    return nil
                }
                return Self.makeImage(seed: Int(windowID))
            },
            captureWithSkyLight: { windowID in
                fallbackCalls += 1
                return Self.makeImage(seed: Int(windowID) + 1000)
            }
        )

        let service = WindowThumbnailService(
            maxEntries: 10,
            ttl: 30,
            maxConcurrentOperationCount: 2,
            dependencies: deps
        )

        let updated = expectation(description: "both-updated")
        updated.expectedFulfillmentCount = 2

        let snapshots = [makeSnapshot(windowID: 1), makeSnapshot(windowID: 2)]
        service.requestThumbnails(for: snapshots, thumbnailWidth: 140) { _, _ in
            updated.fulfill()
        }

        wait(for: [updated], timeout: 1.0)
        XCTAssertEqual(screenCaptureCalls, 2)
        XCTAssertEqual(fallbackCalls, 1)
    }

    private func makeDependencies(
        now: @escaping () -> Date = Date.init,
        isScreenRecordingGranted: @escaping () -> Bool,
        captureWithScreenCaptureKit: @escaping (_ windowID: UInt32, _ scWindow: SCWindow?, _ targetSize: CGSize) -> CGImage?,
        captureWithSkyLight: @escaping (_ windowID: UInt32) -> CGImage? = { _ in nil }
    ) -> WindowThumbnailServiceDependencies {
        WindowThumbnailServiceDependencies(
            now: now,
            backingScaleFactor: { 2.0 },
            isScreenRecordingGranted: isScreenRecordingGranted,
            fetchShareableWindows: { [:] },
            captureWithScreenCaptureKit: captureWithScreenCaptureKit,
            captureWithSkyLight: captureWithSkyLight
        )
    }

    private func makeSnapshot(windowID: UInt32) -> WindowSnapshot {
        WindowSnapshot(
            windowId: windowID,
            pid: 123,
            bundleId: "com.example.app",
            appName: "Example",
            frame: CGRect(x: 0, y: 0, width: 1280, height: 800),
            isMinimized: false,
            appIsHidden: false,
            isFullscreen: false,
            title: "Window \(windowID)",
            isWindowlessApp: false
        )
    }

    private static func makeImage(seed: Int) -> CGImage {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
        let context = CGContext(
            data: nil,
            width: 12,
            height: 8,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        )!

        let color = CGFloat((seed % 255)) / 255
        context.setFillColor(CGColor(red: color, green: 0.4, blue: 0.8, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 12, height: 8))
        return context.makeImage()!
    }
}
