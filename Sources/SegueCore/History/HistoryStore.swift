import Foundation

/// One hand-off Segue made.
public struct HistoryItem: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var date: Date
    public var kind: RouteContext.Kind
    public var source: SourceApp?
    public var to: [String]
    public var cc: [String]
    public var bcc: [String]
    public var subject: String
    public var destinationID: String
    public var destinationName: String
    public var explanation: Explanation
    /// Path of the `.eml` this came from, if any (may no longer exist).
    public var emlPath: String?
    public var attachments: [String] = []
    /// True when a compressed body is stored alongside.
    public var hasBody: Bool
    public var bodyBytes: Int = 0

    public init(id: String = UUID().uuidString, date: Date = Date(), kind: RouteContext.Kind, source: SourceApp?,
                request: ComposeRequest, destination: Destination, explanation: Explanation,
                emlPath: String? = nil, attachments: [String] = [], hasBody: Bool = false) {
        self.id = id
        self.date = date
        self.kind = kind
        self.source = source
        self.to = request.to.map(\.description)
        self.cc = request.cc.map(\.description)
        self.bcc = request.bcc.map(\.description)
        self.subject = request.subject ?? ""
        self.destinationID = destination.id
        self.destinationName = destination.name
        self.explanation = explanation
        self.emlPath = emlPath
        self.attachments = attachments
        self.hasBody = hasBody
    }

    public var primaryRecipient: String { to.first ?? cc.first ?? bcc.first ?? "" }
}

/// `history/index.json` plus one LZFSE-compressed body per item in
/// `history/bodies/`. Capped by item count and total size; 0 items = off.
public final class HistoryStore: @unchecked Sendable {
    public let directory: URL
    public var indexURL: URL { directory.appendingPathComponent("index.json") }
    public var bodiesURL: URL { directory.appendingPathComponent("bodies", isDirectory: true) }
    private let lock = NSLock()

    public init(supportDirectory: URL) {
        directory = supportDirectory.appendingPathComponent("history", isDirectory: true)
    }

    public func items() -> [HistoryItem] {
        lock.lock(); defer { lock.unlock() }
        return loadIndex()
    }

    /// Records a hand-off. `body` is the full compose body (or the original
    /// message text for replies); it is compressed and stored unless history
    /// is off. Returns the stored item, or nil if history is off.
    @discardableResult
    public func record(_ item: HistoryItem, body: String?, settings: HistorySettings) -> HistoryItem? {
        guard settings.keepItems > 0 else { return nil }
        lock.lock(); defer { lock.unlock() }
        var item = item
        var index = loadIndex()
        try? FileManager.default.createDirectory(at: bodiesURL, withIntermediateDirectories: true)
        if let body, !body.isEmpty, let data = body.data(using: .utf8),
           let compressed = try? (data as NSData).compressed(using: .lzfse) as Data {
            let url = bodiesURL.appendingPathComponent(item.id + ".lzfse")
            if (try? compressed.write(to: url, options: .atomic)) != nil {
                item.hasBody = true
                item.bodyBytes = compressed.count
            }
        }
        index.insert(item, at: 0)
        index = trim(index, settings: settings)
        saveIndex(index)
        return item
    }

    public func body(for item: HistoryItem) -> String? {
        guard item.hasBody else { return nil }
        let url = bodiesURL.appendingPathComponent(item.id + ".lzfse")
        guard let data = try? Data(contentsOf: url),
              let raw = try? (data as NSData).decompressed(using: .lzfse) as Data else { return nil }
        return String(data: raw, encoding: .utf8)
    }

    public func remove(id: String) {
        lock.lock(); defer { lock.unlock() }
        var index = loadIndex()
        index.removeAll { $0.id == id }
        try? FileManager.default.removeItem(at: bodiesURL.appendingPathComponent(id + ".lzfse"))
        saveIndex(index)
    }

    public func clear() {
        lock.lock(); defer { lock.unlock() }
        try? FileManager.default.removeItem(at: directory)
    }

    /// Items and bytes on disk (index + bodies).
    public func usage() -> (items: Int, bytes: Int) {
        lock.lock(); defer { lock.unlock() }
        let index = loadIndex()
        var bytes = (try? FileManager.default.attributesOfItem(atPath: indexURL.path)[.size] as? Int) ?? 0
        bytes += index.reduce(0) { $0 + $1.bodyBytes }
        return (index.count, bytes)
    }

    /// Re-applies the caps (after the user lowers them in Settings).
    public func enforce(settings: HistorySettings) {
        lock.lock(); defer { lock.unlock() }
        if settings.keepItems == 0 {
            try? FileManager.default.removeItem(at: directory)
            return
        }
        saveIndex(trim(loadIndex(), settings: settings))
    }

    // MARK: - Private

    private func trim(_ index: [HistoryItem], settings: HistorySettings) -> [HistoryItem] {
        var kept: [HistoryItem] = []
        var bytes = 0
        let maxBytes = settings.maxMB * 1_000_000
        for item in index {
            if kept.count >= settings.keepItems || bytes + item.bodyBytes > maxBytes {
                try? FileManager.default.removeItem(at: bodiesURL.appendingPathComponent(item.id + ".lzfse"))
                continue
            }
            kept.append(item)
            bytes += item.bodyBytes
        }
        return kept
    }

    private func loadIndex() -> [HistoryItem] {
        guard let data = try? Data(contentsOf: indexURL) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([HistoryItem].self, from: data)) ?? []
    }

    private func saveIndex(_ index: [HistoryItem]) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        try? encoder.encode(index).write(to: indexURL, options: .atomic)
    }
}
