import XCTest
@testable import SegueCore

final class LoopGuardTests: XCTestCase {
    private func guardInTemp() -> LoopGuard {
        LoopGuard(directory: FileManager.default.temporaryDirectory
            .appendingPathComponent("segue-loop-\(UUID().uuidString)", isDirectory: true))
    }

    func testFreshLinkIsNotABounce() {
        let g = guardInTemp()
        XCTAssertNil(g.bounce(for: "mailto:a@x.com", sourceBundleID: "com.apple.Safari"))
    }

    func testSameLinkFromTargetWithinWindowIsABounce() {
        let g = guardInTemp()
        let t0 = Date()
        g.remember(mailto: "mailto:a@x.com?subject=hi", destinationID: "chrome-handler", targetBundleID: "com.google.Chrome", now: t0)
        let bounce = g.bounce(for: "mailto:a@x.com?subject=hi", sourceBundleID: "com.google.Chrome", now: t0.addingTimeInterval(1))
        XCTAssertEqual(bounce?.destinationID, "chrome-handler")
    }

    func testReencodedLinkStillCounts() {
        let g = guardInTemp()
        let t0 = Date()
        g.remember(mailto: "mailto:a@x.com?subject=Hi%20there", destinationID: "d", targetBundleID: nil, now: t0)
        XCTAssertNotNil(g.bounce(for: "mailto:a@x.com?Subject=Hi there", sourceBundleID: nil, now: t0.addingTimeInterval(0.5)))
    }

    func testOutsideWindowIsFresh() {
        let g = guardInTemp()
        let t0 = Date()
        g.remember(mailto: "mailto:a@x.com", destinationID: "d", targetBundleID: "com.google.Chrome", now: t0)
        XCTAssertNil(g.bounce(for: "mailto:a@x.com", sourceBundleID: "com.google.Chrome", now: t0.addingTimeInterval(10)))
    }

    func testDifferentSenderIsFresh() {
        let g = guardInTemp()
        let t0 = Date()
        g.remember(mailto: "mailto:a@x.com", destinationID: "d", targetBundleID: "com.google.Chrome", now: t0)
        XCTAssertNil(g.bounce(for: "mailto:a@x.com", sourceBundleID: "com.apple.Safari", now: t0.addingTimeInterval(1)))
    }
}
