import Foundation

/// Builds the ComposeRequest for Reply, Reply All and Forward. Segue never
/// edits text, so this is the only place that writes any: the attribution
/// line, the `> ` quoting and the forwarded header block.
public enum ReplyBuilder {
    public enum Kind: String, Codable, CaseIterable, Sendable { case reply, replyAll, forward }

    public static func build(_ kind: Kind, from message: EmailMessage, myAddresses: Set<String>,
                             now: Date = Date()) -> ComposeRequest {
        var r = ComposeRequest()
        let mine = Set(myAddresses.map { $0.lowercased() })
        let sender = message.replyTo.first ?? message.from.first
        switch kind {
        case .reply:
            if let sender { r.to = [sender] }
            r.subject = prefixed("Re:", message.subject)
        case .replyAll:
            var to: [EmailAddress] = []
            if let sender { to.append(sender) }
            for a in message.to where !mine.contains(a.normalized) && !to.contains(where: { $0.normalized == a.normalized }) {
                to.append(a)
            }
            r.to = to
            r.cc = message.cc.filter { c in !mine.contains(c.normalized) && !to.contains(where: { $0.normalized == c.normalized }) }
            r.subject = prefixed("Re:", message.subject)
        case .forward:
            r.subject = prefixed("Fwd:", message.subject)
        }

        let original = message.bestText
        switch kind {
        case .reply, .replyAll:
            r.body = "\n\n" + attribution(message) + "\n" + quote(original)
            if let id = message.messageID {
                r.extraHeaders.append(.init(name: "In-Reply-To", value: id))
                let refs = (message.references + [id]).joined(separator: " ")
                r.extraHeaders.append(.init(name: "References", value: refs))
            }
        case .forward:
            r.body = "\n\n" + forwardedBlock(message) + "\n" + original
        }
        return r
    }

    /// "On Oct 18, 2026, at 4:12 PM, Pat <pat@acme.com> wrote:"
    public static func attribution(_ m: EmailMessage) -> String {
        let who = m.from.first?.description ?? "someone"
        if let d = m.date {
            let f = DateFormatter()
            f.locale = .current
            f.dateStyle = .medium
            f.timeStyle = .short
            return "On \(f.string(from: d)), \(who) wrote:"
        }
        if let t = m.dateText, !t.isEmpty { return "On \(t), \(who) wrote:" }
        return "\(who) wrote:"
    }

    public static func quote(_ text: String) -> String {
        text.split(separator: "\n", omittingEmptySubsequences: false).map { "> " + $0 }.joined(separator: "\n")
    }

    public static func forwardedBlock(_ m: EmailMessage) -> String {
        var lines = ["---------- Forwarded message ----------"]
        if let f = m.from.first { lines.append("From: \(f.description)") }
        if let d = m.dateText { lines.append("Date: \(d)") }
        lines.append("Subject: \(m.subject)")
        if !m.to.isEmpty { lines.append("To: " + m.to.map(\.description).joined(separator: ", ")) }
        if !m.cc.isEmpty { lines.append("Cc: " + m.cc.map(\.description).joined(separator: ", ")) }
        if !m.attachments.isEmpty {
            lines.append("Attachments (not included): " + m.attachments.map(\.filename).joined(separator: ", "))
        }
        return lines.joined(separator: "\n")
    }

    /// Adds `Re:`/`Fwd:` once, case-insensitively, also recognising `RE:`, `Fw:`, `AW:`, `WG:`.
    static func prefixed(_ prefix: String, _ subject: String) -> String {
        let s = subject.trimmingCharacters(in: .whitespaces)
        let lower = s.lowercased()
        let existing = prefix == "Re:" ? ["re:", "aw:", "sv:"] : ["fwd:", "fw:", "wg:", "tr:"]
        if existing.contains(where: { lower.hasPrefix($0) }) { return s }
        return s.isEmpty ? prefix.trimmingCharacters(in: CharacterSet(charactersIn: ":")) : "\(prefix) \(s)"
    }
}
