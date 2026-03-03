import ApplicationServices
import CoreGraphics
import Foundation

enum AXWindowFallbackKind: Equatable {
    case none
    case activationFallback
    case confirmedWindowless
}

enum AXWindowFallbackClassifier {
    static func fallbackKind(
        bundleId: String?,
        showEmptyApps: VisibilityConfig.ShowEmptyAppsPolicy,
        cgHasLikelyWindow: Bool
    ) -> AXWindowFallbackKind {
        if bundleId == "com.apple.finder" {
            return .none
        }
        if cgHasLikelyWindow {
            return .activationFallback
        }
        switch showEmptyApps {
            case .hide:
                return .none
            case .show, .showAtEnd:
                return .confirmedWindowless
        }
    }
}

enum AXWindowEligibility {
    static func acceptsSubrole(_ subrole: String, isFullscreen: Bool) -> Bool {
        subrole == (kAXStandardWindowSubrole as String) || isFullscreen
    }
}

enum CGWindowPresence {
    static func collectLikelyWindowOwnerPIDs() -> Set<pid_t> {
        guard
            let info = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]]
        else {
            return []
        }
        return likelyWindowOwnerPIDs(from: info)
    }

    static func likelyWindowOwnerPIDs(from windowInfo: [[String: Any]]) -> Set<pid_t> {
        var result = Set<pid_t>()
        for entry in windowInfo {
            guard let ownerPID = numberValue(entry[kCGWindowOwnerPID as String]) else { continue }
            guard numberValue(entry[kCGWindowLayer as String])?.intValue == 0 else { continue }

            if let alpha = numberValue(entry[kCGWindowAlpha as String]), alpha.doubleValue <= 0 {
                continue
            }

            guard let boundsRaw = entry[kCGWindowBounds as String] else { continue }
            guard let bounds = cgRectValue(boundsRaw) else { continue }
            if bounds.width <= 1 || bounds.height <= 1 { continue }

            result.insert(pid_t(ownerPID.intValue))
        }
        return result
    }

    private static func numberValue(_ value: Any?) -> NSNumber? {
        if let number = value as? NSNumber {
            return number
        }
        if let int = value as? Int {
            return NSNumber(value: int)
        }
        if let double = value as? Double {
            return NSNumber(value: double)
        }
        return nil
    }

    private static func cgRectValue(_ value: Any) -> CGRect? {
        if let dict = value as? NSDictionary {
            return CGRect(dictionaryRepresentation: dict)
        }
        return nil
    }
}
