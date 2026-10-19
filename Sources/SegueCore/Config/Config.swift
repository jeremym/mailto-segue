import Foundation

/// `~/Library/Application Support/Segue/config.json`, schema version 1.
/// Kept flat and optional-heavy on purpose so the JSON stays short and easy to
/// edit by hand. `validate()` reports what doesn't add up.
public struct Config: Codable, Equatable, Sendable {
    public static let currentVersion = 1

    public var version: Int = Config.currentVersion
    /// What happens when no rule matches: show the chooser, or go to a destination.
    public var fallback: Fallback = .chooser
    public var destinations: [Destination] = []
    public var rules: [Rule] = []
    public var chooser = ChooserSettings()
    public var eml = EmlSettings()
    public var history = HistorySettings()
    public var general = GeneralSettings()

    public init() {}

    enum CodingKeys: String, CodingKey { case version, fallback, destinations, rules, chooser, eml, history, general }

    /// Every key is optional on disk, so a hand-written three-line config works.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? Config.currentVersion
        fallback = try c.decodeIfPresent(Fallback.self, forKey: .fallback) ?? .chooser
        destinations = try c.decodeIfPresent([Destination].self, forKey: .destinations) ?? []
        rules = try c.decodeIfPresent([Rule].self, forKey: .rules) ?? []
        chooser = try c.decodeIfPresent(ChooserSettings.self, forKey: .chooser) ?? ChooserSettings()
        eml = try c.decodeIfPresent(EmlSettings.self, forKey: .eml) ?? EmlSettings()
        history = try c.decodeIfPresent(HistorySettings.self, forKey: .history) ?? HistorySettings()
        general = try c.decodeIfPresent(GeneralSettings.self, forKey: .general) ?? GeneralSettings()
    }

    public enum Fallback: Equatable, Sendable, Codable {
        case chooser
        case destination(String)

        public init(from decoder: Decoder) throws {
            let s = try decoder.singleValueContainer().decode(String.self)
            self = s == "chooser" ? .chooser : .destination(s)
        }

        public func encode(to encoder: Encoder) throws {
            var c = encoder.singleValueContainer()
            switch self {
            case .chooser: try c.encode("chooser")
            case .destination(let id): try c.encode(id)
            }
        }
    }

    public func destination(id: String) -> Destination? {
        destinations.first { $0.id == id }
    }

    /// Destinations that are enabled, pinned first, otherwise in file order.
    public var activeDestinations: [Destination] {
        let active = destinations.filter { $0.enabled ?? true }
        return active.filter { $0.pinned ?? false } + active.filter { !($0.pinned ?? false) }
    }

    /// Every address the user sends as, lowercased.
    public var myAddresses: Set<String> {
        Set(destinations.flatMap { $0.sendsAs ?? [] }.map { $0.lowercased() })
    }

    /// Human-readable problems. Empty means the config is usable.
    public func validate() -> [String] {
        var issues: [String] = []
        if version > Config.currentVersion {
            issues.append("config version \(version) is newer than this Segue understands (\(Config.currentVersion))")
        }
        var seen = Set<String>()
        for d in destinations {
            if d.id.isEmpty { issues.append("a destination has an empty id") }
            if !seen.insert(d.id).inserted { issues.append("duplicate destination id '\(d.id)'") }
            issues += d.validate().map { "destination '\(d.id)': \($0)" }
        }
        for r in rules {
            if let then = r.then, !seen.contains(then) {
                issues.append("rule '\(r.name)' points at unknown destination '\(then)'")
            }
            if r.builtin == nil, r.then == nil {
                issues.append("rule '\(r.name)' has no 'then' destination")
            }
            if let b = r.builtin, Rule.Builtin(rawValue: b) == nil {
                issues.append("rule '\(r.name)' uses unknown builtin '\(b)'")
            }
        }
        if case .destination(let id) = fallback, !seen.contains(id) {
            issues.append("fallback points at unknown destination '\(id)'")
        }
        return issues
    }
}

public struct ChooserSettings: Codable, Equatable, Sendable {
    public enum Layout: String, Codable, CaseIterable, Sendable { case largeTiles, smallTiles, compactList }
    public enum Position: String, Codable, CaseIterable, Sendable { case center, mouse }
    public enum Modifier: String, Codable, CaseIterable, Sendable { case option, shift, control, command }

    public var layout: Layout = .largeTiles
    public var autoLayout: Bool = false
    public var textScale: Double = 1.4
    /// Holding this key when a link arrives always shows the chooser.
    public var forceModifier: Modifier = .option
    public var position: Position = .center
    /// Highlight the last choice for this source app / recipient domain.
    public var learnDefault: Bool = true

    public init() {}

    enum CodingKeys: String, CodingKey { case layout, autoLayout, textScale, forceModifier, position, learnDefault }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        layout = try c.decodeIfPresent(Layout.self, forKey: .layout) ?? .largeTiles
        autoLayout = try c.decodeIfPresent(Bool.self, forKey: .autoLayout) ?? false
        textScale = try c.decodeIfPresent(Double.self, forKey: .textScale) ?? 1.4
        forceModifier = try c.decodeIfPresent(Modifier.self, forKey: .forceModifier) ?? .option
        position = try c.decodeIfPresent(Position.self, forKey: .position) ?? .center
        learnDefault = try c.decodeIfPresent(Bool.self, forKey: .learnDefault) ?? true
    }
}

public struct EmlSettings: Codable, Equatable, Sendable {
    /// When true, a matching rule routes an opened .eml without a click.
    public var autoRoute: Bool = false
    public init() {}

    enum CodingKeys: String, CodingKey { case autoRoute }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        autoRoute = try c.decodeIfPresent(Bool.self, forKey: .autoRoute) ?? false
    }
}

public struct HistorySettings: Codable, Equatable, Sendable {
    /// 0 turns history off.
    public var keepItems: Int = 500
    public var maxMB: Int = 50
    public init() {}

    enum CodingKeys: String, CodingKey { case keepItems, maxMB }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        keepItems = try c.decodeIfPresent(Int.self, forKey: .keepItems) ?? 500
        maxMB = try c.decodeIfPresent(Int.self, forKey: .maxMB) ?? 50
    }
}

public struct GeneralSettings: Codable, Equatable, Sendable {
    /// Opt-in resident mode: menu-bar icon and a login item. Default is
    /// launch-per-event and quit.
    public var stayRunning: Bool = false
    /// Treat `+` in mailto values as a space (some senders do that).
    public var plusAsSpace: Bool = false
    /// "Pause rules": every link shows the chooser until this is turned off.
    public var rulesPaused: Bool = false
    public init() {}

    enum CodingKeys: String, CodingKey { case stayRunning, plusAsSpace, rulesPaused }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        stayRunning = try c.decodeIfPresent(Bool.self, forKey: .stayRunning) ?? false
        plusAsSpace = try c.decodeIfPresent(Bool.self, forKey: .plusAsSpace) ?? false
        rulesPaused = try c.decodeIfPresent(Bool.self, forKey: .rulesPaused) ?? false
    }
}
