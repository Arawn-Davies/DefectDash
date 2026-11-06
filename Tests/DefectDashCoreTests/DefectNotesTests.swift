import Foundation
import XCTest
@testable import DefectDashCore

final class DefectNotesTests: XCTestCase {
    func fixtureText(_ name: String) throws -> String {
        let url = try XCTUnwrap(Bundle.module.url(forResource: name, withExtension: "txt", subdirectory: "Fixtures"))
        return try String(contentsOf: url, encoding: .utf8)
    }

    func testParsesBug184Fixture() throws {
        let notes = DefectNotes.parse(try fixtureText("bug184-notes"))
        XCTAssertTrue(notes.expected?.hasPrefix("The date and time displayed on the card receipt") ?? false, notes.expected ?? "nil")
        XCTAssertTrue(notes.actual?.hasPrefix("The date and time displayed on the invoice") ?? false, notes.actual ?? "nil")
        XCTAssertEqual(notes.environment, "Staging")
        XCTAssertEqual(notes.browser, "Chrome/Mac")
        XCTAssertEqual(notes.priority, "Low")
        XCTAssertEqual(notes.sprint, "5")
        XCTAssertEqual(notes.raisedBy, "Tester A")
        XCTAssertEqual(notes.dateRaised, "Oct 23, 2026")
        XCTAssertEqual(notes.deliverable, "AC-12")
        XCTAssertEqual(notes.testCaseId, "TC-42")
        XCTAssertTrue(notes.steps?.contains("10. Compare") ?? false, notes.steps ?? "nil")
        XCTAssertTrue(notes.steps?.hasPrefix("1. Log in") ?? false)
    }

    func testHeadingsWithOneOrTwoColons() {
        let notes = DefectNotes.parse("Priority:\nLow\n\nEnvironment::\nStaging\n")
        XCTAssertEqual(notes.priority, "Low")
        XCTAssertEqual(notes.environment, "Staging")
    }

    func testCRLFAndMissingSections() {
        let raw = "Expected result (per the agreed acceptance criteria)::\r\nX\r\n\r\nPriority:\r\nHigh"
        let notes = DefectNotes.parse(raw)
        XCTAssertEqual(notes.expected, "X")
        XCTAssertEqual(notes.priority, "High")
        XCTAssertNil(notes.actual)
        XCTAssertNil(notes.steps)
        XCTAssertEqual(notes.raw, raw)
    }

    func testHeadingAliases() {
        let notes = DefectNotes.parse("Reported by:\nAda\n\nExpected behaviour:\nworks\n\nObserved:\nbroken\n\nRepro steps:\n1. go\n\nSeverity:\nHigh\n\nTeam - Sprint:\n7\n")
        XCTAssertEqual(notes.raisedBy, "Ada")
        XCTAssertEqual(notes.expected, "works")
        XCTAssertEqual(notes.actual, "broken")
        XCTAssertEqual(notes.steps, "1. go")
        XCTAssertEqual(notes.priority, "High")
        XCTAssertEqual(notes.sprint, "7")
    }

    func testEmptyNotes() {
        let notes = DefectNotes.parse("")
        XCTAssertEqual(notes, DefectNotes(raisedBy: nil, dateRaised: nil, deliverable: nil, environment: nil, browser: nil,
                                          steps: nil, expected: nil, actual: nil, testCaseId: nil, priority: nil,
                                          sprint: nil, raw: ""))
    }

    func testTrailingFormFooterIsNotASection() {
        let notes = DefectNotes.parse("ACME - SPRINT:\n5\n\n———————————————\nThis task was submitted through  Defect Report\nhttps://form.asana.com/?k=x")
        XCTAssertEqual(notes.sprint, "5")
        let dashed = DefectNotes.parse("Priority:\nLow\n---\nfooter")
        XCTAssertEqual(dashed.priority, "Low")
    }
}
