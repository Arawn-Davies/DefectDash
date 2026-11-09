import Foundation
import XCTest
@testable import DefectDashCore

final class ActivityTests: XCTestCase {
    static let me = "100"
    static let board = BoardConfig(relayPattern: #"^\S+ comment on BUG-\d+ - (.+?), \d{1,2}/\d{1,2}/\d{4}, [^\n]*\n"#)

    func stories(_ fixture: String) throws -> [AsanaStory] {
        let url = try XCTUnwrap(Bundle.module.url(forResource: fixture, withExtension: "json", subdirectory: "Fixtures"))
        let data = try Data(contentsOf: url)
        return try AsanaDecoding.makeDecoder().decode(AsanaEnvelope<[AsanaStory]>.self, from: data).data
    }

    func date(_ iso: String) -> Date { try! Date.ISO8601FormatStyle().parse(iso) }

    func story(gid: String = UUID().uuidString, at: String, by: AsanaUserRef?, type: String = "comment",
               subtype: String = "comment_added", text: String? = nil, field: String? = nil,
               new: String? = nil, old: String? = nil) -> AsanaStory {
        AsanaStory(gid: gid, createdAt: date(at), createdBy: by, type: type, resourceSubtype: subtype, text: text,
                   customField: field.map(AsanaCustomFieldRef.init), newEnumValue: new.map(AsanaEnumRef.init),
                   oldEnumValue: old.map(AsanaEnumRef.init))
    }

    func testFixtureANoiseDroppedAndOrder() throws {
        let raw = try stories("stories-a")
        XCTAssertEqual(raw.count, 9)
        let events = Activity.events(from: raw, myGid: Self.me, board: Self.board)
        XCTAssertEqual(events.count, 8)   // one personal_comment_reminder_story dropped
        XCTAssertFalse(events.contains { if case .other("personal_comment_reminder_story") = $0.kind { return true } else { return false } })
        for i in 1..<events.count {
            XCTAssertGreaterThan(events[i - 1].at, events[i].at)
        }
    }

    func testRelayPrefixParsed() throws {
        let events = Activity.events(from: try stories("stories-a"), myGid: Self.me, board: Self.board)
        let relayed = try XCTUnwrap(events.first { $0.id == "s6" })
        guard case let .comment(author, text, viaRelay) = relayed.kind else { return XCTFail("not a comment: \(relayed.kind)") }
        XCTAssertEqual(author, "Tester A")
        XCTAssertTrue(text.hasPrefix("Hello"), text)
        XCTAssertFalse(text.contains("ref 1219981597725734"), text)
        XCTAssertTrue(viaRelay)
        XCTAssertEqual(relayed.byName, "Manager")
    }

    func testPlainCommentAuthor() throws {
        let events = Activity.events(from: try stories("stories-a"), myGid: Self.me, board: Self.board)
        let plain = try XCTUnwrap(events.first { $0.id == "s3" })
        guard case let .comment(author, text, viaRelay) = plain.kind else { return XCTFail("not a comment") }
        XCTAssertEqual(author, "Manager")
        XCTAssertTrue(text.hasPrefix("We can't change"), text)
        XCTAssertFalse(viaRelay)
    }

    func testAwaitingAndStatusChanges() throws {
        let events = Activity.events(from: try stories("stories-a"), myGid: Self.me, board: Self.board)
        let awaiting = try XCTUnwrap(events.first { $0.id == "s1" })
        XCTAssertEqual(awaiting.kind, .awaitingChanged(from: "Client", to: "Vendor"))
        let status = try XCTUnwrap(events.first { $0.id == "s9" })
        XCTAssertEqual(status.kind, .defectStatusChanged(from: 3, to: 4))
    }

    func testIsMineByGid() throws {
        let events = Activity.events(from: try stories("stories-a"), myGid: Self.me, board: Self.board)
        XCTAssertEqual(events.first { $0.id == "s4" }?.isMine, true)
        XCTAssertEqual(events.first { $0.id == "s3" }?.isMine, false)
    }

    func testNullCreatorIsNeverMine() {
        let s = story(gid: "x", at: "2026-11-01T00:00:00Z", by: nil, type: "system", subtype: "assigned", text: "assigned to you")
        let events = Activity.events(from: [s], myGid: Self.me, board: Self.board)
        XCTAssertEqual(events.count, 1)
        XCTAssertFalse(events[0].isMine)
        XCTAssertEqual(events[0].kind, .assigned)
        XCTAssertNil(events[0].byGid)
    }

    func testLastOtherAndMyLast() throws {
        let events = Activity.events(from: try stories("stories-a"), myGid: Self.me, board: Self.board)
        XCTAssertEqual(Activity.lastOther(events)?.id, "s1")
        XCTAssertEqual(Activity.lastOther(events)?.at, date("2026-01-20T10:00:00Z"))
        XCTAssertEqual(Activity.myLast(events)?.id, "s4")
        XCTAssertEqual(Activity.myLast(events)?.at, date("2026-01-19T12:00:00Z"))
    }

    func testBouncedOnFixtureB() throws {
        let events = Activity.events(from: try stories("stories-b"), myGid: Self.me, board: Self.board)
        XCTAssertTrue(events.contains { $0.kind == .defectStatusChanged(from: 3, to: 2) })
        XCTAssertFalse(Activity.bounced(events))
        let bounce = story(at: "2026-11-06T00:00:00Z", by: AsanaUserRef(gid: "77", name: "Manager"), type: "system",
                           subtype: "enum_custom_field_changed", field: "Status", new: "3 · In progress",
                           old: "4 · Retest")
        XCTAssertTrue(Activity.bounced(Activity.events(from: [bounce], myGid: Self.me, board: Self.board)))
    }

    func testWithoutRelayPatternCommentsBelongToTheRelayer() throws {
        let events = Activity.events(from: try stories("stories-a"), myGid: Self.me, board: .default)
        let relayed = try XCTUnwrap(events.first { $0.id == "s6" })
        guard case let .comment(author, text, viaRelay) = relayed.kind else { return XCTFail("not a comment") }
        XCTAssertEqual(author, "Manager")
        XCTAssertFalse(viaRelay)
        XCTAssertTrue(text.hasPrefix("Client comment on BUG-101"), text)
    }

    func testCustomFieldNamesComeFromBoardConfig() {
        let board = BoardConfig(statusField: "Stage", awaitingField: "Ball with")
        let stage = story(at: "2026-11-01T00:00:00Z", by: AsanaUserRef(gid: "77", name: "M"), type: "system",
                          subtype: "enum_custom_field_changed", field: "Stage", new: "2 · Next", old: "1 · First")
        let ball = story(at: "2026-11-01T00:00:01Z", by: AsanaUserRef(gid: "77", name: "M"), type: "system",
                         subtype: "enum_custom_field_changed", field: "Ball with", new: "Us", old: "Them")
        let events = Activity.events(from: [stage, ball], myGid: Self.me, board: board)
        XCTAssertEqual(events.map(\.kind), [.awaitingChanged(from: "Them", to: "Us"), .defectStatusChanged(from: 1, to: 2)])
        // With the default names those same stories are unrecognised field changes.
        XCTAssertEqual(Activity.events(from: [stage], myGid: Self.me).map(\.kind), [.other("enum_custom_field_changed")])
    }

    func testBouncedUsesConfiguredRetestStatus() {
        let drop = story(at: "2026-11-01T00:00:00Z", by: AsanaUserRef(gid: "77", name: "M"), type: "system",
                         subtype: "enum_custom_field_changed", field: "Status", new: "4 · Fixing", old: "6 · Retest")
        let events = Activity.events(from: [drop], myGid: Self.me)
        XCTAssertFalse(Activity.bounced(events))
        XCTAssertTrue(Activity.bounced(events, retestStatus: 6))
    }

    func testParseStatusNumber() {
        XCTAssertEqual(Activity.parseStatusNumber("4 · Retest"), 4)
        XCTAssertEqual(Activity.parseStatusNumber("7. Change Request"), 7)
        XCTAssertNil(Activity.parseStatusNumber(nil))
        XCTAssertNil(Activity.parseStatusNumber("Closed"))
    }
}
