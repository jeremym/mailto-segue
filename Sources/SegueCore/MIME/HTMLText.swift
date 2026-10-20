import Foundation

/// A small HTML → text converter for quoting and previews. Not a renderer:
/// it drops scripts and styles, turns block tags into newlines, strips the
/// rest and decodes entities.
public enum HTMLText {
    public static func plainText(_ html: String) -> String {
        var s = html
        s = remove(tag: "script", from: s)
        s = remove(tag: "style", from: s)
        s = remove(tag: "head", from: s)
        s = s.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\n", with: " ")
        let blocks = ["</p>", "</div>", "</li>", "</tr>", "</h1>", "</h2>", "</h3>", "</h4>", "</blockquote>", "</pre>", "</table>"]
        for b in blocks { s = s.replacingOccurrences(of: b, with: "\n", options: .caseInsensitive) }
        s = s.replacingOccurrences(of: #"<br\s*/?>"#, with: "\n", options: [.regularExpression, .caseInsensitive])
        s = s.replacingOccurrences(of: #"<li[^>]*>"#, with: "• ", options: [.regularExpression, .caseInsensitive])
        s = s.replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
        s = decodeEntities(s)
        // Collapse runs of spaces, keep line structure, trim each line.
        let lines = s.components(separatedBy: "\n").map {
            $0.replacingOccurrences(of: #"[ \t\u{00A0}]+"#, with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespaces)
        }
        var out: [String] = []
        var blank = 0
        for line in lines {
            if line.isEmpty { blank += 1; if blank <= 1 { out.append("") } } else { blank = 0; out.append(line) }
        }
        return out.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func remove(tag: String, from s: String) -> String {
        s.replacingOccurrences(of: "<\(tag)[^>]*>[\\s\\S]*?</\(tag)>", with: "", options: [.regularExpression, .caseInsensitive])
    }

    static let named: [String: String] = [
        "amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'", "nbsp": "\u{00A0}", "copy": "©", "reg": "®",
        "hellip": "…", "mdash": "—", "ndash": "–", "lsquo": "‘", "rsquo": "’", "ldquo": "“", "rdquo": "”", "trade": "™", "euro": "€",
    ]

    public static func decodeEntities(_ s: String) -> String {
        guard s.contains("&") else { return s }
        guard let regex = try? NSRegularExpression(pattern: "&(#x[0-9a-fA-F]+|#[0-9]+|[a-zA-Z]+);") else { return s }
        let ns = s as NSString
        var out = ""
        var cursor = 0
        for m in regex.matches(in: s, range: NSRange(location: 0, length: ns.length)) {
            out += ns.substring(with: NSRange(location: cursor, length: m.range.location - cursor))
            let body = ns.substring(with: m.range(at: 1))
            var replacement: String? = nil
            if body.hasPrefix("#x") || body.hasPrefix("#X") {
                replacement = UInt32(body.dropFirst(2), radix: 16).flatMap(UnicodeScalar.init).map { String(Character($0)) }
            } else if body.hasPrefix("#") {
                replacement = UInt32(body.dropFirst()).flatMap(UnicodeScalar.init).map { String(Character($0)) }
            } else {
                replacement = named[body.lowercased()]
            }
            out += replacement ?? ns.substring(with: m.range)
            cursor = m.range.location + m.range.length
        }
        out += ns.substring(from: cursor)
        return out
    }
}
