import Foundation

public enum LogCategory: String, Sendable {
    case runtime
    case config
    case hotkey
    case windows
    case navigation
    case ui
}

public enum LogLevel: String, Sendable {
    case debug
    case info
    case error

    fileprivate var priority: Int {
        switch self {
            case .debug: return 0
            case .info: return 1
            case .error: return 2
        }
    }
}

public enum Logger {
    public typealias Sink = @Sendable (String) -> Void

    private static let lock = NSLock()
    private nonisolated(unsafe) static var level: LogLevel = .info
    private nonisolated(unsafe) static var sink: Sink = { print($0) }

    public static func configure(level: LogLevel) {
        lock.lock()
        Self.level = level
        lock.unlock()
    }

    static func _setSinkForTests(_ sink: @escaping Sink) {
        lock.lock()
        Self.sink = sink
        lock.unlock()
    }

    static func _resetSinkForTests() {
        lock.lock()
        sink = { print($0) }
        lock.unlock()
    }

    public static func debug(_ category: LogCategory, _ message: @autoclosure () -> String) {
        log(.debug, category, message())
    }

    public static func info(_ category: LogCategory, _ message: @autoclosure () -> String) {
        log(.info, category, message())
    }

    public static func error(_ category: LogCategory, _ message: @autoclosure () -> String) {
        log(.error, category, message())
    }

    public static func log(_ level: LogLevel, _ category: LogCategory, _ message: String) {
        lock.lock()
        let configured = Self.level
        let output = sink
        lock.unlock()

        guard level.priority >= configured.priority else { return }
        output("[\(timestamp())] [\(level.rawValue.uppercased())] [\(category.rawValue)] \(message)")
    }

    private static func timestamp() -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: Date())
    }
}
