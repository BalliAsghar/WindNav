import Darwin
import Foundation

@MainActor
final class ConfigWatcher {
    private let configURL: URL
    private let queue = DispatchQueue(label: "windnav.config-watcher")

    private var directoryFD: Int32 = -1
    private var fileFD: Int32 = -1

    private var directorySource: DispatchSourceFileSystemObject?
    private var fileSource: DispatchSourceFileSystemObject?
    private var debounceWorkItem: DispatchWorkItem?

    init(configURL: URL) {
        self.configURL = configURL
    }

    func start(onChange: @escaping @MainActor () -> Void) {
        stop()
        Logger.info(.config, "Starting config watcher at \(configURL.path)")

        startDirectoryWatcher(onChange: onChange)
        startFileWatcherIfPossible(onChange: onChange)
    }

    func stop() {
        if directorySource != nil || fileSource != nil {
            Logger.info(.config, "Stopping config watcher")
        }
        debounceWorkItem?.cancel()
        debounceWorkItem = nil

        directorySource?.cancel()
        directorySource = nil
        if directoryFD != -1 {
            close(directoryFD)
            directoryFD = -1
        }

        fileSource?.cancel()
        fileSource = nil
        if fileFD != -1 {
            close(fileFD)
            fileFD = -1
        }
    }

    private func startDirectoryWatcher(onChange: @escaping @MainActor () -> Void) {
        let directory = configURL.deletingLastPathComponent()
        directoryFD = open(directory.path, O_EVTONLY)
        guard directoryFD >= 0 else {
            Logger.error(.config, "Failed to watch config directory: \(directory.path)")
            return
        }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: directoryFD,
            eventMask: [.write, .rename, .delete, .attrib],
            queue: queue
        )

        source.setEventHandler { [weak self] in
            guard let self else { return }
            Logger.info(.config, "Config directory changed; refreshing file watcher")
            self.startFileWatcherIfPossible(onChange: onChange)
            self.scheduleReload(onChange: onChange)
        }

        source.setCancelHandler { [weak self] in
            guard let self else { return }
            if self.directoryFD != -1 {
                close(self.directoryFD)
                self.directoryFD = -1
            }
        }

        source.resume()
        directorySource = source
        Logger.info(.config, "Watching config directory: \(directory.path)")
    }

    private func startFileWatcherIfPossible(onChange: @escaping @MainActor () -> Void) {
        fileSource?.cancel()
        fileSource = nil
        if fileFD != -1 {
            close(fileFD)
            fileFD = -1
        }

        guard FileManager.default.fileExists(atPath: configURL.path) else { return }

        fileFD = open(configURL.path, O_EVTONLY)
        guard fileFD >= 0 else {
            Logger.error(.config, "Failed to watch config file: \(configURL.path)")
            return
        }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fileFD,
            eventMask: [.write, .rename, .delete, .attrib],
            queue: queue
        )

        source.setEventHandler { [weak self] in
            guard let self else { return }
            Logger.info(.config, "Config file changed event received")
            self.scheduleReload(onChange: onChange)
        }

        source.setCancelHandler { [weak self] in
            guard let self else { return }
            if self.fileFD != -1 {
                close(self.fileFD)
                self.fileFD = -1
            }
        }

        source.resume()
        fileSource = source
        Logger.info(.config, "Watching config file: \(configURL.path)")
    }

    private func scheduleReload(onChange: @escaping @MainActor () -> Void) {
        debounceWorkItem?.cancel()

        let item = DispatchWorkItem { [weak self] in
            guard self != nil else { return }
            Task { @MainActor in
                onChange()
            }
        }

        debounceWorkItem = item
        Logger.info(.config, "Scheduled config reload")
        queue.asyncAfter(deadline: .now() + 0.20, execute: item)
    }
}
