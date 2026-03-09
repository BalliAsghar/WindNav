import Foundation

struct HUDMetadataLines: Equatable, Sendable {
    let primary: String
    let secondary: String
}

enum HUDMetadataFormatter {
    static func lines(for window: WindowSnapshot) -> HUDMetadataLines {
        let appName = WindowSnapshotSupport.appLabel(for: [window])
        let normalizedAppName = normalize(window.appName)
            ?? normalize(window.bundleId)
            ?? normalize(appName)
            ?? "App"

        guard let normalizedTitle = normalize(window.title) else {
            return HUDMetadataLines(primary: normalizedAppName, secondary: "")
        }

        guard !equivalent(normalizedTitle, normalizedAppName) else {
            return HUDMetadataLines(primary: normalizedAppName, secondary: "")
        }

        return HUDMetadataLines(primary: normalizedTitle, secondary: normalizedAppName)
    }

    private static func normalize(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }

    private static func equivalent(_ lhs: String, _ rhs: String) -> Bool {
        lhs.compare(rhs, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
    }
}
