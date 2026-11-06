import Foundation
import XCTest
@testable import DefectDashCore

final class RankingTests: XCTestCase {
    static let me = "100"
    static let other = "200"
    let T = Date(timeIntervalSince1970: 1_793_700_000)   // 2026-11-03 ~10:00 UTC
    let utc: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    var context: RankingContext {
        RankingContext(myGid: Self.me, matchSystems: ["AlphaSystem"], now: T.addingTimeInterval(3600), calendar: utc)
    }

    // MARK: builders

    func event(_ id: String = UUID().uuidString, at: Date, mine: Bool, kind: ActivityKind) -> ActivityEvent {
        ActivityEvent(id: id, at: at, byGid: mine ? Self.me : Self.other, byName: mine ? "Dev One" : "Manager", kind: kind, isMine: mine)
    }

    func otherComment(at: Date, text: String = "hello", relay: Bool = false) -> ActivityEvent {
        event(at: at, mine: false, kind: .comment(author: relay ? "Tester A" : "Manager", text: text, viaRelay: relay))
    }

    func myComment(at: Date) -> ActivityEvent {
        event(at: at, mine: true, kind: .comment(author: "Dev One", text: "done", viaRelay: false))
    }

    func makeDefect(gid: String = UUID().uuidString, bug: Int? = 1, status: Int? = 3, awaiting: Awaiting? = .ours,
                    assigneeGid: String? = RankingTests.me, due: Date? = nil, events: [ActivityEvent] = [],
                    classification: String? = nil, modifiedAt: Date? = nil) -> Defect {
        Defect(gid: gid, bugNumber: bug, title: "[BUG-\(bug ?? 0)] Title", workbenchName: "Follow up of BUG-\(bug ?? 0)",
               permalink: nil, sourceGid: nil, status: status, awaiting: awaiting, classification: classification,
               sprint: nil, assignee: assigneeGid.map { AsanaUserRef(gid: $0, name: "X") }, dueOn: due,
               modifiedAt: modifiedAt ?? T, notes: DefectNotes.parse(""), events: events.sorted { $0.at > $1.at })
    }

    func makeWorktree(system: String = "AlphaSystem", path: String, branch: String? = nil, myLast: Date? = nil,
                      last: Date? = nil, dirty: Bool = false, ahead: Int? = 0) -> Worktree {
        let url = URL(fileURLWithPath: "/tmp/wt/\(system)/\(path)")
        let host = RepoState(path: url, label: "host", branch: branch ?? path, dirty: dirty, ahead: ahead, behind: 0,
                             lastCommitAt: last, lastCommitAuthorEmail: nil, lastCommitSubject: nil,
                             myLastCommitAt: myLast, error: nil)
        return Worktree(path: url, system: system, relativePath: path, host: host)
    }

    func rank(_ defects: [Defect], _ worktrees: [Worktree] = []) -> [WorkItem] {
        Ranking.rank(defects: defects, worktrees: worktrees, context: context)
    }

    // MARK: tests

    func testNeedsYouWhenOtherActivityNewerThanMyCommit() {
        let d = makeDefect(bug: 7, events: [otherComment(at: T.addingTimeInterval(10))])
        let wt = makeWorktree(path: "fix/bug-007", myLast: T, last: T)
        let items = rank([d], [wt])
        XCTAssertEqual(items.count, 1)
        XCTAssertTrue(items[0].needsYou)
        XCTAssertEqual(items[0].group, .needsYou)
        XCTAssertEqual(items[0].primaryWorktree?.relativePath, "fix/bug-007")
        XCTAssertEqual(items[0].myLastAction, T)
        XCTAssertEqual(items[0].lastOtherActivity?.at, T.addingTimeInterval(10))
    }

    func testNotNeedsYouWhenMyCommitNewer() {
        let d = makeDefect(bug: 7, events: [otherComment(at: T.addingTimeInterval(10))])
        let wt = makeWorktree(path: "fix/bug-007", myLast: T.addingTimeInterval(20), last: T.addingTimeInterval(20))
        let items = rank([d], [wt])
        XCTAssertFalse(items[0].needsYou)
        XCTAssertEqual(items[0].group, .yoursInHand)
    }

    func testAwaitingTheirsIsGroup5EvenIfAssignedToMe() {
        let d = makeDefect(awaiting: .theirs, assigneeGid: Self.me, events: [otherComment(at: T)])
        XCTAssertEqual(rank([d])[0].group, .withThem)
        XCTAssertFalse(rank([d])[0].needsYou)
    }

    func testUnsetAwaitingTreatedAsOurs() {
        let d = makeDefect(awaiting: nil, assigneeGid: Self.me, events: [otherComment(at: T)])
        XCTAssertEqual(rank([d])[0].group, .needsYou)
        XCTAssertTrue(rank([d])[0].needsYou)
    }

    func testClosedStatusesGoToGroup6AndNeverNeedYou() {
        for status in [5, 6, 7] {
            let d = makeDefect(status: status, events: [otherComment(at: T)])
            let item = rank([d])[0]
            XCTAssertEqual(item.group, .closedOnBoard, "status \(status)")
            XCTAssertFalse(item.needsYou, "status \(status)")
        }
    }

    func testGroup1OrderOverdueThenStatusThenOldestWaiting() {
        let overdue = makeDefect(gid: "overdue", status: 2, due: utc.date(byAdding: .day, value: -2, to: T)!,
                                 events: [otherComment(at: T)])
        let waiting1d = makeDefect(gid: "1d", status: 4, events: [otherComment(at: T.addingTimeInterval(-86_400))])
        let waiting3d = makeDefect(gid: "3d", status: 4, events: [otherComment(at: T.addingTimeInterval(-3 * 86_400))])
        let items = rank([waiting1d, overdue, waiting3d])
        XCTAssertEqual(items.map(\.group), [.needsYou, .needsYou, .needsYou])
        XCTAssertEqual(items.map(\.id), ["overdue", "3d", "1d"])
        // status ordering 4 before 3 before 2 before 1 before nil, when nothing is overdue
        let s = [4, 3, 2, 1].map { (n: Int) in makeDefect(gid: "s\(n)", status: n, events: [otherComment(at: T)]) }
            + [makeDefect(gid: "snil", status: nil, events: [otherComment(at: T)])]
        XCTAssertEqual(rank(s.reversed()).map(\.id), ["s4", "s3", "s2", "s1", "snil"])
    }

    func testGroup2OrderByDueThenStatus() {
        let later = makeDefect(gid: "later", status: 4, due: T.addingTimeInterval(5 * 86_400), events: [myComment(at: T)])
        let sooner3 = makeDefect(gid: "sooner3", status: 3, due: T.addingTimeInterval(86_400), events: [myComment(at: T)])
        let sooner4 = makeDefect(gid: "sooner4", status: 4, due: T.addingTimeInterval(86_400), events: [myComment(at: T)])
        let noDue = makeDefect(gid: "nodue", status: 4, due: nil, events: [myComment(at: T)])
        let items = rank([noDue, later, sooner3, sooner4])
        XCTAssertEqual(items.map(\.group), Array(repeating: .yoursInHand, count: 4))
        XCTAssertEqual(items.map(\.id), ["sooner4", "sooner3", "later", "nodue"])
    }

    func testMatchRestrictedToSystems() {
        let d = makeDefect(bug: 44, events: [otherComment(at: T)])
        let beta = makeWorktree(system: "BetaSystem", path: "fix/bug-0044", last: T)
        let alpha = makeWorktree(system: "AlphaSystem", path: "fix/bug-0044", last: T)
        XCTAssertTrue(rank([d], [beta])[0].worktrees.isEmpty)
        XCTAssertEqual(rank([d], [beta, alpha])[0].worktrees.map(\.system), ["AlphaSystem"])
    }

    func testBoardConfigDrivesClosedAndRetestNumbers() {
        let board = BoardConfig(closedFromStatus: 9, retestStatus: 6)
        let ctx = RankingContext(myGid: Self.me, matchSystems: [], board: board, now: T, calendar: utc)
        let five = makeDefect(status: 5, events: [otherComment(at: T)])
        XCTAssertEqual(Ranking.rank(defects: [five], worktrees: [], context: ctx)[0].group, .needsYou)
        let nine = makeDefect(status: 9, events: [otherComment(at: T)])
        XCTAssertEqual(Ranking.rank(defects: [nine], worktrees: [], context: ctx)[0].group, .closedOnBoard)
        let retest = makeDefect(status: 6, events: [otherComment(at: T, text: "retested, still broken")])
        XCTAssertTrue(Ranking.rank(defects: [retest], worktrees: [], context: ctx)[0].flags.contains(.retest))
        XCTAssertFalse(rank([retest])[0].flags.contains(.retest))   // default board: retest is 4
    }

    func testEmptyMatchSystemsMatchesEverySystem() {
        let d = makeDefect(bug: 44, events: [otherComment(at: T)])
        let beta = makeWorktree(system: "BetaSystem", path: "fix/bug-0044", last: T)
        let all = RankingContext(myGid: Self.me, matchSystems: [], now: T, calendar: utc)
        XCTAssertEqual(Ranking.rank(defects: [d], worktrees: [beta], context: all)[0].worktrees.map(\.system), ["BetaSystem"])
    }

    func testPrimaryIsNewestCommit() {
        let d = makeDefect(bug: 6, events: [otherComment(at: T)])
        let old = makeWorktree(path: "bug-006", last: T.addingTimeInterval(-100))
        let new = makeWorktree(path: "fix/bug-006-retest", last: T.addingTimeInterval(-10))
        let item = rank([d], [old, new])[0]
        XCTAssertEqual(item.worktrees.count, 2)
        XCTAssertEqual(item.primaryWorktree?.relativePath, "fix/bug-006-retest")
    }

    func testFlags() {
        let retest = makeDefect(status: 4, events: [otherComment(at: T, text: "Re-tested this, still failing")])
        XCTAssertTrue(rank([retest])[0].flags.contains(.retest))
        let retestWrongStatus = makeDefect(status: 3, events: [otherComment(at: T, text: "please retest")])
        XCTAssertFalse(rank([retestWrongStatus])[0].flags.contains(.retest))
        let retestBounced = makeDefect(status: 3, events: [
            otherComment(at: T, text: "retested, failed"),
            event(at: T.addingTimeInterval(-5), mine: false, kind: .defectStatusChanged(from: 4, to: 3)),
        ])
        XCTAssertTrue(rank([retestBounced])[0].flags.contains(.retest))
        XCTAssertTrue(rank([retestBounced])[0].flags.contains(.bounced))

        let classified = makeDefect(events: [otherComment(at: T)], classification: "Expected Behaviour")
        XCTAssertTrue(rank([classified])[0].flags.contains(.expectedBehaviour))
        let relayed = makeDefect(events: [otherComment(at: T, text: "this is the expected behavior", relay: true)])
        XCTAssertTrue(rank([relayed])[0].flags.contains(.expectedBehaviour))
        let plainOther = makeDefect(events: [otherComment(at: T, text: "this is the expected behaviour", relay: false)])
        XCTAssertFalse(rank([plainOther])[0].flags.contains(.expectedBehaviour))

        let yesterday = utc.date(byAdding: .day, value: -1, to: utc.startOfDay(for: context.now))!
        let overdue = makeDefect(due: yesterday, events: [otherComment(at: T)])
        XCTAssertTrue(rank([overdue])[0].flags.contains(.overdue))
        let today = makeDefect(due: utc.startOfDay(for: context.now), events: [otherComment(at: T)])
        XCTAssertFalse(rank([today])[0].flags.contains(.overdue))

        let noWorktree = makeDefect(bug: 9, assigneeGid: Self.me, events: [otherComment(at: T)])
        XCTAssertTrue(rank([noWorktree])[0].flags.contains(.noWorktree))
        let withWorktree = rank([noWorktree], [makeWorktree(path: "fix/bug-009", last: T)])[0]
        XCTAssertFalse(withWorktree.flags.contains(.noWorktree))
        let notMine = makeDefect(bug: 9, assigneeGid: Self.other, events: [otherComment(at: T)])
        XCTAssertFalse(rank([notMine])[0].flags.contains(.noWorktree))
    }

    func testDefectWithoutBugNumberIsListedUnmatched() {
        let d = makeDefect(bug: nil, status: nil, awaiting: nil, assigneeGid: nil, events: [])
        let items = rank([d], [makeWorktree(path: "main", branch: "main", last: T)])
        XCTAssertEqual(items.count, 1)
        XCTAssertTrue(items[0].worktrees.isEmpty)
        XCTAssertEqual(items[0].group, .unassigned)
    }

    func testOtherWorktreesDirtyOrAheadOnly() {
        let clean = makeWorktree(path: "clean", last: T)
        let dirty = makeWorktree(path: "dirty", last: T.addingTimeInterval(-50), dirty: true)
        let ahead = makeWorktree(path: "ahead", last: T.addingTimeInterval(-10), ahead: 2)
        let matchedDirty = makeWorktree(path: "fix/bug-001", last: T, dirty: true)
        let others = Ranking.otherWorktrees([clean, dirty, ahead, matchedDirty], matched: [matchedDirty.id])
        XCTAssertEqual(others.map(\.relativePath), ["ahead", "dirty"])
    }
}
