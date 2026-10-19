import Foundation

/// Remembers the last choice per source app and per recipient domain, so the
/// chooser can highlight the likely answer and Enter is usually right.
/// Stored in `learned.json` next to the config.
public struct LearnedChoices: Sendable {
    public struct Store: Codable, Equatable, Sendable {
        public var byApp: [String: String] = [:]
        public var byDomain: [String: String] = [:]
        public init() {}
    }

    public let fileURL: URL

    public init(directory: URL) { fileURL = directory.appendingPathComponent("learned.json") }

    public func load() -> Store {
        guard let data = try? Data(contentsOf: fileURL),
              let store = try? JSONDecoder().decode(Store.self, from: data) else { return Store() }
        return store
    }

    public func save(_ store: Store) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? encoder.encode(store).write(to: fileURL, options: .atomic)
    }

    public func record(_ context: RouteContext, destinationID: String) {
        var store = load()
        if let app = context.source?.bundleID { store.byApp[app] = destinationID }
        if let domain = context.request.to.first?.domain, !domain.isEmpty { store.byDomain[domain] = destinationID }
        save(store)
    }

    /// The app's last choice wins over the domain's.
    public func suggestion(for context: RouteContext, validIDs: Set<String>) -> String? {
        let store = load()
        if let app = context.source?.bundleID, let id = store.byApp[app], validIDs.contains(id) { return id }
        if let domain = context.request.to.first?.domain, let id = store.byDomain[domain], validIDs.contains(id) { return id }
        return nil
    }

    public func clear() {
        try? FileManager.default.removeItem(at: fileURL)
    }
}

extension Rule {
    /// Builds an "always" rule from chooser chips. Conditions are ANDed.
    public static func remembered(context: RouteContext, destination: Destination,
                                  app: Bool, domain: Bool, sender: Bool) -> Rule? {
        var when: [Condition] = []
        var names: [String] = []
        if app, let s = context.source {
            when.append(Condition(field: "sourceApp", op: .is, value: s.bundleID))
            names.append(s.name)
        }
        if domain, let d = context.request.to.first?.domain, !d.isEmpty {
            when.append(Condition(field: "to.domain", op: .domainIs, value: d))
            names.append(d)
        }
        if sender, let d = context.original?.from?.domain, !d.isEmpty {
            when.append(Condition(field: "original.from.domain", op: .domainIs, value: d))
            names.append("from \(d)")
        }
        guard !when.isEmpty else { return nil }
        return Rule(name: "\(names.joined(separator: " + ")) → \(destination.name)", match: .all, when: when, then: destination.id)
    }
}
