import XCTest
@testable import SegueCore

final class ConfigTests: XCTestCase {
    private func fixture(_ name: String) throws -> Data {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("Fixtures").appendingPathComponent(name)
        return try Data(contentsOf: url)
    }

    private func tempStore() throws -> ConfigStore {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("segue-tests-\(UUID().uuidString)", isDirectory: true)
        return ConfigStore(directory: dir)
    }

    func testExampleDecodes() throws {
        let config = try ConfigStore.decode(fixture("config-example.json"))
        XCTAssertEqual(config.version, 1)
        XCTAssertEqual(config.fallback, .chooser)
        XCTAssertEqual(config.destinations.count, 5)
        XCTAssertEqual(config.destinations[1].browser?.windowMode, .app)
        XCTAssertEqual(config.destinations[1].account?.email, "me@work.com")
        XCTAssertEqual(config.rules.count, 3)
        XCTAssertEqual(config.rules[0].builtin, "replyFromReceiver")
        XCTAssertEqual(config.rules[2].match, .any)
        XCTAssertEqual(config.rules[2].when[0].op, .domainIs)
        XCTAssertEqual(config.chooser.position, .center)
        XCTAssertFalse(config.general.stayRunning)
        XCTAssertEqual(config.validate(), [])
        XCTAssertEqual(config.myAddresses, ["jeremy.mooer@gmail.com", "me@work.com", "me@yahoo.com"])
        XCTAssertEqual(config.activeDestinations.first?.id, "gmail-work", "pinned first")
    }

    func testRoundTripIsStableAndSorted() throws {
        let config = try ConfigStore.decode(fixture("config-example.json"))
        let once = try ConfigStore.encode(config)
        let again = try ConfigStore.encode(try ConfigStore.decode(once))
        XCTAssertEqual(once, again)
        let text = String(decoding: once, as: UTF8.self)
        XCTAssertTrue(text.hasSuffix("\n"))
        // Sorted keys: "chooser" comes before "destinations" before "version".
        let c = text.range(of: "\"chooser\"")!.lowerBound
        let d = text.range(of: "\"destinations\"")!.lowerBound
        let v = text.range(of: "\"version\"")!.lowerBound
        XCTAssertLessThan(c, d)
        XCTAssertLessThan(d, v)
        XCTAssertTrue(text.contains("\"fallback\" : \"chooser\""))
        XCTAssertTrue(text.contains("images/work.png"), "slashes are not escaped")
    }

    func testFallbackDestinationEncodesAsPlainString() throws {
        var config = Config()
        config.destinations = [Destination(id: "a", name: "A", type: .clipboard)]
        config.fallback = .destination("a")
        let data = try ConfigStore.encode(config)
        XCTAssertTrue(String(decoding: data, as: UTF8.self).contains("\"fallback\" : \"a\""))
        XCTAssertEqual(try ConfigStore.decode(data).fallback, .destination("a"))
    }

    func testMissingFileGivesDefaults() throws {
        let store = try tempStore()
        let config = store.load()
        XCTAssertEqual(config, Config())
        XCTAssertNil(store.lastError)
        XCTAssertFalse(store.exists)
    }

    func testSaveThenLoad() throws {
        let store = try tempStore()
        var config = Config()
        config.destinations = [Destination(id: "copy", name: "Copy", type: .clipboard, key: "c")]
        try store.save(config)
        XCTAssertTrue(store.exists)
        XCTAssertEqual(store.load(), config)
        XCTAssertNil(store.lastError)
    }

    func testBadJSONKeepsLastGoodConfig() throws {
        let store = try tempStore()
        var good = Config()
        good.destinations = [Destination(id: "copy", name: "Copy", type: .clipboard)]
        try store.save(good)
        try Data("{ not json".utf8).write(to: store.fileURL)
        let loaded = store.load()
        XCTAssertEqual(loaded, good)
        XCTAssertNotNil(store.lastError)
    }

    func testValidationFindsProblems() {
        var config = Config()
        config.destinations = [
            Destination(id: "a", name: "A", type: .webmail),
            Destination(id: "a", name: "", type: .app),
        ]
        config.rules = [Rule(name: "r", then: "nope")]
        config.fallback = .destination("ghost")
        let issues = config.validate()
        XCTAssertTrue(issues.contains { $0.contains("duplicate destination id 'a'") })
        XCTAssertTrue(issues.contains { $0.contains("needs a provider") })
        XCTAssertTrue(issues.contains { $0.contains("empty name") })
        XCTAssertTrue(issues.contains { $0.contains("needs a bundleID") })
        XCTAssertTrue(issues.contains { $0.contains("unknown destination 'nope'") })
        XCTAssertTrue(issues.contains { $0.contains("fallback points at unknown destination 'ghost'") })
    }

    func testMinimalConfigDecodesWithDefaults() throws {
        let data = Data(#"{ "destinations": [ { "id": "copy", "name": "Copy", "type": "clipboard" } ] }"#.utf8)
        let config = try ConfigStore.decode(data)
        XCTAssertEqual(config.version, 1)
        XCTAssertEqual(config.fallback, .chooser)
        XCTAssertEqual(config.destinations.count, 1)
        XCTAssertEqual(config.chooser, ChooserSettings())
        XCTAssertEqual(config.general, GeneralSettings())
        XCTAssertEqual(try ConfigStore.decode(Data("{}".utf8)), Config())
        XCTAssertFalse(config.general.onboarded)
        XCTAssertFalse(config.general.rulesPaused)
        let flagged = try ConfigStore.decode(Data(#"{ "general": { "onboarded": true, "rulesPaused": true } }"#.utf8))
        XCTAssertTrue(flagged.general.onboarded)
        XCTAssertTrue(flagged.general.rulesPaused)
    }

    func testRuleDefaultsWhenKeysAreMissing() throws {
        let data = Data(#"{"name":"x","then":"d"}"#.utf8)
        let rule = try JSONDecoder().decode(Rule.self, from: data)
        XCTAssertTrue(rule.enabled)
        XCTAssertEqual(rule.match, .all)
        XCTAssertEqual(rule.when, [])
    }
}
