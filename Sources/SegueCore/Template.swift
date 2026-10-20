import Foundation

/// Expands `{token}` placeholders in a custom URL template. Every value is
/// percent-encoded; `{mailto}` is the whole strict mailto: string, encoded
/// once more (the form handler-style URLs like `?url=` expect).
///
/// Tokens: `{to}` `{cc}` `{bcc}` `{subject}` `{body}` `{mailto}` `{domain}`
/// `{to.raw}` and friends give the unencoded value for non-URL templates.
public enum Template {
    public static let tokens = ["to", "cc", "bcc", "subject", "body", "mailto", "domain"]

    public static func expand(_ template: String, with request: ComposeRequest) -> String {
        var out = template
        for (token, value) in values(for: request) {
            out = out.replacingOccurrences(of: "{\(token)}", with: PercentEncoding.encode(value, newline: .lf))
            out = out.replacingOccurrences(of: "{\(token).raw}", with: value)
        }
        return out
    }

    static func values(for r: ComposeRequest) -> [(String, String)] {
        [
            ("to", r.to.map(\.address).joined(separator: ",")),
            ("cc", r.cc.map(\.address).joined(separator: ",")),
            ("bcc", r.bcc.map(\.address).joined(separator: ",")),
            ("subject", r.subject ?? ""),
            ("body", r.body ?? ""),
            ("mailto", r.mailtoString),
            ("domain", r.to.first?.domain ?? r.cc.first?.domain ?? ""),
        ]
    }
}
