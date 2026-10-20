import Foundation

/// Strict RFC 3986 percent-encoding. Only unreserved characters pass through,
/// so `&`, `=`, `+`, `#` and `?` inside values can never break a URL. (The
/// atalayhuryasar/mailto app uses `.urlQueryAllowed`, which is why "A & B"
/// breaks there.)
public enum PercentEncoding {
    public enum Newline: Sendable { case lf, crlf }

    private static let unreserved: Set<UInt8> = {
        var s = Set<UInt8>()
        for c in UInt8(ascii: "A")...UInt8(ascii: "Z") { s.insert(c) }
        for c in UInt8(ascii: "a")...UInt8(ascii: "z") { s.insert(c) }
        for c in UInt8(ascii: "0")...UInt8(ascii: "9") { s.insert(c) }
        for c in "-._~".utf8 { s.insert(c) }
        return s
    }()

    /// Encodes `value`. `\n` (and `\r\n`) in the text become the chosen line
    /// ending, percent-encoded.
    public static func encode(_ value: String, newline: Newline = .lf, extraAllowed: Set<UInt8> = []) -> String {
        let normalized = value.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        var out = ""
        out.reserveCapacity(normalized.utf8.count * 2)
        for byte in normalized.utf8 {
            if byte == UInt8(ascii: "\n") {
                out += newline == .crlf ? "%0D%0A" : "%0A"
            } else if unreserved.contains(byte) || extraAllowed.contains(byte) {
                out.append(Character(UnicodeScalar(byte)))
            } else {
                out += String(format: "%%%02X", byte)
            }
        }
        return out
    }

    /// Like `encode`, but keeps `@`, which RFC 6068 allows in addresses and
    /// which keeps `to=` readable.
    public static func encodeAddress(_ value: String) -> String {
        encode(value, extraAllowed: [UInt8(ascii: "@")])
    }

    /// Decodes `%XX` sequences once. Invalid sequences (`%zz`, a trailing `%`)
    /// are kept as-is instead of failing. Invalid UTF-8 bytes are replaced.
    public static func decode(_ value: String, plusAsSpace: Bool = false) -> String {
        var bytes: [UInt8] = []
        bytes.reserveCapacity(value.utf8.count)
        let u = Array(value.utf8)
        var i = 0
        while i < u.count {
            let b = u[i]
            if b == UInt8(ascii: "%"),
               let hi = hexValue(u[safe: i + 1]), let lo = hexValue(u[safe: i + 2]) {
                bytes.append(hi << 4 | lo)
                i += 3
            } else if plusAsSpace, b == UInt8(ascii: "+") {
                bytes.append(UInt8(ascii: " "))
                i += 1
            } else {
                bytes.append(b)
                i += 1
            }
        }
        return String(decoding: bytes, as: UTF8.self)
    }

    private static func hexValue(_ c: UInt8?) -> UInt8? {
        guard let c else { return nil }
        switch c {
        case UInt8(ascii: "0")...UInt8(ascii: "9"): return c - UInt8(ascii: "0")
        case UInt8(ascii: "a")...UInt8(ascii: "f"): return c - UInt8(ascii: "a") + 10
        case UInt8(ascii: "A")...UInt8(ascii: "F"): return c - UInt8(ascii: "A") + 10
        default: return nil
        }
    }
}

extension Array {
    subscript(safe i: Int) -> Element? { i >= 0 && i < count ? self[i] : nil }
}
