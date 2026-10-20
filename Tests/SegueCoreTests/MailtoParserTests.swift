import XCTest
@testable import SegueCore

final class MailtoParserTests: XCTestCase {
    func testSimpleAddress() {
        let r = MailtoParser.parse("mailto:pat@acme.com")
        XCTAssertEqual(r.to.map(\.address), ["pat@acme.com"])
        XCTAssertNil(r.subject)
        XCTAssertNil(r.body)
    }

    func testSchemeIsCaseInsensitiveAndWhitespaceTrimmed() {
        let r = MailtoParser.parse("  MailTo:pat@acme.com \n")
        XCTAssertEqual(r.to.map(\.address), ["pat@acme.com"])
    }

    func testMultipleToInPathAndQuery() {
        let r = MailtoParser.parse("mailto:a@x.com,b@x.com?to=c@x.com&TO=d@x.com")
        XCTAssertEqual(r.to.map(\.address), ["a@x.com", "b@x.com", "c@x.com", "d@x.com"])
    }

    func testCcBccSubjectBody() {
        let r = MailtoParser.parse("mailto:a@x.com?cc=b@x.com&bcc=c@x.com&subject=Hi%20there&body=Line%201%0D%0ALine%202")
        XCTAssertEqual(r.cc.map(\.address), ["b@x.com"])
        XCTAssertEqual(r.bcc.map(\.address), ["c@x.com"])
        XCTAssertEqual(r.subject, "Hi there")
        XCTAssertEqual(r.body, "Line 1\nLine 2")
    }

    func testMixedCaseHeaderNamesAndRepeats() {
        let r = MailtoParser.parse("mailto:?Subject=a&SUBJECT=b&Cc=x@y.com&cC=z@y.com")
        XCTAssertEqual(r.subject, "a b")
        XCTAssertEqual(r.cc.map(\.address), ["x@y.com", "z@y.com"])
    }

    func testPlusIsLiteralByDefault() {
        let r = MailtoParser.parse("mailto:a+tag@x.com?subject=C%2B%2B+rocks")
        XCTAssertEqual(r.to.first?.address, "a+tag@x.com")
        XCTAssertEqual(r.subject, "C+++rocks")
    }

    func testPlusAsSpaceOption() {
        let r = MailtoParser.parse("mailto:a@x.com?subject=hello+world", options: .init(plusAsSpace: true))
        XCTAssertEqual(r.subject, "hello world")
    }

    func testLFBodyIsKept() {
        let r = MailtoParser.parse("mailto:a@x.com?body=one%0Atwo%0Athree")
        XCTAssertEqual(r.body, "one\ntwo\nthree")
    }

    func testUTF8AndEmoji() {
        let r = MailtoParser.parse("mailto:a@x.com?subject=Caf%C3%A9%20%F0%9F%8E%B5&body=na%C3%AFve")
        XCTAssertEqual(r.subject, "Café 🎵")
        XCTAssertEqual(r.body, "naïve")
    }

    func testEncodedPercentSign() {
        let r = MailtoParser.parse("mailto:a@x.com?subject=100%25%20sure")
        XCTAssertEqual(r.subject, "100% sure")
    }

    func testReservedCharactersInsideValues() {
        let r = MailtoParser.parse("mailto:a@x.com?subject=A%20%26%20B%20%3D%20C%20%2B%20D%20%231%20%3F&body=x%3Dy%26z")
        XCTAssertEqual(r.subject, "A & B = C + D #1 ?")
        XCTAssertEqual(r.body, "x=y&z")
    }

    func testUnencodedHashIsLiteral() {
        let r = MailtoParser.parse("mailto:a@x.com?subject=Issue #1")
        XCTAssertEqual(r.subject, "Issue #1")
    }

    func testEmptyAndNoRecipient() {
        XCTAssertTrue(MailtoParser.parse("mailto:").isEmpty)
        let r = MailtoParser.parse("mailto:?subject=hi")
        XCTAssertTrue(r.to.isEmpty)
        XCTAssertEqual(r.subject, "hi")
        XCTAssertEqual(r.primaryRecipient, "")
    }

    func testUnknownHeadersAreKeptInOrder() {
        let r = MailtoParser.parse("mailto:a@x.com?In-Reply-To=%3Cid%40x%3E&X-Foo=bar")
        XCTAssertEqual(r.extraHeaders.map(\.name), ["In-Reply-To", "X-Foo"])
        XCTAssertEqual(r.header("in-reply-to"), "<id@x>")
        XCTAssertEqual(r.header("x-foo"), "bar")
    }

    func testInvalidPercentSequencesAreKeptRaw() {
        let r = MailtoParser.parse("mailto:a@x.com?subject=50%zz%2")
        XCTAssertEqual(r.subject, "50%zz%2")
    }

    func testLongBody() {
        let body = String(repeating: "word ", count: 2000)
        let r = MailtoParser.parse("mailto:a@x.com?body=" + PercentEncoding.encode(body))
        XCTAssertEqual(r.body, body)
    }

    func testIDNDomainAndDisplayNames() {
        let r = MailtoParser.parse("mailto:Pat%20Smith%20%3Cpat@m%C3%BCnchen.de%3E,%22Lee,%20Kim%22%20%3Ckim@x.com%3E")
        XCTAssertEqual(r.to.count, 2)
        XCTAssertEqual(r.to[0].name, "Pat Smith")
        XCTAssertEqual(r.to[0].address, "pat@münchen.de")
        XCTAssertEqual(r.to[0].domain, "münchen.de")
        XCTAssertEqual(r.to[1].name, "Lee, Kim")
        XCTAssertEqual(r.to[1].address, "kim@x.com")
    }

    func testDoubleSlashFormIsTolerated() {
        let r = MailtoParser.parse("mailto://a@x.com?subject=x")
        XCTAssertEqual(r.to.map(\.address), ["a@x.com"])
    }

    func testEmptyQueryPairsAreIgnored() {
        let r = MailtoParser.parse("mailto:a@x.com?&&subject=x&")
        XCTAssertEqual(r.subject, "x")
        XCTAssertTrue(r.extraHeaders.isEmpty)
    }

    func testNewlinesInSubjectBecomeSpaces() {
        let r = MailtoParser.parse("mailto:a@x.com?subject=one%0D%0Atwo")
        XCTAssertEqual(r.subject, "one two")
    }

    // MARK: - Round trip

    func testMailtoStringRoundTripsStrictly() {
        let original = ComposeRequest(
            to: [EmailAddress(address: "a@x.com", name: "Pat Smith")],
            cc: [EmailAddress(address: "b@x.com")],
            bcc: [EmailAddress(address: "c@x.com")],
            subject: "A & B = C + D #1 ?",
            body: "line 1\nline 2 100%",
            extraHeaders: [.init(name: "In-Reply-To", value: "<id@x>")]
        )
        let s = original.mailtoString
        XCTAssertTrue(s.hasPrefix("mailto:Pat%20Smith%20%3Ca@x.com%3E?"))
        XCTAssertTrue(s.contains("subject=A%20%26%20B%20%3D%20C%20%2B%20D%20%231%20%3F"))
        XCTAssertTrue(s.contains("body=line%201%0D%0Aline%202%20100%25"))
        XCTAssertFalse(s.contains("&body=line 1"))
        XCTAssertEqual(MailtoParser.parse(s), original)
    }

    func testEmptyRequestMailtoString() {
        XCTAssertEqual(ComposeRequest().mailtoString, "mailto:")
    }
}

final class PercentEncodingTests: XCTestCase {
    func testOnlyUnreservedPassThrough() {
        XCTAssertEqual(PercentEncoding.encode("AZaz09-._~"), "AZaz09-._~")
        XCTAssertEqual(PercentEncoding.encode(" &=+#?/:@"), "%20%26%3D%2B%23%3F%2F%3A%40")
    }

    func testNewlineModes() {
        XCTAssertEqual(PercentEncoding.encode("a\nb", newline: .lf), "a%0Ab")
        XCTAssertEqual(PercentEncoding.encode("a\r\nb", newline: .crlf), "a%0D%0Ab")
        XCTAssertEqual(PercentEncoding.encode("a\rb", newline: .lf), "a%0Ab")
    }

    func testAddressKeepsAt() {
        XCTAssertEqual(PercentEncoding.encodeAddress("a@x.com"), "a@x.com")
    }

    func testDecodeKeepsInvalidSequences() {
        XCTAssertEqual(PercentEncoding.decode("%41%zz%4"), "A%zz%4")
        XCTAssertEqual(PercentEncoding.decode("100%"), "100%")
    }

    func testDecodeInvalidUTF8DoesNotCrash() {
        XCTAssertEqual(PercentEncoding.decode("%FF%FE").count, 2)
    }
}

final class EmailAddressTests: XCTestCase {
    func testDomainAndSubdomainMatching() {
        let a = EmailAddress(address: "pat@Mail.Acme.com")
        XCTAssertEqual(a.domain, "mail.acme.com")
        XCTAssertTrue(a.isIn(domain: "acme.com"))
        XCTAssertTrue(a.isIn(domain: "mail.acme.com"))
        XCTAssertFalse(a.isIn(domain: "notacme.com"))
        XCTAssertFalse(a.isIn(domain: "cme.com"))
    }

    func testDescriptionQuotesWhenNeeded() {
        XCTAssertEqual(EmailAddress(address: "a@x.com", name: "Lee, Kim").description, "\"Lee, Kim\" <a@x.com>")
        XCTAssertEqual(EmailAddress(address: "a@x.com", name: "Pat").description, "Pat <a@x.com>")
        XCTAssertEqual(EmailAddress(address: "a@x.com").description, "a@x.com")
    }

    func testListParsingHonoursQuotesAndSemicolons() {
        let list = EmailAddress.list(parsing: "\"Lee, Kim\" <a@x.com>; b@x.com, <c@x.com>")
        XCTAssertEqual(list.map(\.address), ["a@x.com", "b@x.com", "c@x.com"])
        XCTAssertEqual(list[0].name, "Lee, Kim")
        XCTAssertNil(list[2].name)
    }
}
