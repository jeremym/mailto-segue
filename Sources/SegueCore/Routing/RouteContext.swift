import Foundation

/// What a hand-off looks like to the router and the rules.
public struct RouteContext: Equatable, Sendable {
    public enum Kind: String, Codable, Sendable { case mailto, reply, replyAll, forward, cli }

    public var kind: Kind
    public var request: ComposeRequest
    public var source: SourceApp?
    /// The original message, for replies and forwards from an `.eml`.
    public var original: OriginalMessage?
    /// The user held the "force chooser" modifier when the link arrived.
    public var forceChooser: Bool = false

    public init(kind: Kind, request: ComposeRequest, source: SourceApp? = nil,
                original: OriginalMessage? = nil, forceChooser: Bool = false) {
        self.kind = kind
        self.request = request
        self.source = source
        self.original = original
        self.forceChooser = forceChooser
    }
}

/// The app that sent the link. `guessed` means we couldn't read the sender
/// from the Apple Event and used the frontmost app instead.
public struct SourceApp: Equatable, Codable, Sendable {
    public var bundleID: String
    public var name: String
    public var pid: Int32?
    public var guessed: Bool

    public init(bundleID: String, name: String, pid: Int32? = nil, guessed: Bool = false) {
        self.bundleID = bundleID
        self.name = name
        self.pid = pid
        self.guessed = guessed
    }
}

/// The parts of an opened `.eml` that rules can see.
public struct OriginalMessage: Equatable, Codable, Sendable {
    public var from: EmailAddress?
    public var deliveredTo: String?
    public var listID: String?
    public var messageID: String?
    public var headers: [ComposeRequest.Header] = []

    public init(from: EmailAddress? = nil, deliveredTo: String? = nil, listID: String? = nil,
                messageID: String? = nil, headers: [ComposeRequest.Header] = []) {
        self.from = from
        self.deliveredTo = deliveredTo
        self.listID = listID
        self.messageID = messageID
        self.headers = headers
    }

    public func header(_ name: String) -> String? {
        headers.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }?.value
    }
}
