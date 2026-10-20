import Foundation

/// Why a request went where it went. Shown in History and in logs.
public struct Explanation: Codable, Equatable, Sendable {
    public var text: String
    public var ruleName: String?
    public var condition: String?

    public init(text: String, ruleName: String? = nil, condition: String? = nil) {
        self.text = text
        self.ruleName = ruleName
        self.condition = condition
    }

    public static let pickedByUser = Explanation(text: "Picked by you")
    public static let fallback = Explanation(text: "Fallback destination")
    public static let onlyDestination = Explanation(text: "The only destination")
}

/// Evaluates the ordered rule list. First enabled rule that matches wins.
public enum RuleEngine {
    public struct Match: Equatable, Sendable {
        public var destinationID: String
        public var explanation: Explanation
    }

    public static func evaluate(_ context: RouteContext, config: Config) -> Match? {
        for rule in config.rules where rule.enabled {
            if let builtin = rule.builtin {
                guard let kind = Rule.Builtin(rawValue: builtin) else { continue }
                if let match = evaluateBuiltin(kind, rule: rule, context: context, config: config) { return match }
                continue
            }
            guard let then = rule.then, let destination = config.destination(id: then), destination.enabled ?? true else { continue }
            guard !rule.when.isEmpty else { continue }
            let results = rule.when.map { ($0, matches($0, context: context)) }
            let hit: (Condition, Bool)?
            switch rule.match {
            case .all:
                hit = results.allSatisfy { $0.1 } ? results.first : nil
            case .any:
                hit = results.first { $0.1 }
            }
            if let (condition, _) = hit {
                let detail = describe(condition)
                return Match(destinationID: then,
                             explanation: Explanation(text: "Rule “\(rule.name)” matched: \(detail)",
                                                      ruleName: rule.name, condition: detail))
            }
        }
        return nil
    }

    private static func evaluateBuiltin(_ kind: Rule.Builtin, rule: Rule, context: RouteContext, config: Config) -> Match? {
        switch kind {
        case .replyFromReceiver:
            guard let received = context.original?.deliveredTo?.lowercased(), !received.isEmpty else { return nil }
            for d in config.activeDestinations {
                if (d.sendsAs ?? []).contains(where: { $0.lowercased() == received }) {
                    return Match(destinationID: d.id,
                                 explanation: Explanation(text: "Reply from the account that received it (\(received))",
                                                          ruleName: rule.name, condition: "deliveredTo is \(received)"))
                }
            }
            return nil
        }
    }

    // MARK: - Conditions

    public static func matches(_ condition: Condition, context: RouteContext) -> Bool {
        let values = context.values(for: condition.field)
        let target = condition.value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !target.isEmpty else { return false }
        switch condition.op {
        case .is:
            return values.contains { $0.caseInsensitiveCompare(target) == .orderedSame }
        case .domainIs:
            return values.contains { value in
                let domain = value.contains("@") ? EmailAddress(address: value).domain : value.lowercased()
                return EmailAddress(address: "x@" + domain).isIn(domain: target)
            }
        case .contains:
            return values.contains { $0.range(of: target, options: .caseInsensitive) != nil }
        case .startsWith:
            return values.contains { $0.lowercased().hasPrefix(target.lowercased()) }
        case .matches:
            guard let regex = RegexCache.regex(target) else { return false }
            return values.contains { regex.firstMatch(in: $0, range: NSRange($0.startIndex..., in: $0)) != nil }
        }
    }

    public static func describe(_ c: Condition) -> String {
        let op: String
        switch c.op {
        case .is: op = "is"
        case .domainIs: op = "is in domain"
        case .contains: op = "contains"
        case .startsWith: op = "starts with"
        case .matches: op = "matches"
        }
        return "\(c.field) \(op) \(c.value)"
    }
}

/// Compiled regular expressions, so a rule list is cheap to re-evaluate.
enum RegexCache {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var cache: [String: NSRegularExpression] = [:]

    static func regex(_ pattern: String) -> NSRegularExpression? {
        lock.lock(); defer { lock.unlock() }
        if let r = cache[pattern] { return r }
        guard let r = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        cache[pattern] = r
        return r
    }
}

extension RouteContext {
    /// The field names a condition can use.
    public static let fields: [String] = [
        "kind", "sourceApp", "sourceApp.name",
        "to", "to.domain", "cc", "cc.domain", "bcc", "bcc.domain", "recipient", "recipient.domain",
        "subject", "body",
        "original.from", "original.from.domain", "original.deliveredTo", "original.deliveredTo.domain",
        "original.listId", "original.messageId", "original.header.<Name>",
    ]

    /// Every value a field has in this context. Multi-valued fields (`to`)
    /// return one entry per address; a condition matches if any entry does.
    public func values(for field: String) -> [String] {
        let f = field.trimmingCharacters(in: .whitespaces)
        switch f {
        case "kind": return [kind.rawValue]
        case "sourceApp": return source.map { [$0.bundleID] } ?? []
        case "sourceApp.name": return source.map { [$0.name] } ?? []
        case "to": return request.to.map(\.address)
        case "to.domain": return request.to.map(\.domain)
        case "cc": return request.cc.map(\.address)
        case "cc.domain": return request.cc.map(\.domain)
        case "bcc": return request.bcc.map(\.address)
        case "bcc.domain": return request.bcc.map(\.domain)
        case "recipient": return request.allRecipients.map(\.address)
        case "recipient.domain": return request.allRecipients.map(\.domain)
        case "subject": return request.subject.map { [$0] } ?? []
        case "body": return request.body.map { [$0] } ?? []
        case "original.from": return original?.from.map { [$0.address] } ?? []
        case "original.from.domain": return original?.from.map { [$0.domain] } ?? []
        case "original.deliveredTo": return original?.deliveredTo.map { [$0] } ?? []
        case "original.deliveredTo.domain": return original?.deliveredTo.map { [EmailAddress(address: $0).domain] } ?? []
        case "original.listId": return original?.listID.map { [$0] } ?? []
        case "original.messageId": return original?.messageID.map { [$0] } ?? []
        default:
            if f.lowercased().hasPrefix("original.header.") {
                let name = String(f.dropFirst("original.header.".count))
                return original?.header(name).map { [$0] } ?? []
            }
            return []
        }
    }
}
