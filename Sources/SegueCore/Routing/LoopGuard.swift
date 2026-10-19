import Foundation

/// Stops a mailto: from bouncing forever. Segue launches per event, so the
/// memory of "what we just sent where" has to live on disk.
///
/// A bounce looks like: we handed `mailto:x` to a browser or an app a moment
/// ago, and the same `mailto:x` is back, sent by that app (or by nobody we can
/// name). The caller then shows the chooser instead of repeating the route.
public struct LoopGuard: Sendable {
    public struct Record: Codable, Equatable, Sendable {
        public var mailto: String
        public var destinationID: String
        /// Bundle ID of the app we handed the link to, if any.
        public var targetBundleID: String?
        public var at: Date
    }

    public static let window: TimeInterval = 3

    public let fileURL: URL

    public init(fileURL: URL) { self.fileURL = fileURL }

    public init(directory: URL) { self.fileURL = directory.appendingPathComponent("last-route.json") }

    public func remember(mailto: String, destinationID: String, targetBundleID: String?, now: Date = Date()) {
        let record = Record(mailto: mailto, destinationID: destinationID, targetBundleID: targetBundleID, at: now)
        try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(record) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }

    public func lastRecord() -> Record? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? JSONDecoder().decode(Record.self, from: data)
    }

    /// Returns the record of the route being bounced, or nil if this is a fresh link.
    public func bounce(for mailto: String, sourceBundleID: String?, now: Date = Date()) -> Record? {
        guard let last = lastRecord() else { return nil }
        guard now.timeIntervalSince(last.at) < LoopGuard.window else { return nil }
        guard LoopGuard.sameLink(last.mailto, mailto) else { return nil }
        if let source = sourceBundleID, let target = last.targetBundleID, source != target {
            // Someone else sent an identical link right away. Unusual, but not a bounce.
            return nil
        }
        return last
    }

    /// Browsers re-encode links before bouncing them, so compare the parsed fields.
    static func sameLink(_ a: String, _ b: String) -> Bool {
        a == b || MailtoParser.parse(a) == MailtoParser.parse(b)
    }
}
