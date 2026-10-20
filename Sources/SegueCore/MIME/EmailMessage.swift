import Foundation

/// A parsed `.eml` / `.emlx`: enough to show it and build a reply.
public struct EmailMessage: Equatable, Sendable {
    public struct Header: Equatable, Sendable {
        public var name: String
        /// Unfolded and RFC 2047-decoded.
        public var value: String
        public init(name: String, value: String) { self.name = name; self.value = value }
    }

    public struct Attachment: Equatable, Sendable {
        public var filename: String
        public var mimeType: String
        public var size: Int
        public var contentID: String?
        public var isInline: Bool
        public var data: Data
        public init(filename: String, mimeType: String, size: Int, contentID: String? = nil, isInline: Bool = false, data: Data) {
            self.filename = filename
            self.mimeType = mimeType
            self.size = size
            self.contentID = contentID
            self.isInline = isInline
            self.data = data
        }
    }

    public var headers: [Header] = []
    public var from: [EmailAddress] = []
    public var to: [EmailAddress] = []
    public var cc: [EmailAddress] = []
    public var replyTo: [EmailAddress] = []
    public var subject: String = ""
    public var date: Date?
    public var dateText: String?
    public var messageID: String?
    public var inReplyTo: String?
    public var references: [String] = []
    public var listID: String?
    /// `Delivered-To` / `X-Original-To`, else nil (the reply builder falls back to To/Cc).
    public var deliveredTo: String?
    public var textBody: String?
    public var htmlBody: String?
    public var attachments: [Attachment] = []
    /// Set when the parser hit something it couldn't make sense of; the
    /// reader then offers the raw source.
    public var parseWarnings: [String] = []

    public init() {}

    public func header(_ name: String) -> String? {
        headers.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }?.value
    }

    public func allHeaders(_ name: String) -> [String] {
        headers.filter { $0.name.caseInsensitiveCompare(name) == .orderedSame }.map(\.value)
    }

    /// Plain text for quoting and display: the text part, else the HTML stripped.
    public var bestText: String {
        if let t = textBody, !t.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return t }
        if let h = htmlBody { return HTMLText.plainText(h) }
        return ""
    }

    /// What rules and the reply builder see.
    public var original: OriginalMessage {
        OriginalMessage(from: from.first, deliveredTo: resolvedDeliveredTo(myAddresses: []), listID: listID,
                        messageID: messageID, headers: headers.map { .init(name: $0.name, value: $0.value) })
    }

    /// The address this message reached. `Delivered-To` wins; otherwise the
    /// first To/Cc address that is one of mine; otherwise the first To.
    public func resolvedDeliveredTo(myAddresses: Set<String>) -> String? {
        if let d = deliveredTo, !d.isEmpty { return d.lowercased() }
        let mine = myAddresses.map { $0.lowercased() }
        for a in to + cc where mine.contains(a.normalized) { return a.normalized }
        return to.first?.normalized
    }
}
