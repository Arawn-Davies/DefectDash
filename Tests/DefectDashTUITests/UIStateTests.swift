import Foundation
import XCTest
import DefectDashCore
@testable import DefectDashTUI

enum Fixtures {
    static let T = Date(timeIntervalSince1970: 1_793_700_000)

    static func defect(_ bug: Int, status: Int? = 3, awaiting: Awaiting? = .ours, assignee: String? = "100",
                       title: String? = nil, events: [ActivityEvent] = []) -> Defect {
        Defect(gid: "g\(bug)", bugNumber: bug, title: title ?? "[BUG-\(bug)] Title \(bug)", workbenchName: "Follow up of BUG-\(bug)",
               permalink: "https://app.asana.com/0/1/g\(bug)", sourceGid: nil, status: status,
               statusLabel: status.map { "\($0) · S" }, awaiting: awaiting, awaitingLabel: awaiting == .ours ? "Vendor" : "Client",
               classification: nil, sprint: nil, assignee: assignee.map { AsanaUserRef(gid: $0, name: "Dev One") },
               dueOn: nil, modifiedAt: T, notes: DefectNotes.parse("Expected result::\nworks\n\nActual result::\nbroken\n"),
               events: events)
    }

    static func other(at: Date) -> ActivityEvent {
        ActivityEvent(id: UUID().uuidString, at: at, byGid: "200", byName: "Manager",
                      kind: .comment(author: "Manager", text: "hello there", viaRelay: false), isMine: false)
    }

    static func worktree(_ path: String, system: String = "Sys") -> Worktree {
        let url = URL(fileURLWithPath: "/tmp/wt/\(system)/\(path)")
        let host = RepoState(path: url, label: "host", branch: path, dirty: true, ahead: 1, behind: 0, lastCommitAt: T,
                             lastCommitAuthorEmail: "d@x", lastCommitSubject: "fix", myLastCommitAt: T, error: nil)
        return Worktree(path: url, system: system, relativePath: path, host: host)
    }

    /// Three items: BUG-1 needs you (with worktree), BUG-2 yours in hand, BUG-3 with the other side (dimmed).
    static func items() -> [WorkItem] {
        let ctx = RankingContext(myGid: "100", matchSystems: ["Sys"], now: T.addingTimeInterval(60))
        return Ranking.rank(defects: [
            defect(1, events: [other(at: T.addingTimeInterval(10))]),   // newer than my last commit at T
            defect(2, events: []),
            defect(3, awaiting: .theirs, events: [other(at: T)]),
        ], worktrees: [worktree("fix/bug-1")], context: ctx)
    }
}

final class UIStateTests: XCTestCase {
    func makeState() -> UIState {
        var s = UIState()
        s.items = Fixtures.items()
        s.otherWorktrees = [Fixtures.worktree("misc/scratch")]
        return s
    }

    func testRowsAreGroupedAndSelectionStartsOnFirstItem() {
        let s = makeState()
        let rows = s.rows
        guard case .header(.needsYou, 1) = rows[0] else { return XCTFail("\(rows[0])") }
        guard case let .item(item) = rows[1] else { return XCTFail("\(rows[1])") }
        XCTAssertEqual(item.defect.bugNumber, 1)
        XCTAssertEqual(s.selectedItem?.defect.bugNumber, 1)
        XCTAssertTrue(rows.contains { if case .otherHeader(1) = $0 { return true } else { return false } })
    }

    func testMoveSkipsHeadersAndClamps() {
        var s = makeState()
        s.move(by: 1)
        XCTAssertEqual(s.selectedItem?.defect.bugNumber, 2)
        s.move(by: 1)
        XCTAssertEqual(s.selectedItem?.defect.bugNumber, 3)
        s.move(by: 5)
        XCTAssertEqual(s.selectedItem?.defect.bugNumber, 3)
        s.move(by: -10)
        XCTAssertEqual(s.selectedItem?.defect.bugNumber, 1)
    }

    func testHideDimmedRemovesTiers4To6() {
        var s = makeState()
        s.hideDimmed = true
        XCTAssertFalse(s.rows.contains { if case let .item(i) = $0 { return i.defect.bugNumber == 3 } else { return false } })
        s.move(by: 10)
        XCTAssertEqual(s.selectedItem?.defect.bugNumber, 2)
    }

    func testFilterNarrowsByBugOrTitle() {
        var s = makeState()
        s.filter = "bug-3"
        XCTAssertEqual(s.visibleItems.map(\.defect.bugNumber), [3])
        s.filter = "title 2"
        XCTAssertEqual(s.visibleItems.map(\.defect.bugNumber), [2])
        s.filter = ""
        XCTAssertEqual(s.visibleItems.count, 3)
    }

    func testJumpToTier() {
        var s = makeState()
        s.jump(to: .withThem)
        XCTAssertEqual(s.selectedItem?.defect.bugNumber, 3)
        s.jump(to: .unassigned)   // empty tier: selection unchanged
        XCTAssertEqual(s.selectedItem?.defect.bugNumber, 3)
    }

    func testKeysProduceCommands() {
        var s = makeState()
        XCTAssertEqual(s.apply(.char("q")), .quit)
        XCTAssertEqual(s.apply(.ctrlC), .quit)
        XCTAssertEqual(s.apply(.char("r")), .refresh)
        XCTAssertEqual(s.apply(.char("o")), .openAsana)
        XCTAssertEqual(s.apply(.char("d")), .toggleDimmed)
        XCTAssertTrue(s.hideDimmed)
        XCTAssertEqual(s.apply(.char("j")), .none)
        XCTAssertEqual(s.selectedItem?.defect.bugNumber, 2)
        XCTAssertEqual(s.apply(.enter), .none)
        XCTAssertEqual(s.focus, .detail)
        XCTAssertEqual(s.apply(.char("J")), .none)
        XCTAssertEqual(s.detailScroll, 10)   // J pages; j scrolls one line
        XCTAssertEqual(s.apply(.char("k")), .none)
        XCTAssertEqual(s.detailScroll, 9)
        XCTAssertEqual(s.apply(.escape), .none)
        XCTAssertEqual(s.focus, .list)
    }

    func testFilterModeCollectsTextUntilEnter() {
        var s = makeState()
        _ = s.apply(.char("/"))
        XCTAssertEqual(s.focus, .filter)
        _ = s.apply(.char("3"))
        XCTAssertEqual(s.filter, "3")
        XCTAssertEqual(s.visibleItems.map(\.defect.bugNumber), [3])
        _ = s.apply(.backspace)
        XCTAssertEqual(s.filter, "")
        _ = s.apply(.char("1"))
        _ = s.apply(.enter)
        XCTAssertEqual(s.focus, .list)
        XCTAssertEqual(s.filter, "1")
        _ = s.apply(.escape)
        XCTAssertEqual(s.filter, "")
    }
}

final class RenderTests: XCTestCase {
    func testFrameShowsGroupsSelectionAndDetail() {
        var s = UIState()
        s.items = Fixtures.items()
        s.me = AsanaUserRef(gid: "100", name: "Dev One")
        s.lastRefreshed = Fixtures.T
        let screen = Render.frame(state: s, cols: 100, rows: 24, now: Fixtures.T.addingTimeInterval(120))
        let text = (0..<24).map(screen.line).joined(separator: "\n")
        XCTAssertTrue(text.contains("Needs you (1)"), text)
        XCTAssertTrue(text.contains("BUG-1"), text)
        XCTAssertTrue(text.contains("Dev One"), text)
        XCTAssertTrue(text.contains("refreshed 2m ago"), text)
        XCTAssertTrue(text.contains("Expected result"), text)
        XCTAssertTrue(text.contains("fix/bug-1"), text)
        XCTAssertTrue(text.contains("q quit"), text)
    }

    func testTooSmallShowsMessage() {
        let screen = Render.frame(state: UIState(), cols: 40, rows: 10, now: Fixtures.T)
        XCTAssertTrue((0..<10).map(screen.line).joined().contains("Terminal too small"))
    }

    func testDetailLinesIncludeReportAndActivity() {
        let item = Fixtures.items().first!
        let lines = DetailText.lines(for: item, width: 60).map(\.text)
        XCTAssertTrue(lines.contains { $0.contains("Expected result") })
        XCTAssertTrue(lines.contains { $0.contains("works") })
        XCTAssertTrue(lines.contains { $0.contains("Manager") && $0.contains("hello there") || $0.contains("Manager") })
        XCTAssertTrue(lines.allSatisfy { $0.count <= 60 })
    }
}
