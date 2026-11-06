import Foundation
import XCTest
@testable import DefectDashCore

final class WorktreeScannerTests: XCTestCase {
    var root: URL!
    let git = ProcessGitRunner()

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appending(path: "defectdash-tests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    // MARK: helpers

    @discardableResult
    func sh(_ args: [String], in dir: URL, env: [String: String] = [:]) async throws -> String {
        try await ProcessGitRunner().run(args, in: dir, environment: env)
    }

    func initRepo(_ name: String, commit: Bool = true) async throws -> URL {
        let dir = root.appending(path: name, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try await sh(["init", "-q", "-b", "main"], in: dir)
        try await sh(["config", "user.email", "test@example.com"], in: dir)
        try await sh(["config", "user.name", "Test"], in: dir)
        if commit {
            try "hello\n".write(to: dir.appending(path: "a.txt"), atomically: true, encoding: .utf8)
            try await sh(["add", "a.txt"], in: dir)
            try await sh(["commit", "-q", "-m", "init"], in: dir)
        }
        return dir
    }

    func testEnumerateStopsAtGitAndSkipsDotDirs() throws {
        let sys = root.appending(path: "Sys")
        let fm = FileManager.default
        try fm.createDirectory(at: sys.appending(path: ".bare/refs"), withIntermediateDirectories: true)
        try fm.createDirectory(at: sys.appending(path: "fix/bug-1/sub"), withIntermediateDirectories: true)
        try "gitdir: ../../.bare/worktrees/bug-1\n".write(to: sys.appending(path: "fix/bug-1/.git"), atomically: true, encoding: .utf8)
        try fm.createDirectory(at: sys.appending(path: "main/.git"), withIntermediateDirectories: true)
        try fm.createDirectory(at: sys.appending(path: "main/nested/.git"), withIntermediateDirectories: true)
        try fm.createDirectory(at: root.appending(path: ".hidden/.git"), withIntermediateDirectories: true)

        let found = WorktreeScanner(git: git).enumerate(root: root)
        let pairs = found.map { "\($0.system)/\($0.relativePath)" }.sorted()
        XCTAssertEqual(pairs, ["Sys/fix/bug-1", "Sys/main"])
    }

    func testReadHostCleanWithCommit() async throws {
        let dir = try await initRepo("clean")
        let state = await WorktreeScanner(git: git).readHost(dir)
        XCTAssertEqual(state.label, "host")
        XCTAssertEqual(state.branch, "main")
        XCTAssertFalse(state.dirty)
        XCTAssertEqual(state.lastCommitSubject, "init")
        XCTAssertEqual(state.lastCommitAuthorEmail, "test@example.com")
        XCTAssertNotNil(state.lastCommitAt)
        XCTAssertEqual(state.myLastCommitAt, state.lastCommitAt)
        XCTAssertNil(state.error)
    }

    func testReadHostDirtyNoUpstreamDetached() async throws {
        let dir = try await initRepo("dirty")
        try "changed\n".write(to: dir.appending(path: "a.txt"), atomically: true, encoding: .utf8)
        try await sh(["checkout", "-q", "--detach"], in: dir)
        let state = await WorktreeScanner(git: git).readHost(dir)
        XCTAssertTrue(state.dirty)
        XCTAssertNil(state.ahead)
        XCTAssertNil(state.behind)
        XCTAssertNil(state.branch)
        XCTAssertNil(state.error)
    }

    func testReadHostEmptyRepo() async throws {
        let dir = try await initRepo("empty", commit: false)
        let state = await WorktreeScanner(git: git).readHost(dir)
        XCTAssertNil(state.lastCommitAt)
        XCTAssertNil(state.myLastCommitAt)
        XCTAssertFalse(state.dirty)
        XCTAssertNil(state.error)
    }

    func testAheadBehindAgainstUpstream() async throws {
        let origin = try await initRepo("origin")
        let clone = root.appending(path: "clone")
        try await sh(["clone", "-q", origin.path, clone.path], in: root)
        try await sh(["config", "user.email", "test@example.com"], in: clone)
        try await sh(["config", "user.name", "Test"], in: clone)
        try "more\n".write(to: clone.appending(path: "b.txt"), atomically: true, encoding: .utf8)
        try await sh(["add", "b.txt"], in: clone)
        try await sh(["commit", "-q", "-m", "second"], in: clone)
        let state = await WorktreeScanner(git: git).readHost(clone)
        XCTAssertEqual(state.ahead, 1)
        XCTAssertEqual(state.behind, 0)
    }

    func testSubmoduleCommitWinsRecency() async throws {
        let subOrigin = try await initRepo("sub-origin")
        let host = try await initRepo("host")
        let t0 = "2026-01-01T10:00:00Z"
        let t1 = "2026-01-01T10:01:00Z"
        try await sh(["-c", "protocol.file.allow=always", "submodule", "add", "-q", subOrigin.path, "sub"], in: host)
        try await sh(["commit", "-q", "-m", "add sub"], in: host, env: ["GIT_COMMITTER_DATE": t0, "GIT_AUTHOR_DATE": t0])
        let sub = host.appending(path: "sub")
        try await sh(["config", "user.email", "test@example.com"], in: sub)
        try await sh(["config", "user.name", "Test"], in: sub)
        try "x\n".write(to: sub.appending(path: "x.txt"), atomically: true, encoding: .utf8)
        try await sh(["add", "x.txt"], in: sub)
        try await sh(["commit", "-q", "-m", "sub work"], in: sub, env: ["GIT_COMMITTER_DATE": t1, "GIT_AUTHOR_DATE": t1])

        let scanner = WorktreeScanner(git: git)
        let hostState = await scanner.readHost(host)
        let subs = await scanner.readSubmodules(host)
        XCTAssertEqual(subs.count, 1)
        XCTAssertEqual(subs.first?.label, "sub")
        XCTAssertFalse(subs.first?.dirty ?? true)
        // An uninitialised submodule (declared but not checked out) is skipped.
        try FileManager.default.removeItem(at: sub)
        let after = await scanner.submodulePaths(host)
        XCTAssertEqual(after, [])
        let wt = Worktree(path: host, system: "Sys", relativePath: "host", host: hostState, submodules: subs)
        XCTAssertEqual(wt.lastCommitAt, try Date.ISO8601FormatStyle().parse(t1))
        XCTAssertEqual(wt.myLastCommitAt, try Date.ISO8601FormatStyle().parse(t1))
        XCTAssertEqual(hostState.lastCommitAt, try Date.ISO8601FormatStyle().parse(t0))
        XCTAssertTrue(wt.dirty)   // host sees the submodule pointer moved
    }

    func testEnrichOnlyWhereAsked() async throws {
        let subOrigin = try await initRepo("sub-origin2")
        let sysRoot = root.appending(path: "Sys")
        try FileManager.default.createDirectory(at: sysRoot, withIntermediateDirectories: true)
        for name in ["a", "b"] {
            let dir = try await initRepo("Sys/\(name)")
            try await sh(["-c", "protocol.file.allow=always", "submodule", "add", "-q", subOrigin.path, "sub"], in: dir)
            try await sh(["commit", "-q", "-m", "add sub"], in: dir)
        }
        let scanner = WorktreeScanner(git: git)
        let hosts = await scanner.scanHosts(root: root)
        let sysHosts = hosts.filter { $0.system == "Sys" }
        XCTAssertEqual(sysHosts.map(\.relativePath).sorted(), ["a", "b"])
        XCTAssertTrue(sysHosts.allSatisfy { $0.submodules.isEmpty })
        let enriched = await scanner.enrich(sysHosts) { $0.relativePath == "a" }
        XCTAssertEqual(enriched.first { $0.relativePath == "a" }?.submodules.count, 1)
        XCTAssertEqual(enriched.first { $0.relativePath == "b" }?.submodules.count, 0)
    }
}
