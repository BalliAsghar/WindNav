import Darwin
import Foundation

public enum LogCategory: String, Sendable {
    case runtime
    case config
    case hotkey
    case windows
    case navigation
    case ui
    case capture
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

public enum LogColorMode: String, Sendable {
    case auto
    case always
    case never
}

public struct Logger {
    nonisolated(unsafe) private static var state = State()
    private static let queue = DispatchQueue(label: "tabpp.logger")

    public static func configure(level: LogLevel, colorMode: LogColorMode) {
        queue.sync {
            state.level = level
            state.colorMode = colorMode
            state.useColor = resolveColorUsage(colorMode: colorMode, isTTY: state.isTTYProvider())
        }
    }

    public static func debug(_ category: LogCategory, _ message: @autoclosure () -> String) {
        log(level: .debug, category: category, message: message())
    }

    public static func info(_ category: LogCategory, _ message: @autoclosure () -> String) {
        log(level: .info, category: category, message: message())
    }

    public static func error(_ category: LogCategory, _ message: @autoclosure () -> String) {
        log(level: .error, category: category, message: message())
    }

    private static func log(level: LogLevel, category: LogCategory, message: String) {
        queue.sync {
            guard shouldEmit(incoming: level, configured: state.level) else {
                return
            }

            let timestamp = timestampString(from: state.nowProvider())
            let system = category.displayName.padding(toLength: 10, withPad: " ", startingAt: 0)
            let line = formatLine(
                timestamp: timestamp,
                system: system,
                systemColor: category.ansiColor,
                message: message,
                useColor: state.useColor
            )
            state.sink(line)
        }
    }

    private static func shouldEmit(incoming: LogLevel, configured: LogLevel) -> Bool {
        incoming.priority >= configured.priority
    }

    private static func resolveColorUsage(colorMode: LogColorMode, isTTY: Bool) -> Bool {
        switch colorMode {
            case .auto:
                return isTTY
            case .always:
                return true
            case .never:
                return false
        }
    }

    private static func timestampString(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.string(from: date)
    }

    private static func formatLine(
        timestamp: String,
        system: String,
        systemColor: String,
        message: String,
        useColor: Bool
    ) -> String {
        if useColor {
            return "\(ANSIColor.gray)[\(timestamp)]\(ANSIColor.reset) \(systemColor)\(system)\(ANSIColor.reset) -> \(message)\n"
        }
        return "[\(timestamp)] \(system) -> \(message)\n"
    }

    private static func defaultSink(_ line: String) {
        guard let data = line.data(using: .utf8) else { return }
        FileHandle.standardOutput.write(data)
        fflush(stdout)
    }

    private static func defaultIsTTY() -> Bool {
        isatty(fileno(stdout)) == 1
    }

    private struct State {
        var level: LogLevel = .info
        var colorMode: LogColorMode = .auto
        var useColor = Logger.defaultIsTTY()

        var nowProvider: @Sendable () -> Date = Date.init
        var isTTYProvider: @Sendable () -> Bool = Logger.defaultIsTTY
        var sink: @Sendable (String) -> Void = Logger.defaultSink
    }
}

extension Logger {
    static func _setTestNowProvider(_ nowProvider: @escaping @Sendable () -> Date) {
        queue.sync {
            state.nowProvider = nowProvider
            state.useColor = resolveColorUsage(colorMode: state.colorMode, isTTY: state.isTTYProvider())
        }
    }

    static func _setTestIsTTYProvider(_ isTTYProvider: @escaping @Sendable () -> Bool) {
        queue.sync {
            state.isTTYProvider = isTTYProvider
            state.useColor = resolveColorUsage(colorMode: state.colorMode, isTTY: state.isTTYProvider())
        }
    }

    static func _setTestSink(_ sink: @escaping @Sendable (String) -> Void) {
        queue.sync {
            state.sink = sink
        }
    }

    static func _resetForTests() {
        queue.sync {
            state = State()
            state.useColor = resolveColorUsage(colorMode: state.colorMode, isTTY: state.isTTYProvider())
        }
    }
}

private extension LogCategory {
    var displayName: String {
        switch self {
            case .runtime: return "Runtime"
            case .config: return "Config"
            case .hotkey: return "Hotkey"
            case .windows: return "Windows"
            case .navigation: return "Navigation"
            case .ui: return "UI"
            case .capture: return "Capture"
        }
    }

    var ansiColor: String {
        switch self {
            case .runtime: return ANSIColor.cyan
            case .config: return ANSIColor.yellow
            case .hotkey: return ANSIColor.magenta
            case .windows: return ANSIColor.green
            case .navigation: return ANSIColor.blue
            case .ui: return ANSIColor.brightCyan
            case .capture: return ANSIColor.yellow
        }
    }
}

private enum ANSIColor {
    static let reset = "\u{001B}[0m"
    static let gray = "\u{001B}[90m"
    static let cyan = "\u{001B}[36m"
    static let yellow = "\u{001B}[33m"
    static let magenta = "\u{001B}[35m"
    static let green = "\u{001B}[32m"
    static let blue = "\u{001B}[34m"
    static let brightCyan = "\u{001B}[96m"
}
