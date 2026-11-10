import Foundation
import XCTest
@testable import DefectDashCore

final class RefreshCacheTests: XCTestCase {
    var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appending(path: "defectdash-cache-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    func sampleResult() -> RefreshResult {
        let T = Date(timeIntervalSince1970: 1_800_000_000)
        let event = ActivityEvent(id: "e1", at: T, byGid: "200", byName: "Manager",
                                  kind: .comment(author: "Tester A", text: "re-tested", viaRelay: true), isMine: false)
        let change = ActivityEvent(id: "e2", at: T.addingTimeInterval(-60), byGid: "100", byName: "Dev One",
                                   kind: .defectStatusChanged(from: 3, to: 4), isMine: true)
        let defect = Defect(gid: "g1", bugNumber: 101, title: "[BUG-101] Save drops an ingredient", workbenchName: "Follow up of BUG-101",
                            permalink: "https://app.asana.com/0/1/g1", sourceGid: "5001", status: 4, statusLabel: "4 · Retest",
                            awaiting: .ours, awaitingLabel: "Vendor", classification: nil, sprint: "5",
                            assignee: AsanaUserRef(gid: "100", name: "Dev One"), dueOn: T, modifiedAt: T,
                            notes: DefectNotes.parse("Expected result::\nsaved\n\nActual result::\ndropped\n"),
                            events: [event, change])
        let host = RepoState(path: URL(fileURLWithPath: "/tmp/wt/Sys/fix/bug-101"), label: "host", branch: "fix/bug-101",
                             dirty: true, ahead: 1, behind: 0, lastCommitAt: T, lastCommitAuthorEmail: "d@x", lastCommitSubject: "fix",
                             myLastCommitAt: T, error: nil)
        let sub = RepoState(path: URL(fileURLWithPath: "/tmp/wt/Sys/fix/bug-101/engines/core"), label: "engines/core", branch: nil,
                            dirty: false, ahead: nil, behind: nil, lastCommitAt: nil, lastCommitAuthorEmail: nil, lastCommitSubject: nil,
                            myLastCommitAt: nil, error: "not a repo")
        let wt = Worktree(path: host.path, system: "Sys", relativePath: "fix/bug-101", host: host, submodules: [sub], bugPrefix: "BUG")
        let item = WorkItem(defect: defect, worktrees: [wt], primaryWorktree: wt, group: .needsYou,
                            flags: [.retest, .overdue], needsYou: true, lastOtherActivity: event, myLastAction: T)
        let other = Worktree(path: URL(fileURLWithPath: "/tmp/wt/Sys/misc"), system: "Sys", relativePath: "misc", host: host)
        return RefreshResult(items: [item], otherWorktrees: [other], me: AsanaUserRef(gid: "100", name: "Dev One"),
                             timings: [("asana", 1.5)])
    }

    func testRoundTrip() throws {
        let url = dir.appending(path: "last-refresh.json")
        let savedAt = Date(timeIntervalSince1970: 1_800_000_100)
        try RefreshCache.save(sampleResult(), savedAt: savedAt, to: url)
        let cached = try XCTUnwrap(RefreshCache.load(from: url))
        XCTAssertEqual(cached.savedAt, savedAt)
        XCTAssertEqual(cached.me, AsanaUserRef(gid: "100", name: "Dev One"))
        XCTAssertEqual(cached.items.count, 1)
        let item = cached.items[0]
        XCTAssertEqual(item.group, .needsYou)
        XCTAssertEqual(item.flags, [.retest, .overdue])
        XCTAssertTrue(item.needsYou)
        XCTAssertEqual(item.defect.bugNumber, 101)
        XCTAssertEqual(item.defect.awaiting, .ours)
        XCTAssertEqual(item.defect.notes.expected, "saved")
        XCTAssertEqual(item.defect.events.map(\.kind), [
            .comment(author: "Tester A", text: "re-tested", viaRelay: true), .defectStatusChanged(from: 3, to: 4),
        ])
        XCTAssertEqual(item.worktrees.first?.submodules.first?.error, "not a repo")
        XCTAssertEqual(item.primaryWorktree?.bugNumber, 101)
        XCTAssertEqual(item.lastOtherActivity?.id, "e1")
        XCTAssertEqual(cached.otherWorktrees.map(\.relativePath), ["misc"])
    }

    func testMissingOrCorruptFileLoadsNil() throws {
        XCTAssertNil(RefreshCache.load(from: dir.appending(path: "nope.json")))
        let bad = dir.appending(path: "bad.json")
        try Data("{not json".utf8).write(to: bad)
        XCTAssertNil(RefreshCache.load(from: bad))
    }

    func testFileIsPrivateAndWrittenAtomically() throws {
        let url = dir.appending(path: "sub/last-refresh.json")   // parent created on demand
        try RefreshCache.save(sampleResult(), savedAt: Date(), to: url)
        let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
        XCTAssertEqual((attrs[.posixPermissions] as? Int).map { $0 & 0o777 }, 0o600)
        XCTAssertTrue(RefreshCache.defaultURL.path.contains("Library/Caches/\(Settings.bundleIdentifier)/"))
    }
}
