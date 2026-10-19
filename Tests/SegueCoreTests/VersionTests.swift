import XCTest
@testable import SegueCore

final class VersionTests: XCTestCase {
    func testVersionLooksLikeSemver() {
        let parts = SegueVersion.string.split(separator: ".")
        XCTAssertEqual(parts.count, 3)
        XCTAssertTrue(parts.allSatisfy { Int($0) != nil })
    }
}
