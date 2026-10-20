import Foundation

/// Reads and writes `config.json`: pretty-printed, sorted keys, atomic writes.
/// If the file is unreadable or invalid, `load()` keeps the last good config
/// and records the problem in `lastError`.
public final class ConfigStore: @unchecked Sendable {
    public static let folderName = "Mailto Segue"

    public let directory: URL
    public var fileURL: URL { directory.appendingPathComponent("config.json") }

    private let lock = NSLock()
    private var current: Config?
    private(set) public var lastError: String?

    public init(directory: URL) {
        self.directory = directory
    }

    /// `~/Library/Application Support/Mailto Segue`.
    public static func defaultDirectory() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent(folderName, isDirectory: true)
    }

    public static func makeDefault() -> ConfigStore { ConfigStore(directory: defaultDirectory()) }

    public var exists: Bool { FileManager.default.fileExists(atPath: fileURL.path) }

    /// Loads from disk. A missing file gives `Config()` with no error. A bad
    /// file keeps the previous config (or `Config()`) and sets `lastError`.
    @discardableResult
    public func load() -> Config {
        lock.lock(); defer { lock.unlock() }
        guard let data = try? Data(contentsOf: fileURL) else {
            lastError = nil
            if current == nil { current = Config() }
            return current!
        }
        do {
            let config = try ConfigStore.decode(data)
            let issues = config.validate()
            lastError = issues.isEmpty ? nil : issues.joined(separator: "\n")
            current = config
        } catch {
            lastError = "config.json could not be read: \(error.localizedDescription)"
            if current == nil { current = Config() }
        }
        return current!
    }

    public func save(_ config: Config) throws {
        lock.lock(); defer { lock.unlock() }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try ConfigStore.encode(config)
        try data.write(to: fileURL, options: .atomic)
        current = config
        lastError = config.validate().isEmpty ? nil : config.validate().joined(separator: "\n")
    }

    public static func decode(_ data: Data) throws -> Config {
        try JSONDecoder().decode(Config.self, from: data)
    }

    public static func encode(_ config: Config) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        var data = try encoder.encode(config)
        data.append(UInt8(ascii: "\n"))
        return data
    }

    // MARK: - Watching (used only while Segue stays running)

    private var watcher: DispatchSourceFileSystemObject?

    /// Calls `onChange` on the main queue whenever the file is written or
    /// replaced. Atomic saves replace the file, so the watch is re-armed.
    public func startWatching(onChange: @escaping @Sendable () -> Void) {
        stopWatching()
        let fd = open(fileURL.path, O_EVTONLY)
        guard fd >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd, eventMask: [.write, .delete, .rename], queue: .main
        )
        source.setEventHandler { [weak self] in
            onChange()
            if source.data.contains(.delete) || source.data.contains(.rename) {
                // The file was replaced; watch the new inode.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { self?.startWatching(onChange: onChange) }
            }
        }
        source.setCancelHandler { close(fd) }
        source.resume()
        watcher = source
    }

    public func stopWatching() {
        watcher?.cancel()
        watcher = nil
    }
}
