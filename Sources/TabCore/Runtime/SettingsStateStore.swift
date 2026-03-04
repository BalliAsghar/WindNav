import Foundation

@MainActor
public protocol SettingsStateStore: AnyObject {
    var configURL: URL { get }
    func loadOrCreate() throws -> TabConfig
    func save(_ config: TabConfig) throws
}

@MainActor
public final class FileSettingsStateStore: SettingsStateStore {
    public let configURL: URL
    private let loader: ConfigLoader

    public init() {
        let configURL = Self.defaultConfigURL()
        self.configURL = configURL
        self.loader = ConfigLoader(configURL: configURL)
    }

    public init(configURL: URL) {
        self.configURL = configURL
        self.loader = ConfigLoader(configURL: configURL)
    }

    public func loadOrCreate() throws -> TabConfig {
        try loader.loadOrCreate()
    }

    public func save(_ config: TabConfig) throws {
        try loader.save(config)
    }

    private static func defaultConfigURL() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appending(path: ".config", directoryHint: .isDirectory)
            .appending(path: "tabpp", directoryHint: .isDirectory)
            .appending(path: "config.toml", directoryHint: .notDirectory)
    }
}
