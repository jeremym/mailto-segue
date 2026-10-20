import XCTest
@testable import SegueCore

final class WebmailURLBuilderTests: XCTestCase {
    /// The plan's golden input: a subject with every reserved character and a multi-line body.
    private let request = ComposeRequest(
        to: [EmailAddress(address: "pat@acme.com", name: "Pat"), EmailAddress(address: "lee@acme.com")],
        cc: [EmailAddress(address: "cc@acme.com")],
        bcc: [EmailAddress(address: "bcc@acme.com")],
        subject: "A & B = C + D #1 ?",
        body: "line one\nline two"
    )

    private func build(_ provider: WebmailProvider, account: WebmailAccount? = nil) throws -> String {
        try WebmailURLBuilder.build(request, provider: provider, account: account).url.absoluteString
    }

    func testGmailByIndex() throws {
        XCTAssertEqual(try build(.gmail, account: WebmailAccount(index: 1)),
            "https://mail.google.com/mail/u/1/?view=cm&fs=1&to=pat@acme.com,lee@acme.com&cc=cc@acme.com&bcc=bcc@acme.com&su=A%20%26%20B%20%3D%20C%20%2B%20D%20%231%20%3F&body=line%20one%0Aline%20two")
    }

    func testGmailByEmail() throws {
        XCTAssertEqual(try build(.gmail, account: WebmailAccount(email: "me@work.com")),
            "https://mail.google.com/mail/?authuser=me@work.com&view=cm&fs=1&to=pat@acme.com,lee@acme.com&cc=cc@acme.com&bcc=bcc@acme.com&su=A%20%26%20B%20%3D%20C%20%2B%20D%20%231%20%3F&body=line%20one%0Aline%20two")
    }

    func testGmailNoAccount() throws {
        XCTAssertTrue(try build(.gmail).hasPrefix("https://mail.google.com/mail/?view=cm&fs=1&to="))
    }

    func testOutlookAndOffice365() throws {
        XCTAssertEqual(try build(.outlook),
            "https://outlook.live.com/mail/0/deeplink/compose?to=pat@acme.com,lee@acme.com&cc=cc@acme.com&bcc=bcc@acme.com&subject=A%20%26%20B%20%3D%20C%20%2B%20D%20%231%20%3F&body=line%20one%0Aline%20two")
        XCTAssertEqual(try build(.office365),
            "https://outlook.office.com/mail/deeplink/compose?to=pat@acme.com,lee@acme.com&cc=cc@acme.com&bcc=bcc@acme.com&subject=A%20%26%20B%20%3D%20C%20%2B%20D%20%231%20%3F&body=line%20one%0Aline%20two")
    }

    func testYahoo() throws {
        XCTAssertEqual(try build(.yahoo),
            "https://compose.mail.yahoo.com/?to=pat@acme.com,lee@acme.com&cc=cc@acme.com&bcc=bcc@acme.com&subject=A%20%26%20B%20%3D%20C%20%2B%20D%20%231%20%3F&body=line%20one%0Aline%20two")
    }

    func testProtonFastmailZohoCarryTheWholeMailto() throws {
        let encodedMailto = PercentEncoding.encode(request.mailtoString)
        XCTAssertEqual(try build(.proton), "https://mail.proton.me/inbox#mailto=" + encodedMailto)
        XCTAssertEqual(try build(.proton, account: WebmailAccount(index: 2)), "https://mail.proton.me/u/2/inbox#mailto=" + encodedMailto)
        XCTAssertEqual(try build(.fastmail), "https://www.fastmail.com/action/compose/?mailto=" + encodedMailto)
        XCTAssertEqual(try build(.zoho), "https://mail.zoho.com/mail/compose.do?extsrc=mailto&mode=compose&tp=zb&ct=" + encodedMailto)
        XCTAssertTrue(encodedMailto.hasPrefix("mailto%3APat%2520%253Cpat%40acme.com%253E"), "encoded once more: \(encodedMailto.prefix(50))")
    }

    func testProvidersWithoutComposeURLThrow() {
        XCTAssertThrowsError(try build(.icloud))
        XCTAssertThrowsError(try build(.hey))
        XCTAssertFalse(WebmailProvider.icloud.supportsDirectCompose)
    }

    func testEveryURLParsesBackToTheSameFields() throws {
        // The field-style providers must survive URLComponents decoding.
        for provider in [WebmailProvider.gmail, .outlook, .office365, .yahoo] {
            let url = try WebmailURLBuilder.build(request, provider: provider).url
            let items = URLComponents(url: url, resolvingAgainstBaseURL: false)!.queryItems!
            let dict = Dictionary(items.map { ($0.name, $0.value ?? "") }, uniquingKeysWith: { a, _ in a })
            XCTAssertEqual(dict["to"], "pat@acme.com,lee@acme.com", provider.rawValue)
            XCTAssertEqual(dict["body"], "line one\nline two", provider.rawValue)
            XCTAssertEqual(dict[provider == .gmail ? "su" : "subject"], "A & B = C + D #1 ?", provider.rawValue)
        }
    }

    func testLongBodyOverflowsToClipboard() throws {
        var long = request
        long.body = String(repeating: "quoted line\n", count: 300)
        let built = try WebmailURLBuilder.build(long, provider: .gmail, maxLength: 2000)
        XCTAssertEqual(built.overflowBody, long.body)
        XCTAssertLessThan(built.url.absoluteString.count, 600)
        XCTAssertTrue(built.url.absoluteString.contains("clipboard"))
        let short = try WebmailURLBuilder.build(request, provider: .gmail, maxLength: 2000)
        XCTAssertNil(short.overflowBody)
    }

    func testGmailThreadURL() {
        let url = ComposeRequest.gmailThreadURL(messageID: "<abc.123@mail.acme.com>", account: WebmailAccount(index: 1))
        XCTAssertEqual(url?.absoluteString, "https://mail.google.com/mail/u/1/#search/rfc822msgid%3Aabc.123%40mail.acme.com")
        let byEmail = ComposeRequest.gmailThreadURL(messageID: "abc@x", account: WebmailAccount(email: "me@work.com"))
        XCTAssertEqual(byEmail?.absoluteString, "https://mail.google.com/mail/?authuser=me@work.com#search/rfc822msgid%3Aabc%40x")
        XCTAssertNil(ComposeRequest.gmailThreadURL(messageID: "<>", account: nil))
    }
}

final class TemplateTests: XCTestCase {
    func testExpandsEncodedAndRawTokens() {
        let r = ComposeRequest(to: [EmailAddress(address: "pat@acme.com")], subject: "A & B", body: "x\ny")
        let out = Template.expand("https://x.test/?t={to}&s={subject}&b={body}&d={domain}&raw={subject.raw}", with: r)
        XCTAssertEqual(out, "https://x.test/?t=pat%40acme.com&s=A%20%26%20B&b=x%0Ay&d=acme.com&raw=A & B")
    }

    func testMailtoTokenIsEncodedOnceMore() {
        let r = ComposeRequest(to: [EmailAddress(address: "pat@acme.com")], subject: "Hi there")
        let out = Template.expand("https://mail.google.com/mail/?extsrc=mailto&url={mailto}", with: r)
        XCTAssertEqual(out, "https://mail.google.com/mail/?extsrc=mailto&url=mailto%3Apat%40acme.com%3Fsubject%3DHi%2520there")
    }

    func testUnknownTokensAreLeftAlone() {
        XCTAssertEqual(Template.expand("{nope}", with: ComposeRequest()), "{nope}")
    }
}

final class ClipboardTextTests: XCTestCase {
    let r = ComposeRequest(to: [EmailAddress(address: "a@x.com", name: "A")], cc: [EmailAddress(address: "b@x.com")],
                           subject: "Hi", body: "Body\nhere")

    func testModes() {
        XCTAssertEqual(ClipboardText.text(for: r, mode: .addresses), "a@x.com, b@x.com")
        XCTAssertEqual(ClipboardText.text(for: r, mode: .mailto), r.mailtoString)
        XCTAssertEqual(ClipboardText.text(for: r, mode: .all), "To: A <a@x.com>\nCc: b@x.com\nSubject: Hi\n\nBody\nhere")
    }
}
