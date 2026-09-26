import XCTest
@testable import LocalMusic

final class WhatsNewTests: XCTestCase {
    private let seenKey = WhatsNew.lastSeenKey

    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: seenKey)
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: seenKey)
        super.tearDown()
    }

    func testReleasesSortedNewestFirst() {
        let releases = WhatsNew.all
        XCTAssertFalse(releases.isEmpty)
        for i in 0..<(releases.count - 1) {
            XCTAssertGreaterThan(releases[i].build, releases[i + 1].build)
        }
    }

    func testLatestReleaseHasMotivationsAndChanges() {
        let latest = WhatsNew.latest
        XCTAssertEqual(latest.version, "1.2.0")
        XCTAssertFalse(latest.headline.isEmpty)
        XCTAssertFalse(latest.why.isEmpty, "Motivations must be provided per standing rules")
        XCTAssertFalse(latest.changes.isEmpty)
    }

    func testUnseenFilterAndMarkSeen() {
        XCTAssertTrue(WhatsNew.hasUnseen)
        XCTAssertEqual(WhatsNew.unseen.first?.version, "1.2.0")

        WhatsNew.markSeen()
        XCTAssertFalse(WhatsNew.hasUnseen)
        XCTAssertTrue(WhatsNew.unseen.isEmpty)
    }
}
