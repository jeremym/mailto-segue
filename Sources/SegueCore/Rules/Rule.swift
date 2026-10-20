import Foundation

/// An ordered rule. The first enabled rule that matches wins.
public struct Rule: Codable, Equatable, Sendable {
    public enum MatchMode: String, Codable, CaseIterable, Sendable { case all, any }
    public enum Builtin: String, Codable, CaseIterable, Sendable {
        /// Route a reply to the destination that sends as the address the
        /// original message was delivered to.
        case replyFromReceiver
    }

    public var name: String
    public var enabled: Bool = true
    public var builtin: String?
    public var match: MatchMode = .all
    public var when: [Condition] = []
    /// Destination id.
    public var then: String?

    public init(name: String, enabled: Bool = true, match: MatchMode = .all, when: [Condition] = [], then: String?) {
        self.name = name
        self.enabled = enabled
        self.match = match
        self.when = when
        self.then = then
    }

    public init(builtin: Builtin, name: String? = nil, enabled: Bool = true) {
        self.name = name ?? builtin.defaultName
        self.enabled = enabled
        self.builtin = builtin.rawValue
    }

    enum CodingKeys: String, CodingKey { case name, enabled, builtin, match, when, then }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decode(String.self, forKey: .name)
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        builtin = try c.decodeIfPresent(String.self, forKey: .builtin)
        match = try c.decodeIfPresent(MatchMode.self, forKey: .match) ?? .all
        when = try c.decodeIfPresent([Condition].self, forKey: .when) ?? []
        then = try c.decodeIfPresent(String.self, forKey: .then)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(name, forKey: .name)
        try c.encode(enabled, forKey: .enabled)
        try c.encodeIfPresent(builtin, forKey: .builtin)
        if builtin == nil {
            try c.encode(match, forKey: .match)
            try c.encode(when, forKey: .when)
        }
        try c.encodeIfPresent(then, forKey: .then)
    }
}

extension Rule.Builtin {
    public var defaultName: String {
        switch self {
        case .replyFromReceiver: return "Reply from the account that received it"
        }
    }
}

/// `field op value`, e.g. `to.domain domainIs acme.com`.
public struct Condition: Codable, Equatable, Sendable {
    public enum Op: String, Codable, CaseIterable, Sendable {
        case `is`, domainIs, contains, startsWith, matches
    }

    /// A field name from `RouteContext` (see the Rules engine): `kind`,
    /// `sourceApp`, `to`, `to.domain`, `cc`, `cc.domain`, `bcc`, `bcc.domain`,
    /// `recipient`, `recipient.domain`, `subject`, `body`, `original.from`,
    /// `original.from.domain`, `original.deliveredTo`, `original.listId`,
    /// `original.header.<Name>`.
    public var field: String
    public var op: Op
    public var value: String

    public init(field: String, op: Op, value: String) {
        self.field = field
        self.op = op
        self.value = value
    }
}
