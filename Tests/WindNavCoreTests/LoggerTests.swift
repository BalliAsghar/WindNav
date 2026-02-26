@testable import WindNavCore
import Foundation
import XCTest

final class LoggerTests: XCTestCase {
    override func setUp() {
        super.setUp()
        Logger._resetForTests()
    }

    override func tearDown() {
        Logger._resetForTests()
        super.tearDown()
    }

    func testFormatsLineWithoutANSIWhenColorNever() {
        let sink = SinkBox()
        Logger._setTestSink { line in sink.append(line) }
        Logger._setTestNowProvider { Date(timeIntervalSince1970: 0) }
        Logger.configure(level: .info, colorMode: .never)

        Logger.info(.runtime, "Boot")

        let lines = sink.lines()
        XCTAssertEqual(lines.count, 1)
        let line = lines[0]
        XCTAssertTrue(line.contains(" -> Boot"))
        XCTAssertTrue(line.contains("Runtime"))
        XCTAssertFalse(line.contains("\u{001B}["))

        let systemField = systemToken(from: line)
        XCTAssertEqual(systemField?.count, 10)
    }

    func testAutoColorUsesTTYSignal() {
        let sink = SinkBox()
        Logger._setTestSink { line in sink.append(line) }
        Logger._setTestNowProvider { Date(timeIntervalSince1970: 0) }

        Logger._setTestIsTTYProvider { false }
        Logger.configure(level: .info, colorMode: .auto)
        Logger.info(.hotkey, "No color")
        XCTAssertFalse(sink.lines().last?.contains("\u{001B}[") == true)

        sink.clear()

        Logger._setTestIsTTYProvider { true }
        Logger.configure(level: .info, colorMode: .auto)
        Logger.info(.hotkey, "Has color")
        XCTAssertTrue(sink.lines().last?.contains("\u{001B}[") == true)
    }

    func testAlwaysColorEmitsANSIWhenNotTTY() {
        let sink = SinkBox()
        Logger._setTestSink { line in sink.append(line) }
        Logger._setTestNowProvider { Date(timeIntervalSince1970: 0) }
        Logger._setTestIsTTYProvider { false }
        Logger.configure(level: .info, colorMode: .always)

        Logger.info(.config, "Color on")

        XCTAssertTrue(sink.lines().last?.contains("\u{001B}[") == true)
    }

    func testErrorLevelSuppressesInfoLogs() {
        let sink = SinkBox()
        Logger._setTestSink { line in sink.append(line) }
        Logger._setTestNowProvider { Date(timeIntervalSince1970: 0) }
        Logger.configure(level: .error, colorMode: .never)

        Logger.info(.runtime, "Info message")
        Logger.error(.runtime, "Error message")

        let lines = sink.lines()
        XCTAssertEqual(lines.count, 1)
        XCTAssertTrue(lines[0].contains("Error message"))
    }
}

private func systemToken(from line: String) -> String? {
    guard let closeBracket = line.firstIndex(of: "]") else { return nil }
    guard let arrowRange = line.range(of: " -> ") else { return nil }
    let start = line.index(after: closeBracket)
    guard start < arrowRange.lowerBound else { return nil }
    let raw = String(line[start ..< arrowRange.lowerBound])
    guard raw.hasPrefix(" ") else { return nil }
    return String(raw.dropFirst())
}

private final class SinkBox: @unchecked Sendable {
    private var values: [String] = []
    private let lock = NSLock()

    func append(_ line: String) {
        lock.lock()
        values.append(line)
        lock.unlock()
    }

    func lines() -> [String] {
        lock.lock()
        defer { lock.unlock() }
        return values
    }

    func clear() {
        lock.lock()
        values.removeAll()
        lock.unlock()
    }
}
