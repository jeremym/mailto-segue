import Foundation

/// RFC 5322 + MIME parser for `.eml` and `.emlx` files. Dependency-free and
/// lenient: whatever it can't understand becomes a warning, never a crash.
public enum MIMEParser {
    public static func parse(_ data: Data) -> EmailMessage {
        var message = EmailMessage()
        let body = stripEmlx(data)
        let (headerBlock, bodyData) = splitHeaders(body)
        message.headers = parseHeaders(headerBlock)
        fillKnownHeaders(&message)

        let contentType = HeaderDecoding.parseParameterized(message.header("Content-Type") ?? "text/plain")
        var context = PartContext(message: message)
        walk(part: bodyData, contentType: contentType, headers: message.headers, depth: 0, context: &context)
        message = context.message
        if message.headers.isEmpty {
            message.parseWarnings.append("No headers found.")
        }
        if (message.textBody ?? "").isEmpty && message.htmlBody == nil && message.attachments.isEmpty {
            message.parseWarnings.append("No readable body found.")
        }
        return message
    }

    public static func parse(fileURL: URL) throws -> EmailMessage {
        parse(try Data(contentsOf: fileURL))
    }

    // MARK: - Containers

    /// Apple Mail's `.emlx`: a decimal byte count on the first line, the
    /// message, then an XML plist. Only the middle part is the message.
    static func stripEmlx(_ data: Data) -> Data {
        guard let newline = data.firstIndex(of: UInt8(ascii: "\n")), newline < 20 else { return data }
        let firstLine = String(decoding: data[data.startIndex..<newline], as: UTF8.self).trimmingCharacters(in: .whitespaces)
        guard let count = Int(firstLine), count > 0 else { return data }
        let start = data.index(after: newline)
        let end = min(data.endIndex, start + count)
        return data.subdata(in: start..<end)
    }

    static func splitHeaders(_ data: Data) -> (String, Data) {
        let separators: [[UInt8]] = [[13, 10, 13, 10], [10, 10]]
        var cut: (Range<Data.Index>)? = nil
        for sep in separators {
            if let r = data.range(of: Data(sep)) { if cut == nil || r.lowerBound < cut!.lowerBound { cut = r } }
        }
        guard let r = cut else {
            // Headers only, or no blank line at all: treat everything as headers.
            return (latin1(data), Data())
        }
        return (latin1(data.subdata(in: data.startIndex..<r.lowerBound)), data.subdata(in: r.upperBound..<data.endIndex))
    }

    static func latin1(_ data: Data) -> String {
        String(data: data, encoding: .isoLatin1) ?? ""
    }

    static func parseHeaders(_ block: String) -> [EmailMessage.Header] {
        var out: [EmailMessage.Header] = []
        for line in HeaderDecoding.unfold(block).split(separator: "\n", omittingEmptySubsequences: true) {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let name = line[..<colon].trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty, !name.contains(" ") else { continue }
            let rawValue = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            // Header bytes were read as Latin-1; most are ASCII, but raw UTF-8 shows up in the wild.
            let utf8Fixed = String(data: Data(rawValue.utf8.map { $0 }), encoding: .utf8).flatMap { _ in
                String(data: Data(rawValue.unicodeScalars.map { UInt8(truncatingIfNeeded: $0.value) }), encoding: .utf8)
            } ?? rawValue
            out.append(.init(name: name, value: HeaderDecoding.decodeEncodedWords(utf8Fixed)))
        }
        return out
    }

    static func fillKnownHeaders(_ m: inout EmailMessage) {
        m.from = EmailAddress.list(parsing: m.header("From") ?? "")
        m.to = m.allHeaders("To").flatMap { EmailAddress.list(parsing: $0) }
        m.cc = m.allHeaders("Cc").flatMap { EmailAddress.list(parsing: $0) }
        m.replyTo = EmailAddress.list(parsing: m.header("Reply-To") ?? "")
        m.subject = m.header("Subject") ?? ""
        m.dateText = m.header("Date")
        m.date = m.dateText.flatMap(DateParsing.parse)
        m.messageID = m.header("Message-ID")?.trimmingCharacters(in: .whitespaces)
        m.inReplyTo = m.header("In-Reply-To")?.trimmingCharacters(in: .whitespaces)
        m.references = (m.header("References") ?? "").split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
        m.listID = m.header("List-Id") ?? m.header("List-ID")
        if let d = m.header("Delivered-To") ?? m.header("X-Original-To") {
            m.deliveredTo = EmailAddress(parsing: d)?.normalized
        }
    }

    // MARK: - Parts

    struct PartContext {
        var message: EmailMessage
        var sawAlternativeText = false
    }

    static func walk(part data: Data, contentType: (main: String, params: [String: String]),
                     headers: [EmailMessage.Header], depth: Int, context: inout PartContext) {
        guard depth < 20 else { context.message.parseWarnings.append("MIME nesting too deep."); return }
        let type = contentType.main
        let disposition = HeaderDecoding.parseParameterized(headerValue("Content-Disposition", in: headers) ?? "")
        let encoding = (headerValue("Content-Transfer-Encoding", in: headers) ?? "7bit").trimmingCharacters(in: .whitespaces).lowercased()

        if type.hasPrefix("multipart/") {
            guard let boundary = contentType.params["boundary"], !boundary.isEmpty else {
                context.message.parseWarnings.append("multipart without a boundary")
                addText(decodeBytes(data, encoding: encoding), charset: contentType.params["charset"], html: false, context: &context)
                return
            }
            let parts = splitMultipart(data, boundary: boundary)
            if parts.isEmpty { context.message.parseWarnings.append("multipart with no parts") }
            for p in parts {
                let (hBlock, body) = splitHeaders(p)
                let h = parseHeaders(hBlock)
                let ct = HeaderDecoding.parseParameterized(headerValue("Content-Type", in: h) ?? "text/plain")
                walk(part: body, contentType: ct, headers: h, depth: depth + 1, context: &context)
            }
            return
        }

        let bytes = decodeBytes(data, encoding: encoding)
        let filename = disposition.params["filename"] ?? contentType.params["name"]
        let isAttachment = disposition.main == "attachment" || (filename != nil && !type.hasPrefix("text/"))
            || type == "message/rfc822"
        let contentID = headerValue("Content-ID", in: headers)?.trimmingCharacters(in: CharacterSet(charactersIn: "<> "))

        if isAttachment || (!type.hasPrefix("text/") && disposition.main == "inline") || (!type.hasPrefix("text/") && contentID != nil) {
            let name = filename ?? (type == "message/rfc822" ? "message.eml" : "attachment")
            context.message.attachments.append(.init(filename: name, mimeType: type, size: bytes.count, contentID: contentID,
                                                     isInline: disposition.main == "inline" || contentID != nil, data: bytes))
            return
        }

        switch type {
        case "text/plain", "text":
            addText(bytes, charset: contentType.params["charset"], html: false, context: &context)
        case "text/html":
            addText(bytes, charset: contentType.params["charset"], html: true, context: &context)
        default:
            if type.hasPrefix("text/") {
                addText(bytes, charset: contentType.params["charset"], html: false, context: &context)
            } else {
                context.message.attachments.append(.init(filename: filename ?? "attachment", mimeType: type, size: bytes.count,
                                                         contentID: contentID, isInline: false, data: bytes))
            }
        }
    }

    static func addText(_ bytes: Data, charset: String?, html: Bool, context: inout PartContext) {
        guard var text = Charsets.decode(bytes, charset: charset) else { return }
        text = text.replacingOccurrences(of: "\r\n", with: "\n")
        if html {
            if context.message.htmlBody == nil { context.message.htmlBody = text } else { context.message.htmlBody! += "\n" + text }
        } else {
            if context.message.textBody == nil { context.message.textBody = text } else { context.message.textBody! += "\n" + text }
        }
    }

    static func decodeBytes(_ data: Data, encoding: String) -> Data {
        switch encoding {
        case "base64": return TransferDecoding.base64(latin1(data))
        case "quoted-printable": return TransferDecoding.quotedPrintable(latin1(data))
        default: return data
        }
    }

    static func headerValue(_ name: String, in headers: [EmailMessage.Header]) -> String? {
        headers.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }?.value
    }

    /// Splits on `--boundary` lines; stops at `--boundary--`. Tolerates a
    /// missing closing boundary and CRLF or LF line endings.
    static func splitMultipart(_ data: Data, boundary: String) -> [Data] {
        let marker = Data(("--" + boundary).utf8)
        struct Mark { var start: Data.Index; var lineEnd: Data.Index; var closing: Bool }
        var marks: [Mark] = []
        var searchFrom = data.startIndex
        while searchFrom < data.endIndex, let r = data.range(of: marker, in: searchFrom..<data.endIndex) {
            searchFrom = r.upperBound
            // A boundary must start a line and must not be a prefix of a longer boundary.
            let atLineStart = r.lowerBound == data.startIndex || data[r.lowerBound - 1] == 10
            guard atLineStart else { continue }
            var i = r.upperBound
            var closing = false
            if i + 1 < data.endIndex, data[i] == UInt8(ascii: "-"), data[i + 1] == UInt8(ascii: "-") {
                closing = true
                i += 2
            }
            if i < data.endIndex, data[i] != 10, data[i] != 13, data[i] != 32, data[i] != 9 { continue }
            while i < data.endIndex, data[i] != 10 { i += 1 }
            if i < data.endIndex { i += 1 }
            marks.append(Mark(start: r.lowerBound, lineEnd: i, closing: closing))
            if closing { break }
        }
        var parts: [Data] = []
        for (n, mark) in marks.enumerated() {
            if mark.closing { break }
            let start = mark.lineEnd
            var end = n + 1 < marks.count ? marks[n + 1].start : data.endIndex
            if n + 1 < marks.count {
                if end > start, data[end - 1] == 10 { end -= 1 }
                if end > start, data[end - 1] == 13 { end -= 1 }
            }
            if start <= end { parts.append(data.subdata(in: start..<end)) }
        }
        return parts
    }
}

enum DateParsing {
    private static let formatters: [DateFormatter] = {
        let patterns = [
            "EEE, d MMM yyyy HH:mm:ss Z", "d MMM yyyy HH:mm:ss Z", "EEE, d MMM yyyy HH:mm Z", "d MMM yyyy HH:mm Z",
            "EEE, d MMM yyyy HH:mm:ss", "yyyy-MM-dd'T'HH:mm:ssZ", "EEE MMM d HH:mm:ss yyyy",
        ]
        return patterns.map { p in
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            f.dateFormat = p
            return f
        }
    }()

    static func parse(_ text: String) -> Date? {
        // Drop a trailing "(PDT)" comment and collapse whitespace.
        var s = text.replacingOccurrences(of: #"\s*\([^)]*\)\s*$"#, with: "", options: .regularExpression)
        s = s.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression).trimmingCharacters(in: .whitespaces)
        for f in formatters { if let d = f.date(from: s) { return d } }
        return nil
    }
}
