import Foundation

@MainActor
final class CatalogWindowProvider: WindowProvider, FocusedWindowProvider {
    private let source: AXWindowProvider
    private let catalog: WindowCatalog
    private let monitor: WindowCatalogMonitor

    init(source: AXWindowProvider, catalog: WindowCatalog = WindowCatalog()) {
        self.source = source
        self.catalog = catalog
        self.monitor = WindowCatalogMonitor(catalog: catalog)
    }

    func updateConfig(_ config: TabConfig) {
        source.updateConfig(config)
    }

    func currentSnapshot() async throws -> [WindowSnapshot] {
        _ = monitor
        let rawSnapshots = try await source.currentSnapshot()
        return await catalog.reconcile(rawSnapshots: rawSnapshots)
    }

    func focusedWindowID() async -> UInt32? {
        await source.focusedWindowID()
    }
}
