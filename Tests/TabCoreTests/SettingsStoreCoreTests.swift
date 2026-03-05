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
        config.directional.enabled = false
        config.onboarding.launchAtLoginEnabled = true
        try store.save(config)

        let reloaded = try store.loadOrCreate()
        XCTAssertFalse(reloaded.directional.enabled)
        XCTAssertTrue(reloaded.onboarding.launchAtLoginEnabled)
    }
}
