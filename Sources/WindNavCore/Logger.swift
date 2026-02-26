import Darwin
import Foundation

public enum LogLevel: String, Sendable {
    case info
    case error
}

public enum LogColorMode: String, Sendable {
    case auto
    case always
    case never
}

public enum LogSystem: String, Sendable {
    case runtime = "Runtime"
    case config = "Config"
    case startup = "Startup"
    case hotkey = "Hotkey"
    case navigation = "Navigation"
    case ax = "AX"
    case cache = "Cache"
    case observer = "Observer"

    fileprivate var ansiColor: String {
        switch self {
            case .runtime:
                ANSIColor.cyan
            case .config:
                ANSIColor.yellow
            case .startup:
                ANSIColor.brightYellow
            case .hotkey:
                ANSIColor.magenta
            case .navigation:
                ANSIColor.blue
            case .ax:
                ANSIColor.green
            case .cache:
                ANSIColor.brightCyan
            case .observer:
                ANSIColor.brightMagenta
        }
    }
}

public struct Logger {
    nonisolated(unsafe) private static var state = State()
    private static let queue = DispatchQueue(label: "windnav.logger")

    public static func configure(level: LogLevel, colorMode: LogColorMode) {
        queue.sync {
            state.level = level
            state.colorMode = colorMode
            state.useColor = resolveColorUsage(colorMode: colorMode, isTTY: state.isTTYProvider())
        }
    }

    public static func info(_ system: LogSystem, _ message: String) {
        log(level: .info, system: system, message: message)
    }

    public static func error(_ system: LogSystem, _ message: String) {
        log(level: .error, system: system, message: message)
    }

    private static func log(level: LogLevel, system: LogSystem, message: String) {
        queue.sync {
            guard shouldEmit(incoming: level, configured: state.level) else {
                return
            }

            let timestamp = timestampString(from: state.nowProvider())
            let systemPadded = system.rawValue.padding(toLength: 10, withPad: " ", startingAt: 0)
            let line = formatLine(
                timestamp: timestamp,
                system: systemPadded,
                systemColor: system.ansiColor,
                message: message,
                useColor: state.useColor
            )
            state.sink(line)
        }
    }

    private static func shouldEmit(incoming: LogLevel, configured: LogLevel) -> Bool {
        switch configured {
            case .info:
                return true
            case .error:
                return incoming == .error
        }
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
        var useColor: Bool = true

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

private enum ANSIColor {
    static let reset = "\u{001B}[0m"
    static let gray = "\u{001B}[90m"
    static let cyan = "\u{001B}[36m"
    static let yellow = "\u{001B}[33m"
    static let brightYellow = "\u{001B}[93m"
    static let magenta = "\u{001B}[35m"
    static let blue = "\u{001B}[34m"
    static let green = "\u{001B}[32m"
    static let brightCyan = "\u{001B}[96m"
    static let brightMagenta = "\u{001B}[95m"
}
