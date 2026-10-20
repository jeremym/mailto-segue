import Foundation

/// One mailbox: the address plus an optional display name.
/// Accepts `pat@acme.com`, `Pat Smith <pat@acme.com>` and `<pat@acme.com>`.
public struct EmailAddress: Hashable, Codable, Sendable, CustomStringConvertible {
    public var address: String
    public var name: String?

    public init(address: String, name: String? = nil) {
        self.address = address.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        self.name = trimmed.isEmpty ? nil : trimmed
    }

    /// Parses one mailbox string. Returns nil for an empty string.
    public init?(parsing text: String) {
        let s = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return nil }
        if let open = s.lastIndex(of: "<"), let close = s[open...].firstIndex(of: ">") {
            let addr = String(s[s.index(after: open)..<close])
            var name = String(s[..<open]).trimmingCharacters(in: .whitespaces)
            if name.hasPrefix("\""), name.hasSuffix("\""), name.count >= 2 {
                name = String(name.dropFirst().dropLast())
            }
            self.init(address: addr, name: name)
        } else {
            self.init(address: s, name: nil)
        }
    }

    /// Splits a comma-separated list, respecting quotes and angle brackets.
    public static func list(parsing text: String) -> [EmailAddress] {
        var out: [EmailAddress] = []
        var current = ""
        var inQuotes = false
        var inAngle = false
        for ch in text {
            switch ch {
            case "\"": inQuotes.toggle(); current.append(ch)
            case "<" where !inQuotes: inAngle = true; current.append(ch)
            case ">" where !inQuotes: inAngle = false; current.append(ch)
            case "," where !inQuotes && !inAngle, ";" where !inQuotes && !inAngle:
                if let a = EmailAddress(parsing: current) { out.append(a) }
                current = ""
            default: current.append(ch)
            }
        }
        if let a = EmailAddress(parsing: current) { out.append(a) }
        return out
    }

    /// The part after the last `@`, lowercased. Empty if there is no `@`.
    public var domain: String {
        guard let at = address.lastIndex(of: "@") else { return "" }
        return address[address.index(after: at)...].lowercased()
    }

    /// The lowercased address, for comparisons.
    public var normalized: String { address.lowercased() }

    /// `Pat Smith <pat@acme.com>` or just `pat@acme.com`.
    public var description: String {
        guard let name, !name.isEmpty else { return address }
        let needsQuotes = name.contains(where: { ",;<>@\"()".contains($0) })
        return needsQuotes ? "\"\(name)\" <\(address)>" : "\(name) <\(address)>"
    }

    /// True when `domain` equals `candidate` or is a subdomain of it.
    public func isIn(domain candidate: String) -> Bool {
        let c = candidate.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
        let d = domain
        return d == c || d.hasSuffix("." + c)
    }
}
