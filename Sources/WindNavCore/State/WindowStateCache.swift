import Foundation

@MainActor
final class WindowStateCache {
    private let provider: WindowProvider
    private(set) var snapshot: [WindowSnapshot] = []
    private var lastLoggedWindowCount: Int?

    init(provider: WindowProvider) {
        self.provider = provider
    }

    func refresh() async {
        do {
            snapshot = try await provider.currentSnapshot()
            if lastLoggedWindowCount != snapshot.count {
                Logger.info(.cache, "Window snapshot count changed: \(snapshot.count)")
                lastLoggedWindowCount = snapshot.count
            }
        } catch {
            Logger.error(.cache, "Failed to refresh window cache: \(error.localizedDescription)")
        }
    }

    func refreshAndGetSnapshot() async -> [WindowSnapshot] {
        await refresh()
        return snapshot
    }
}
