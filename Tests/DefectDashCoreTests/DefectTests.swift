import Foundation
import XCTest
@testable import DefectDashCore

final class DefectTests: XCTestCase {
    static let me = "100"
    let labels = AwaitingLabels(ours: "Vendor", theirs: "Client")
    var board: BoardConfig { BoardConfig(awaitingLabels: labels) }
    let utc: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    func task(name: String, fields: [(String, String?)], dueOn: String? = nil, dependents: [String] = [],
              assignee: AsanaUserRef? = nil) -> AsanaTask {
        AsanaTask(gid: "t1", name: name, notes: "Priority:\nLow\n", assignee: assignee, dueOn: dueOn,
                  modifiedAt: Date(timeIntervalSince1970: 1_793_789_572), permalinkUrl: "https://app.asana.com/0/1/t1",
                  customFields: fields.map { AsanaCustomField(name: $0.0, displayValue: $0.1) },
                  dependents: dependents.map(AsanaDependentRef.init))
    }

    func testAssemblesFromTask() throws {
        let t = task(name: "Follow up of BUG-184",
                     fields: [("Status", "4 · Retest"), ("Awaiting", "Vendor"),
                              ("Classification", nil), ("ACME - SPRINT", "5")],
                     dueOn: "2026-10-26", dependents: ["5001"],
                     assignee: AsanaUserRef(gid: Self.me, name: "Dev One"))
        let story = AsanaStory(gid: "s1", createdAt: Date(timeIntervalSince1970: 1_793_710_413),
                               createdBy: AsanaUserRef(gid: Self.me, name: "Dev One"),
                               type: "comment", resourceSubtype: "comment_added", text: "hi")
        let d = Defect(task: t, stories: [story], sourceTitle: "[BUG-184] Receipt time", myGid: Self.me,
                       board: board, calendar: utc)
        XCTAssertEqual(d.gid, "t1")
        XCTAssertEqual(d.bugNumber, 184)
        XCTAssertEqual(d.status, 4)
        XCTAssertEqual(d.awaiting, .ours)
        XCTAssertEqual(d.awaitingLabel, "Vendor")
        XCTAssertEqual(d.title, "[BUG-184] Receipt time")
        XCTAssertEqual(d.workbenchName, "Follow up of BUG-184")
        XCTAssertEqual(d.sourceGid, "5001")
        XCTAssertEqual(d.sprint, "5")
        XCTAssertNil(d.classification)
        XCTAssertEqual(d.permalink, "https://app.asana.com/0/1/t1")
        XCTAssertEqual(d.assignee?.gid, Self.me)
        XCTAssertEqual(d.dueOn, utc.date(from: DateComponents(year: 2026, month: 10, day: 26)))
        XCTAssertEqual(d.notes.priority, "Low")
        XCTAssertEqual(d.events.count, 1)
        XCTAssertTrue(d.events[0].isMine)
    }

    func testTitleFallsBackToWorkbenchName() {
        let t = task(name: "Follow up of BUG-184", fields: [], dependents: [])
        let d = Defect(task: t, stories: [], sourceTitle: nil, myGid: Self.me, board: board, calendar: utc)
        XCTAssertEqual(d.title, "Follow up of BUG-184")
        XCTAssertNil(d.sourceGid)
    }

    func testNoBugNumberStillBuilds() {
        let t = task(name: "Qualifications import", fields: [])
        let d = Defect(task: t, stories: [], sourceTitle: nil, myGid: Self.me, board: board, calendar: utc)
        XCTAssertNil(d.bugNumber)
        XCTAssertNil(d.status)
        XCTAssertNil(d.awaiting)
        XCTAssertNil(d.dueOn)
        XCTAssertEqual(d.title, "Qualifications import")
    }

    func testUnknownEnumValuesBecomeNil() {
        let t = task(name: "Follow up of BUG-1", fields: [("Awaiting", "Partner"), ("Status", "Weird")])
        let d = Defect(task: t, stories: [], sourceTitle: nil, myGid: Self.me, board: board, calendar: utc)
        XCTAssertNil(d.awaiting)
        XCTAssertEqual(d.awaitingLabel, "Partner")
        XCTAssertNil(d.status)
    }

    func testAwaitingLabelsAreCaseInsensitiveAndEmptyNeverMatches() {
        XCTAssertEqual(labels.classify("client"), .theirs)
        XCTAssertEqual(labels.classify(" VENDOR "), .ours)
        XCTAssertNil(labels.classify(""))
        XCTAssertNil(labels.classify(nil))
        XCTAssertNil(AwaitingLabels.none.classify("Client"))
        let t = task(name: "Follow up of BUG-2", fields: [("Awaiting", "Client")])
        XCTAssertEqual(Defect(task: t, stories: [], sourceTitle: nil, myGid: Self.me, board: board).awaiting, .theirs)
    }
}
