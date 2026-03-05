import CoreGraphics
import Foundation

enum ScreenRecordingPermission {
    static func isGranted() -> Bool {
        CGPreflightScreenCaptureAccess()
    }

    static func requestAccess() -> Bool {
        CGRequestScreenCaptureAccess()
    }
}
