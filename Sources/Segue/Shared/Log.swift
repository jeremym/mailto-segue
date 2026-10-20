import Foundation

/// A small append-only log at `<support>/segue.log`, because a per-event app
/// is gone before anyone can attach a debugger. Kept under ~1 MB.
enum Log {
    nonisolated(unsafe) static var fileURL: URL?
    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return f
    }()

    static func write(_ message: String) {
        NSLog("Segue: %@", message)
        guard let url = fileURL else { return }
        let line = "\(formatter.string(from: Date())) [\(getpid())] \(message)\n"
        guard let data = line.data(using: .utf8) else { return }
        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            if let size = try? handle.seekToEnd(), size > 1_000_000 {
                try? handle.truncate(atOffset: 0)
            }
            try? handle.write(contentsOf: data)
        } else {
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? data.write(to: url)
        }
    }
}
