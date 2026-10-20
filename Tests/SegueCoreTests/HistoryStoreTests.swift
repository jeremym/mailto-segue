import XCTest
@testable import SegueCore

final class HistoryStoreTests: XCTestCase {
    private func store() -> HistoryStore {
        HistoryStore(supportDirectory: FileManager.default.temporaryDirectory.appendingPathComponent("segue-history-\(UUID().uuidString)"))
    }

    private func item(_ n: Int) -> HistoryItem {
        var d = Destination(id: "d", name: "Dest", type: .clipboard)
        d.copy = .addresses
        return HistoryItem(kind: .mailto, source: SourceApp(bundleID: "com.apple.Safari", name: "Safari"),
                           request: ComposeRequest(to: [EmailAddress(address: "p\(n)@x.com")], subject: "S\(n)"),
                           destination: d, explanation: .pickedByUser)
    }

    func testRecordRoundTripAndBody() {
        let s = store()
        let body = String(repeating: "quoted text line\n", count: 200)
        let stored = s.record(item(1), body: body, settings: HistorySettings())!
        XCTAssertTrue(stored.hasBody)
        XCTAssertLessThan(stored.bodyBytes, body.utf8.count / 4, "LZFSE shrinks repetitive text a lot")
        let items = s.items()
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].subject, "S1")
        XCTAssertEqual(items[0].primaryRecipient, "p1@x.com")
        XCTAssertEqual(s.body(for: items[0]), body)
        XCTAssertEqual(s.usage().items, 1)
        XCTAssertGreaterThan(s.usage().bytes, 0)
    }

    func testNewestFirstAndItemCap() {
        let s = store()
        var settings = HistorySettings()
        settings.keepItems = 3
        for n in 1...5 { s.record(item(n), body: "b\(n)", settings: settings) }
        XCTAssertEqual(s.items().map(\.subject), ["S5", "S4", "S3"])
        let bodies = try? FileManager.default.contentsOfDirectory(atPath: s.bodiesURL.path)
        XCTAssertEqual(bodies?.count, 3, "dropped items lose their body files")
    }

    func testSizeCap() {
        let s = store()
        var settings = HistorySettings()
        settings.maxMB = 1
        let big = String((0..<300_000).map { _ in "abcdefghijklmnopqrstuvwxyz".randomElement()! })  // ~300 KB, barely compressible
        for n in 1...6 { s.record(item(n), body: big, settings: settings) }
        let usage = s.usage()
        XCTAssertLessThanOrEqual(usage.bytes, 1_000_000 + 10_000)
        XCTAssertLessThan(usage.items, 6)
    }

    func testOffAndClear() {
        let s = store()
        var off = HistorySettings()
        off.keepItems = 0
        XCTAssertNil(s.record(item(1), body: "x", settings: off))
        XCTAssertEqual(s.items().count, 0)
        s.record(item(2), body: "x", settings: HistorySettings())
        s.remove(id: s.items()[0].id)
        XCTAssertEqual(s.items().count, 0)
        s.record(item(3), body: "x", settings: HistorySettings())
        s.clear()
        XCTAssertEqual(s.items().count, 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: s.indexURL.path))
    }

    func testEnforceAfterLoweringCaps() {
        let s = store()
        for n in 1...4 { s.record(item(n), body: "b", settings: HistorySettings()) }
        var lower = HistorySettings()
        lower.keepItems = 2
        s.enforce(settings: lower)
        XCTAssertEqual(s.items().count, 2)
    }
}
