import Foundation

/// Parses `mailto:` links per RFC 6068, leniently.
///
/// - Addresses in the path are comma-separated; `to=` adds more.
/// - Header names are case-insensitive; repeated `to`/`cc`/`bcc` merge.
/// - Values are percent-decoded once. `+` stays a plus unless `plusAsSpace`.
/// - `#` is treated literally (people write "Issue #1" in subjects), not as a fragment.
/// - The body keeps its newlines, normalized to `\n`.
/// - Bad input never throws: whatever can't be decoded is kept raw.
public enum MailtoParser {
    public struct Options: Sendable {
        public var plusAsSpace = false
        public init(plusAsSpace: Bool = false) { self.plusAsSpace = plusAsSpace }
    }

    public static func isMailto(_ text: String) -> Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().hasPrefix("mailto:")
    }

    public static func parse(_ text: String, options: Options = Options()) -> ComposeRequest {
        var s = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.lowercased().hasPrefix("mailto:") {
            s = String(s.dropFirst("mailto:".count))
        }
        // RFC 6068 has no authority part, but "mailto://a@b" shows up in the wild.
        while s.hasPrefix("/") { s.removeFirst() }

        var request = ComposeRequest()
        let path: Substring
        let query: Substring?
        if let q = s.firstIndex(of: "?") {
            path = s[..<q]
            query = s[s.index(after: q)...]
        } else {
            path = s[...]
            query = nil
        }

        if !path.isEmpty {
            request.to += EmailAddress.list(parsing: PercentEncoding.decode(String(path), plusAsSpace: options.plusAsSpace))
        }

        guard let query, !query.isEmpty else { return request }
        for pair in query.split(separator: "&", omittingEmptySubsequences: true) {
            let name: String
            let rawValue: String
            if let eq = pair.firstIndex(of: "=") {
                name = String(pair[..<eq])
                rawValue = String(pair[pair.index(after: eq)...])
            } else {
                name = String(pair)
                rawValue = ""
            }
            let key = PercentEncoding.decode(name).lowercased()
            // The body is the one header whose value may legitimately hold "+".
            let value = PercentEncoding.decode(rawValue, plusAsSpace: options.plusAsSpace)
            switch key {
            case "to": request.to += EmailAddress.list(parsing: value)
            case "cc": request.cc += EmailAddress.list(parsing: value)
            case "bcc": request.bcc += EmailAddress.list(parsing: value)
            case "subject":
                let flat = value.replacingOccurrences(of: "\r\n", with: " ").replacingOccurrences(of: "\n", with: " ")
                request.subject = (request.subject.map { $0 + " " } ?? "") + flat
            case "body":
                let normalized = value.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
                request.body = (request.body.map { $0 + "\n" } ?? "") + normalized
            case "":
                continue
            default:
                request.extraHeaders.append(.init(name: PercentEncoding.decode(name), value: value))
            }
        }
        return request
    }
}
