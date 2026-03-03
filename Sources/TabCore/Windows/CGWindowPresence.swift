import ApplicationServices
import CoreGraphics
import Foundation

enum CGWindowEvidence: Int, Comparable {
    case none = 0
    case weak = 1
    case strong = 2

    static func < (lhs: CGWindowEvidence, rhs: CGWindowEvidence) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

enum AXWindowFallbackKind: Equatable {
    case none
    case activationFallback
    case confirmedWindowless
}

enum AXWindowFallbackClassifier {
    static func fallbackKind(
        bundleId: String?,
        showEmptyApps: VisibilityConfig.ShowEmptyAppsPolicy,
        cgEvidence: CGWindowEvidence
    ) -> AXWindowFallbackKind {
        if bundleId == "com.apple.finder" {
            return .none
        }
        if showEmptyApps == .hide {
            return .none
        }
        return cgEvidence == .strong ? .activationFallback : .confirmedWindowless
    }
}

enum AXWindowEligibility {
    static func acceptsSubrole(_ subrole: String, isFullscreen: Bool) -> Bool {
        subrole == (kAXStandardWindowSubrole as String) || isFullscreen
    }
}

enum CGWindowPresence {
    static func collectWindowEvidenceByPID() -> [pid_t: CGWindowEvidence] {
        guard
            let info = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]]
        else {
            return [:]
        }
        return windowEvidenceByPID(from: info)
    }

    static func windowEvidenceByPID(from windowInfo: [[String: Any]]) -> [pid_t: CGWindowEvidence] {
        var result: [pid_t: CGWindowEvidence] = [:]
        for entry in windowInfo {
            guard let ownerPID = numberValue(entry[kCGWindowOwnerPID as String]) else { continue }
            guard numberValue(entry[kCGWindowLayer as String])?.intValue == 0 else { continue }

            if let alpha = numberValue(entry[kCGWindowAlpha as String]), alpha.doubleValue <= 0 {
                continue
            }

            guard let boundsRaw = entry[kCGWindowBounds as String] else { continue }
            guard let bounds = cgRectValue(boundsRaw) else { continue }
            if bounds.width <= 100 || bounds.height <= 50 { continue }

            let isOnScreen = boolValue(entry[kCGWindowIsOnscreen as String]) ?? false
            let isLargeOffscreen = bounds.width >= 700 && bounds.height >= 400
            let evidence: CGWindowEvidence = (isOnScreen || isLargeOffscreen) ? .strong : .weak

            let pid = pid_t(ownerPID.intValue)
            let previous = result[pid] ?? .none
            if evidence > previous {
                result[pid] = evidence
            }
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

    private static func boolValue(_ value: Any?) -> Bool? {
        if let bool = value as? Bool {
            return bool
        }
        if let number = value as? NSNumber {
            return number.boolValue
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
