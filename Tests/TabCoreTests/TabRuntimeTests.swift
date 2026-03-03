@testable import TabCore
import XCTest

@MainActor
final class TabRuntimeTests: XCTestCase {
    func testRuntimeCanInitializeAndStop() {
        let runtime = TabRuntime(configURL: nil)
        runtime.stop()
    }
}
