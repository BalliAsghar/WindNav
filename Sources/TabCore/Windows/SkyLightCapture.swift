import CoreGraphics
import Foundation

typealias CGSConnectionID = UInt32

struct CGSWindowCaptureOptions: OptionSet {
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

enum SkyLightCapture {
    private static let connection: CGSConnectionID = CGSMainConnectionID()

    static func captureWindow(_ windowID: CGWindowID) -> CGImage? {
        var windowID = windowID
        let captured = CGSHWCaptureWindowList(
            connection,
            &windowID,
            1,
            [.ignoreGlobalClipShape, .bestResolution, .fullSize]
        ).takeRetainedValue() as? [CGImage]
        return captured?.first
    }
}
