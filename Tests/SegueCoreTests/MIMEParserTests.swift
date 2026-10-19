import XCTest
@testable import SegueCore

final class MIMEParserTests: XCTestCase {
    private func fixture(_ name: String) throws -> EmailMessage {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("Fixtures/eml").appendingPathComponent(name)
        return try MIMEParser.parse(fileURL: url)
    }

    func testPlain() throws {
        let m = try fixture("plain.eml")
        XCTAssertEqual(m.from.first?.address, "pat@acme.com")
        XCTAssertEqual(m.from.first?.name, "Pat Smith")
        XCTAssertEqual(m.to.map(\.address), ["me@work.com"])
        XCTAssertEqual(m.cc.map(\.address), ["lee@acme.com"])
        XCTAssertEqual(m.subject, "Q3 numbers")
        XCTAssertEqual(m.messageID, "<abc.123@mail.acme.com>")
        XCTAssertEqual(m.deliveredTo, "me@work.com")
        XCTAssertEqual(m.listID, "Dev list <dev.lists.acme.com>")
        XCTAssertEqual(m.textBody, "Hi,\n\nHere are the numbers: 42 & 43.\nCheers,\nPat\n")
        XCTAssertNil(m.htmlBody)
        XCTAssertNotNil(m.date)
        let comps = Calendar(identifier: .gregorian).dateComponents(in: TimeZone(secondsFromGMT: 0)!, from: m.date!)
        XCTAssertEqual(comps.hour, 23, "16:12 -0700 is 23:12 UTC")
        XCTAssertTrue(m.parseWarnings.isEmpty)
    }

    func testAlternativeWithBase64AndQuotedPrintable() throws {
        let m = try fixture("alternative.eml")
        XCTAssertEqual(m.subject, "Café meeting 🎵", "adjacent encoded words join without the space")
        XCTAssertEqual(m.textBody, "Hello there,\ncafé & crème\n\nBye\n")
        XCTAssertTrue(m.htmlBody!.contains("caf\u{e9} &amp; crème"))
        XCTAssertEqual(m.bestText, m.textBody)
    }

    func testHTMLOnlyFallsBackToStrippedText() throws {
        let m = try fixture("html-only.eml")
        XCTAssertNil(m.textBody)
        XCTAssertEqual(m.bestText, "Line one\nLine \"two\" — done\nthree")
        XCTAssertFalse(m.bestText.contains("alert"), "scripts and styles are dropped")
    }

    func testLatin1QuotedPrintableAndEncodedHeaders() throws {
        let m = try fixture("latin1.eml")
        XCTAssertEqual(m.from.first?.name, "Jürgen")
        XCTAssertEqual(m.subject, "Grüße")
        XCTAssertTrue(m.textBody!.hasPrefix("Grüße aus München"))
    }

    func testWindows1252AndShiftJIS() throws {
        XCTAssertEqual(try fixture("windows-1252.eml").textBody, "Smart “quotes” and €")
        let jp = try fixture("shift-jis.eml")
        XCTAssertEqual(jp.textBody, "こんにちは、世界")
        XCTAssertEqual(jp.subject, "こんにちは")
    }

    func testAttachmentsInlineImagesAndRFC2231Names() throws {
        let m = try fixture("attachments.eml")
        XCTAssertEqual(m.attachments.count, 3)
        let names = m.attachments.map(\.filename)
        XCTAssertEqual(names, ["logo.png", "Q3 report café.pdf", "notes.txt"])
        XCTAssertTrue(m.attachments[0].isInline)
        XCTAssertEqual(m.attachments[0].contentID, "logo@acme")
        XCTAssertEqual(m.attachments[1].mimeType, "application/pdf")
        XCTAssertEqual(m.attachments[1].data.prefix(4), Data("%PDF".utf8))
        XCTAssertEqual(m.attachments[2].data, Data("just notes".utf8))
        XCTAssertTrue(m.htmlBody!.contains("<b>attached</b>"))
        XCTAssertNil(m.textBody, "a text attachment is not the body")
        XCTAssertEqual(m.replyTo.first?.address, "replies@acme.com")
        XCTAssertEqual(m.references, ["<m0@acme.com>", "<m1@acme.com>"])
        XCTAssertNotNil(m.date, "a trailing (UTC) comment is tolerated")
    }

    func testNestedAndMessageRFC822() throws {
        let m = try fixture("nested.eml")
        XCTAssertEqual(m.textBody, "inner text")
        XCTAssertEqual(m.htmlBody, "<p>inner html</p>")
        XCTAssertEqual(m.attachments.count, 1)
        XCTAssertEqual(m.attachments[0].mimeType, "message/rfc822")
        XCTAssertEqual(m.attachments[0].filename, "message.eml")
    }

    func testFoldedHeaders() throws {
        let m = try fixture("folded-headers.eml")
        XCTAssertEqual(m.to.map(\.address), ["me@work.com", "second@work.com"])
        XCTAssertEqual(m.subject, "This is a long folded subject line")
        XCTAssertEqual(m.header("X-Long"), "one two")
        XCTAssertEqual(m.textBody, "body\n")
    }

    func testMalformedDoesNotCrash() throws {
        let m = try fixture("malformed.eml")
        XCTAssertTrue(m.from.isEmpty)
        XCTAssertEqual(m.subject, "")
        XCTAssertFalse(m.parseWarnings.isEmpty)
    }

    func testMissingClosingBoundary() throws {
        let m = try fixture("no-closing-boundary.eml")
        XCTAssertEqual(m.textBody, "the text part")
        XCTAssertEqual(m.htmlBody, "<p>the html part</p>\n")
    }

    func testXOriginalToAndResolvedDeliveredTo() throws {
        let m = try fixture("x-original-to.eml")
        XCTAssertEqual(m.deliveredTo, "me@work.com")
        var plain = try fixture("nested.eml")
        plain.to = [EmailAddress(address: "A@x.com"), EmailAddress(address: "Me@Work.com")]
        XCTAssertEqual(plain.resolvedDeliveredTo(myAddresses: ["me@work.com"]), "me@work.com")
        XCTAssertEqual(plain.resolvedDeliveredTo(myAddresses: []), "a@x.com")
    }

    func testRawUTF8Headers() throws {
        let m = try fixture("raw-utf8-headers.eml")
        XCTAssertEqual(m.from.first?.name, "Zoë")
        XCTAssertEqual(m.subject, "naïve raw utf-8 header")
    }

    func testEmlx() throws {
        let m = try fixture("apple-mail.emlx")
        XCTAssertEqual(m.subject, "from Apple Mail")
        XCTAssertEqual(m.textBody, "emlx body\n")
        XCTAssertTrue(m.parseWarnings.isEmpty, "the trailing plist is not part of the message")
    }

    func testHeaderDecodingUnits() {
        XCTAssertEqual(HeaderDecoding.decodeEncodedWords("=?utf-8?q?a_b?= =?utf-8?q?c?= d"), "a bc d")
        XCTAssertEqual(HeaderDecoding.decodeEncodedWords("plain"), "plain")
        let (main, params) = HeaderDecoding.parseParameterized("Text/HTML; charset=\"UTF-8\"; name*0*=utf-8''ab%20; name*1=cd")
        XCTAssertEqual(main, "text/html")
        XCTAssertEqual(params["charset"], "UTF-8")
        XCTAssertEqual(params["name"], "ab cd")
        XCTAssertEqual(String(decoding: TransferDecoding.quotedPrintable("a=3Db=\r\nc=\nd="), as: UTF8.self), "a=bcd")
        XCTAssertEqual(HTMLText.decodeEntities("&lt;&#65;&#x42;&nbsp;&bogus;"), "<AB\u{00A0}&bogus;")
    }

    func testDateFormats() {
        XCTAssertNotNil(DateParsing.parse("Mon, 19 Oct 2026 09:00:00 +0200"))
        XCTAssertNotNil(DateParsing.parse("19 Oct 2026 09:00 +0200"))
        XCTAssertNotNil(DateParsing.parse("Sat, 17 Oct 2026 10:00:00 +0000 (UTC)"))
        XCTAssertNil(DateParsing.parse("yesterday"))
    }
}

final class ReplyBuilderTests: XCTestCase {
    private func message() throws -> EmailMessage {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/eml/attachments.eml")
        return try MIMEParser.parse(fileURL: url)
    }

    func testReplyGoesToReplyToAndQuotes() throws {
        let r = ReplyBuilder.build(.reply, from: try message(), myAddresses: ["me@work.com"])
        XCTAssertEqual(r.to.map(\.address), ["replies@acme.com"])
        XCTAssertTrue(r.cc.isEmpty)
        XCTAssertEqual(r.subject, "Re: Files", "no doubled Re:")
        XCTAssertTrue(r.body!.contains("wrote:\n> See the attached file."))
        XCTAssertEqual(r.header("In-Reply-To"), "<m2@acme.com>")
        XCTAssertEqual(r.header("References"), "<m0@acme.com> <m1@acme.com> <m2@acme.com>")
    }

    func testReplyAllDropsMyAddressesAndDuplicates() throws {
        let r = ReplyBuilder.build(.replyAll, from: try message(), myAddresses: ["me@work.com"])
        XCTAssertEqual(r.to.map(\.address), ["replies@acme.com", "other@work.com"])
        XCTAssertEqual(r.cc.map(\.address), ["boss@work.com"])
    }

    func testForward() throws {
        let r = ReplyBuilder.build(.forward, from: try message(), myAddresses: [])
        XCTAssertTrue(r.to.isEmpty)
        XCTAssertEqual(r.subject, "Fwd: Re: Files")
        XCTAssertTrue(r.body!.contains("---------- Forwarded message ----------\nFrom: pat@acme.com"))
        XCTAssertTrue(r.body!.contains("Attachments (not included): logo.png, Q3 report café.pdf, notes.txt"))
        XCTAssertTrue(r.extraHeaders.isEmpty)
    }

    func testSubjectPrefixes() {
        XCTAssertEqual(ReplyBuilder.prefixed("Re:", "RE: hi"), "RE: hi")
        XCTAssertEqual(ReplyBuilder.prefixed("Re:", "AW: hi"), "AW: hi")
        XCTAssertEqual(ReplyBuilder.prefixed("Re:", ""), "Re")
        XCTAssertEqual(ReplyBuilder.prefixed("Fwd:", "Fw: x"), "Fw: x")
        XCTAssertEqual(ReplyBuilder.prefixed("Fwd:", "Re: x"), "Fwd: Re: x")
    }

    func testAttributionWithoutDate() {
        var m = EmailMessage()
        m.from = [EmailAddress(address: "a@x.com", name: "A")]
        XCTAssertEqual(ReplyBuilder.attribution(m), "A <a@x.com> wrote:")
        m.dateText = "Mon, 1 Jan 2026 00:00:00 +0000"
        m.date = DateParsing.parse(m.dateText!)
        XCTAssertTrue(ReplyBuilder.attribution(m).hasPrefix("On "))
    }
}
