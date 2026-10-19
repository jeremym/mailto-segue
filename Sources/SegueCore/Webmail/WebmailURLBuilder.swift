import Foundation

/// Builds the compose URL for a webmail provider. URL formats were researched
/// on 2026-10-19 (see the vault's 03-Research) and are verified by hand in M9.
public enum WebmailURLBuilder {
    /// Past this many characters some browsers and services drop the request.
    public static let defaultMaxLength = 2000

    public struct Built: Equatable, Sendable {
        public var url: URL
        /// Set when the body was too long for the URL: the full text that
        /// should go to the clipboard so the user can paste it.
        public var overflowBody: String?
    }

    public enum BuildError: Error, Equatable {
        case noComposeURL(WebmailProvider)
        case invalidURL
    }

    public static func build(_ request: ComposeRequest, provider: WebmailProvider,
                             account: WebmailAccount? = nil,
                             maxLength: Int = defaultMaxLength) throws -> Built {
        guard provider.supportsDirectCompose else { throw BuildError.noComposeURL(provider) }
        let full = try url(for: request, provider: provider, account: account)
        if full.absoluteString.count <= maxLength || (request.body ?? "").isEmpty {
            return Built(url: full, overflowBody: nil)
        }
        // Too long: keep everything but the body, hint at the clipboard.
        var short = request
        short.body = "(Quoted text is on the clipboard. Paste it here.)"
        let shortURL = try url(for: request.withBody(short.body), provider: provider, account: account)
        return Built(url: shortURL, overflowBody: request.body)
    }

    public static func url(for request: ComposeRequest, provider: WebmailProvider,
                           account: WebmailAccount?) throws -> URL {
        let s: String
        switch provider {
        case .gmail: s = gmail(request, account: account)
        case .outlook: s = fields("https://outlook.live.com/mail/0/deeplink/compose", request, subjectKey: "subject")
        case .office365: s = fields("https://outlook.office.com/mail/deeplink/compose", request, subjectKey: "subject")
        case .yahoo: s = fields("https://compose.mail.yahoo.com/", request, subjectKey: "subject")
        case .proton:
            let base = account?.index.map { "https://mail.proton.me/u/\($0)/inbox" } ?? "https://mail.proton.me/inbox"
            s = base + "#mailto=" + PercentEncoding.encode(request.mailtoString)
        case .fastmail:
            s = "https://www.fastmail.com/action/compose/?mailto=" + PercentEncoding.encode(request.mailtoString)
        case .zoho:
            s = "https://mail.zoho.com/mail/compose.do?extsrc=mailto&mode=compose&tp=zb&ct=" + PercentEncoding.encode(request.mailtoString)
        case .icloud, .hey:
            throw BuildError.noComposeURL(provider)
        }
        guard let url = URL(string: s) else { throw BuildError.invalidURL }
        return url
    }

    // MARK: - Providers

    private static func gmail(_ r: ComposeRequest, account: WebmailAccount?) -> String {
        var base = "https://mail.google.com/mail/"
        if let index = account?.index { base += "u/\(index)/" }
        var q: [String] = []
        if let email = account?.email, !email.isEmpty { q.append("authuser=" + PercentEncoding.encodeAddress(email)) }
        q.append("view=cm")
        q.append("fs=1")
        q += recipientParams(r)
        if let s = r.subject, !s.isEmpty { q.append("su=" + PercentEncoding.encode(s)) }
        if let b = r.body, !b.isEmpty { q.append("body=" + PercentEncoding.encode(b, newline: .lf)) }
        return base + "?" + q.joined(separator: "&")
    }

    /// Providers that take plain `to/cc/bcc/subject/body` query fields.
    private static func fields(_ base: String, _ r: ComposeRequest, subjectKey: String) -> String {
        var q = recipientParams(r)
        if let s = r.subject, !s.isEmpty { q.append("\(subjectKey)=" + PercentEncoding.encode(s)) }
        if let b = r.body, !b.isEmpty { q.append("body=" + PercentEncoding.encode(b, newline: .lf)) }
        return base + "?" + q.joined(separator: "&")
    }

    private static func recipientParams(_ r: ComposeRequest) -> [String] {
        var q: [String] = []
        if !r.to.isEmpty { q.append("to=" + addresses(r.to)) }
        if !r.cc.isEmpty { q.append("cc=" + addresses(r.cc)) }
        if !r.bcc.isEmpty { q.append("bcc=" + addresses(r.bcc)) }
        return q
    }

    /// Webmail gets bare addresses (display names confuse some services),
    /// comma-separated, with `@` left readable.
    private static func addresses(_ list: [EmailAddress]) -> String {
        list.map { PercentEncoding.encodeAddress($0.address) }.joined(separator: ",")
    }
}

extension ComposeRequest {
    public func withBody(_ body: String?) -> ComposeRequest {
        var copy = self
        copy.body = body
        return copy
    }

    /// Gmail can open the real thread for a message it holds, which makes a
    /// reply threaded and keeps the attachments. `messageID` is the raw
    /// `Message-ID` header value, with or without angle brackets.
    public static func gmailThreadURL(messageID: String, account: WebmailAccount?) -> URL? {
        let id = messageID.trimmingCharacters(in: CharacterSet(charactersIn: "<> \n"))
        guard !id.isEmpty else { return nil }
        var base = "https://mail.google.com/mail/"
        if let index = account?.index { base += "u/\(index)/" }
        var s = base
        if let email = account?.email, !email.isEmpty { s += "?authuser=" + PercentEncoding.encodeAddress(email) }
        s += "#search/" + PercentEncoding.encode("rfc822msgid:" + id)
        return URL(string: s)
    }
}
