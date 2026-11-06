import XCTest
@testable import DefectDashCore

final class BugNumberTests: XCTestCase {
    func testTaskName() { XCTAssertEqual(BugNumber.fromTaskName("Follow up of BUG-184"), 184) }
    func testTaskNameZeroPadded() { XCTAssertEqual(BugNumber.fromTaskName("Follow up of BUG-0044"), 44) }
    func testTaskNameNoBug() { XCTAssertNil(BugNumber.fromTaskName("Qualifications import")) }

    func testWorktreeShapes() {
        let cases: [(String, String?, Int?)] = [
            ("fix/bug-001", "fix/bug-001", 1),
            ("fix/BUG-140", "fix/BUG-140", 140),
            ("bug-006", "bug-006", 6),
            ("bug-013/public-booking-confirmation-email", "bug-013/public-booking-confirmation-email", 13),
            ("feature/bug-185-status-filter", nil, 185),
            ("sprint-4/bug-007", "sprint-4/bug-007", 7),
            ("follow-up-bug-063", "follow-up-bug-063", 63),
            ("fix-bug-004", "fix-bug-004", 4),
            ("fix/bug-0044", "fix/bug-0044-one-row-per-exam", 44),
            ("misc/certificates-v3", "feature/presented-by", nil),
            ("sprint-6/uat-test-scripts", "sprint-6/uat-test-scripts", nil),
            ("main", "main", nil),
        ]
        for (path, branch, expected) in cases {
            XCTAssertEqual(BugNumber.fromWorktree(relativePath: path, branch: branch), expected, path)
        }
    }

    func testBranchWinsWhenPathHasNone() {
        XCTAssertEqual(BugNumber.fromWorktree(relativePath: "misc/scratch", branch: "fix/bug-212-stripe-iso"), 212)
    }
}
