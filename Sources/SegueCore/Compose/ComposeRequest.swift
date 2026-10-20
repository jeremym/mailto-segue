import Foundation

/// Everything needed to open a draft somewhere. Built from a `mailto:` link,
/// from an `.eml` reply, or from the CLI. Segue never edits it; it only carries
/// it to a destination.
public struct ComposeRequest: Equatable, Codable, Sendable {
    public var to: [EmailAddress] = []
    public var cc: [EmailAddress] = []
    public var bcc: [EmailAddress] = []
    public var subject: String?
    /// Lines separated by `\n`. Encoders choose the line ending they need.
    public var body: String?
    /// Headers other than to/cc/bcc/subject/body (e.g. `In-Reply-To`), in the
    /// order they arrived. Names keep their original spelling.
    public var extraHeaders: [Header] = []

    public struct Header: Equatable, Codable, Sendable {
        public var name: String
        public var value: String
        public init(name: String, value: String) { self.name = name; self.value = value }
    }

    public init(to: [EmailAddress] = [], cc: [EmailAddress] = [], bcc: [EmailAddress] = [],
                subject: String? = nil, body: String? = nil, extraHeaders: [Header] = []) {
        self.to = to
        self.cc = cc
        self.bcc = bcc
        self.subject = subject
        self.body = body
        self.extraHeaders = extraHeaders
    }

    public var isEmpty: Bool {
        to.isEmpty && cc.isEmpty && bcc.isEmpty && (subject ?? "").isEmpty
            && (body ?? "").isEmpty && extraHeaders.isEmpty
    }

    /// Every recipient, in to/cc/bcc order.
    public var allRecipients: [EmailAddress] { to + cc + bcc }

    /// Case-insensitive lookup in `extraHeaders`.
    public func header(_ name: String) -> String? {
        extraHeaders.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }?.value
    }

    /// The first recipient's address, for display. Empty if there is none.
    public var primaryRecipient: String { to.first?.address ?? cc.first?.address ?? bcc.first?.address ?? "" }

    /// A strictly encoded `mailto:` string (RFC 6068) that any mail app accepts.
    /// Body newlines become `%0D%0A`.
    public var mailtoString: String {
        var s = "mailto:" + to.map { PercentEncoding.encodeAddress($0.description) }.joined(separator: ",")
        var query: [String] = []
        if !cc.isEmpty { query.append("cc=" + cc.map { PercentEncoding.encodeAddress($0.description) }.joined(separator: ",")) }
        if !bcc.isEmpty { query.append("bcc=" + bcc.map { PercentEncoding.encodeAddress($0.description) }.joined(separator: ",")) }
        if let subject, !subject.isEmpty { query.append("subject=" + PercentEncoding.encode(subject)) }
        if let body, !body.isEmpty { query.append("body=" + PercentEncoding.encode(body, newline: .crlf)) }
        for h in extraHeaders { query.append(PercentEncoding.encode(h.name) + "=" + PercentEncoding.encode(h.value)) }
        if !query.isEmpty { s += "?" + query.joined(separator: "&") }
        return s
    }
}
