import XCTest
@testable import SegueCore

final class RuleEngineTests: XCTestCase {
    private var config: Config = {
        var c = Config()
        var work = Destination(id: "gmail-work", name: "Gmail — work", type: .webmail)
        work.provider = .gmail
        work.sendsAs = ["me@work.com"]
        var personal = Destination(id: "gmail-personal", name: "Gmail — personal", type: .webmail)
        personal.provider = .gmail
        personal.sendsAs = ["jeremy@example.com"]
        var mail = Destination(id: "mail", name: "Mail", type: .app)
        mail.bundleID = "com.apple.mail"
        c.destinations = [work, personal, mail]
        return c
    }()

    private func context(to: String = "pat@acme.com", source: String? = "com.tinyspeck.slackmacgap",
                         subject: String? = nil, original: OriginalMessage? = nil) -> RouteContext {
        RouteContext(kind: original == nil ? .mailto : .reply,
                     request: ComposeRequest(to: [EmailAddress(address: to)], subject: subject),
                     source: source.map { SourceApp(bundleID: $0, name: "Slack") },
                     original: original)
    }

    func testFirstMatchWinsInOrder() {
        config.rules = [
            Rule(name: "Slack → work", when: [Condition(field: "sourceApp", op: .is, value: "com.tinyspeck.slackmacgap")], then: "gmail-work"),
            Rule(name: "acme → personal", when: [Condition(field: "to.domain", op: .domainIs, value: "acme.com")], then: "gmail-personal"),
        ]
        let m = RuleEngine.evaluate(context(), config: config)
        XCTAssertEqual(m?.destinationID, "gmail-work")
        XCTAssertEqual(m?.explanation.ruleName, "Slack → work")
        XCTAssertEqual(m?.explanation.text, "Rule “Slack → work” matched: sourceApp is com.tinyspeck.slackmacgap")
    }

    func testDisabledRulesAreSkipped() {
        config.rules = [
            Rule(name: "off", enabled: false, when: [Condition(field: "sourceApp", op: .is, value: "com.tinyspeck.slackmacgap")], then: "gmail-work"),
            Rule(name: "on", when: [Condition(field: "to.domain", op: .domainIs, value: "acme.com")], then: "gmail-personal"),
        ]
        XCTAssertEqual(RuleEngine.evaluate(context(), config: config)?.destinationID, "gmail-personal")
    }

    func testAllVersusAny() {
        let a = Condition(field: "sourceApp", op: .is, value: "com.tinyspeck.slackmacgap")
        let b = Condition(field: "to.domain", op: .domainIs, value: "other.com")
        config.rules = [Rule(name: "all", match: .all, when: [a, b], then: "gmail-work")]
        XCTAssertNil(RuleEngine.evaluate(context(), config: config))
        config.rules = [Rule(name: "any", match: .any, when: [b, a], then: "gmail-work")]
        let m = RuleEngine.evaluate(context(), config: config)
        XCTAssertEqual(m?.destinationID, "gmail-work")
        XCTAssertEqual(m?.explanation.condition, "sourceApp is com.tinyspeck.slackmacgap", "the condition that hit is named")
    }

    func testDomainIsIncludesSubdomains() {
        config.rules = [Rule(name: "r", when: [Condition(field: "to.domain", op: .domainIs, value: "acme.com")], then: "gmail-work")]
        XCTAssertNotNil(RuleEngine.evaluate(context(to: "x@mail.acme.com"), config: config))
        XCTAssertNil(RuleEngine.evaluate(context(to: "x@notacme.com"), config: config))
        config.rules = [Rule(name: "r", when: [Condition(field: "to", op: .domainIs, value: "acme.com")], then: "gmail-work")]
        XCTAssertNotNil(RuleEngine.evaluate(context(to: "x@acme.com"), config: config), "domainIs works on an address field too")
    }

    func testRegexAndContainsAndStartsWith() {
        config.rules = [Rule(name: "inv", when: [Condition(field: "subject", op: .matches, value: "^inv(oice)?\\s*#?\\d+")], then: "gmail-work")]
        XCTAssertNotNil(RuleEngine.evaluate(context(subject: "Invoice #42"), config: config))
        XCTAssertNil(RuleEngine.evaluate(context(subject: "Re: invoice"), config: config))
        config.rules = [Rule(name: "c", when: [Condition(field: "subject", op: .contains, value: "urgent")], then: "mail")]
        XCTAssertNotNil(RuleEngine.evaluate(context(subject: "Very URGENT thing"), config: config))
        config.rules = [Rule(name: "s", when: [Condition(field: "to", op: .startsWith, value: "pat@")], then: "mail")]
        XCTAssertNotNil(RuleEngine.evaluate(context(), config: config))
        config.rules = [Rule(name: "bad", when: [Condition(field: "subject", op: .matches, value: "(")], then: "mail")]
        XCTAssertNil(RuleEngine.evaluate(context(subject: "("), config: config), "a broken regex never matches")
    }

    func testUnknownDestinationOrEmptyConditionsNeverMatch() {
        config.rules = [Rule(name: "ghost", when: [Condition(field: "kind", op: .is, value: "mailto")], then: "nope"),
                        Rule(name: "empty", when: [], then: "mail")]
        XCTAssertNil(RuleEngine.evaluate(context(), config: config))
    }

    func testReplyFromReceiver() {
        config.rules = [Rule(builtin: .replyFromReceiver)]
        let original = OriginalMessage(from: EmailAddress(address: "pat@acme.com"), deliveredTo: "Me@Work.com")
        let m = RuleEngine.evaluate(context(original: original), config: config)
        XCTAssertEqual(m?.destinationID, "gmail-work")
        XCTAssertEqual(m?.explanation.text, "Reply from the account that received it (me@work.com)")
        XCTAssertNil(RuleEngine.evaluate(context(), config: config), "no original, no match")
        XCTAssertNil(RuleEngine.evaluate(context(original: OriginalMessage(deliveredTo: "nobody@x.com")), config: config))
    }

    func testOriginalFieldsAndHeaders() {
        let original = OriginalMessage(from: EmailAddress(address: "news@lists.acme.com"), deliveredTo: "me@work.com",
                                       listID: "<dev.lists.acme.com>", headers: [.init(name: "X-Priority", value: "1")])
        let ctx = context(original: original)
        XCTAssertEqual(ctx.values(for: "original.from.domain"), ["lists.acme.com"])
        XCTAssertEqual(ctx.values(for: "original.deliveredTo.domain"), ["work.com"])
        XCTAssertEqual(ctx.values(for: "original.listId"), ["<dev.lists.acme.com>"])
        XCTAssertEqual(ctx.values(for: "original.header.x-priority"), ["1"])
        XCTAssertEqual(ctx.values(for: "kind"), ["reply"])
        XCTAssertEqual(ctx.values(for: "nonsense"), [])
    }

    func testRememberedRuleBuildsAndMatches() {
        let ctx = context()
        let rule = Rule.remembered(context: ctx, destination: config.destinations[0], app: true, domain: true, sender: false)!
        XCTAssertEqual(rule.name, "Slack + acme.com → Gmail — work")
        XCTAssertEqual(rule.when.count, 2)
        config.rules = [rule]
        XCTAssertEqual(RuleEngine.evaluate(ctx, config: config)?.destinationID, "gmail-work")
        XCTAssertNil(RuleEngine.evaluate(context(source: "com.apple.Safari"), config: config), "AND: a different app doesn't match")
        XCTAssertNil(Rule.remembered(context: ctx, destination: config.destinations[0], app: false, domain: false, sender: true))
    }
}

final class LearnedChoicesTests: XCTestCase {
    func testRecordAndSuggest() {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("segue-learned-\(UUID().uuidString)")
        let learned = LearnedChoices(directory: dir)
        let slack = RouteContext(kind: .mailto, request: ComposeRequest(to: [EmailAddress(address: "pat@acme.com")]),
                                 source: SourceApp(bundleID: "com.tinyspeck.slackmacgap", name: "Slack"))
        XCTAssertNil(learned.suggestion(for: slack, validIDs: ["a", "b"]))
        learned.record(slack, destinationID: "a")
        XCTAssertEqual(learned.suggestion(for: slack, validIDs: ["a", "b"]), "a")
        // Same domain from another app: the domain memory applies.
        let safari = RouteContext(kind: .mailto, request: ComposeRequest(to: [EmailAddress(address: "lee@acme.com")]),
                                  source: SourceApp(bundleID: "com.apple.Safari", name: "Safari"))
        XCTAssertEqual(learned.suggestion(for: safari, validIDs: ["a", "b"]), "a")
        // The app memory wins over the domain memory.
        learned.record(safari, destinationID: "b")
        XCTAssertEqual(learned.suggestion(for: safari, validIDs: ["a", "b"]), "b")
        XCTAssertNil(learned.suggestion(for: safari, validIDs: ["zzz"]), "a deleted destination is ignored")
        learned.clear()
        XCTAssertNil(learned.suggestion(for: slack, validIDs: ["a"]))
    }
}
