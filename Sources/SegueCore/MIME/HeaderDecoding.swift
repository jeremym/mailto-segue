import Foundation

/// RFC 2047 encoded words, RFC 2231 parameters, and header unfolding.
public enum HeaderDecoding {
    /// Joins continuation lines (CRLF followed by whitespace).
    public static func unfold(_ raw: String) -> String {
        raw.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\n[ \t]+", with: " ", options: .regularExpression)
    }

    /// Decodes `=?charset?B|Q?text?=` words. Whitespace between two encoded
    /// words is dropped, as the RFC requires.
    public static func decodeEncodedWords(_ text: String) -> String {
        guard text.contains("=?") else { return text }
        let pattern = #"=\?([^?]+)\?([bBqQ])\?([^?]*)\?="#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        let ns = text as NSString
        var out = ""
        var cursor = 0
        var lastWasEncoded = false
        var pendingSpace = ""
        for m in regex.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            let between = ns.substring(with: NSRange(location: cursor, length: m.range.location - cursor))
            if lastWasEncoded, between.trimmingCharacters(in: .whitespaces).isEmpty {
                pendingSpace = ""
            } else {
                out += pendingSpace + between
                pendingSpace = ""
            }
            let charset = ns.substring(with: m.range(at: 1))
            let encoding = ns.substring(with: m.range(at: 2)).uppercased()
            let payload = ns.substring(with: m.range(at: 3))
            let bytes: Data?
            if encoding == "B" {
                bytes = Data(base64Encoded: payload, options: .ignoreUnknownCharacters)
            } else {
                bytes = TransferDecoding.quotedPrintable(payload.replacingOccurrences(of: "_", with: " "), header: true)
            }
            if let bytes, let decoded = Charsets.decode(bytes, charset: charset) {
                out += decoded
            } else {
                out += ns.substring(with: m.range)
            }
            cursor = m.range.location + m.range.length
            lastWasEncoded = true
        }
        out += ns.substring(from: cursor)
        return out
    }

    /// Parses `type/subtype; name="x"; charset=utf-8` and RFC 2231 pieces
    /// (`name*0*=utf-8''...`, `name*1*=...`). Keys are lowercased.
    public static func parseParameterized(_ value: String) -> (main: String, params: [String: String]) {
        var parts: [String] = []
        var current = ""
        var inQuotes = false
        for ch in value {
            if ch == "\"" { inQuotes.toggle(); current.append(ch) }
            else if ch == ";" && !inQuotes { parts.append(current); current = "" }
            else { current.append(ch) }
        }
        parts.append(current)
        let main = parts.first?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        var params: [String: String] = [:]
        var continuations: [String: [(Int, String, Bool)]] = [:]
        for p in parts.dropFirst() {
            guard let eq = p.firstIndex(of: "=") else { continue }
            var key = p[..<eq].trimmingCharacters(in: .whitespaces).lowercased()
            var val = p[p.index(after: eq)...].trimmingCharacters(in: .whitespacesAndNewlines)
            if val.hasPrefix("\""), val.hasSuffix("\""), val.count >= 2 { val = String(val.dropFirst().dropLast()) }
            var extended = false
            if key.hasSuffix("*") { key.removeLast(); extended = true }
            if let star = key.firstIndex(of: "*"), let index = Int(key[key.index(after: star)...]) {
                let base = String(key[..<star])
                continuations[base, default: []].append((index, val, extended))
            } else if extended {
                params[key] = decodeRFC2231(val)
            } else {
                params[key] = decodeEncodedWords(val)
            }
        }
        for (key, pieces) in continuations {
            let joined = pieces.sorted { $0.0 < $1.0 }
            let first = joined.first
            let raw = joined.map { $0.1 }.joined()
            params[key] = (first?.2 ?? false) ? decodeRFC2231(raw) : raw
        }
        return (main, params)
    }

    /// `utf-8'en'caf%C3%A9` → `café`.
    static func decodeRFC2231(_ value: String) -> String {
        let pieces = value.split(separator: "'", maxSplits: 2, omittingEmptySubsequences: false)
        guard pieces.count == 3 else { return PercentEncoding.decode(value) }
        let charset = String(pieces[0])
        let encoded = String(pieces[2])
        var bytes: [UInt8] = []
        let u = Array(encoded.utf8)
        var i = 0
        while i < u.count {
            if u[i] == UInt8(ascii: "%"), i + 2 < u.count, let v = UInt8(String(decoding: u[(i + 1)...(i + 2)], as: UTF8.self), radix: 16) {
                bytes.append(v); i += 3
            } else { bytes.append(u[i]); i += 1 }
        }
        return Charsets.decode(Data(bytes), charset: charset) ?? encoded
    }
}

public enum Charsets {
    /// Decodes bytes in an IANA charset. Unknown charsets fall back to UTF-8,
    /// then Latin-1 (which never fails).
    public static func decode(_ data: Data, charset: String?) -> String? {
        let name = (charset ?? "utf-8").trimmingCharacters(in: .whitespaces).lowercased()
        if let enc = encoding(forIANA: name), let s = String(data: data, encoding: enc) { return s }
        if let s = String(data: data, encoding: .utf8) { return s }
        return String(data: data, encoding: .isoLatin1)
    }

    public static func encoding(forIANA name: String) -> String.Encoding? {
        switch name {
        case "utf-8", "utf8": return .utf8
        case "us-ascii", "ascii": return .ascii
        case "iso-8859-1", "latin1", "latin-1", "iso_8859-1": return .isoLatin1
        case "windows-1252", "cp1252": return .windowsCP1252
        case "utf-16": return .utf16
        default:
            let cf = CFStringConvertIANACharSetNameToEncoding(name as CFString)
            guard cf != kCFStringEncodingInvalidId else { return nil }
            return String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(cf))
        }
    }
}

public enum TransferDecoding {
    public static func quotedPrintable(_ text: String, header: Bool = false) -> Data {
        var out = Data()
        let u = Array(text.utf8)
        var i = 0
        while i < u.count {
            let b = u[i]
            if b == UInt8(ascii: "=") {
                if i + 2 < u.count,
                   let v = UInt8(String(decoding: u[(i + 1)...(i + 2)], as: UTF8.self), radix: 16) {
                    out.append(v); i += 3; continue
                }
                // Soft line break: "=" followed by CRLF or LF.
                if i + 1 < u.count, u[i + 1] == UInt8(ascii: "\r") { i += (i + 2 < u.count && u[i + 2] == UInt8(ascii: "\n")) ? 3 : 2; continue }
                if i + 1 < u.count, u[i + 1] == UInt8(ascii: "\n") { i += 2; continue }
                if i + 1 == u.count { i += 1; continue }
                out.append(b); i += 1
            } else {
                out.append(b); i += 1
            }
        }
        return out
    }

    public static func base64(_ text: String) -> Data {
        Data(base64Encoded: text, options: .ignoreUnknownCharacters) ?? Data()
    }
}
