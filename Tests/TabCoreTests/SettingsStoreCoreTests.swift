@testable import TabCore
import Foundation
import XCTest

@MainActor
final class SettingsStoreCoreTests: XCTestCase {
    func testLoadAndSavePersistsFeatureToggles() throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let url = dir.appending(path: "config.toml", directoryHint: .notDirectory)
        let store = FileSettingsStateStore(configURL: url)

        var config = try store.loadOrCreate()
        config.activation.overrideSystemCmdTab = false
        config.directional.enabled = false
        try store.save(config)

        let reloaded = try store.loadOrCreate()
        XCTAssertFalse(reloaded.activation.overrideSystemCmdTab)
        XCTAssertFalse(reloaded.directional.enabled)
    }
}
