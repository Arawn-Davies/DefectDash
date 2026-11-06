import Foundation
import XCTest
@testable import DefectDashCore

final class GitRunnerTests: XCTestCase {
    var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appending(path: "defectdash-git-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    /// A child that writes more than the 64 KiB pipe buffer must still be drained and reaped.
    func testLargeOutputDoesNotDeadlock() async throws {
        let git = ProcessGitRunner()
        try FileManager.default.createDirectory(at: root.appending(path: "big/files"), withIntermediateDirectories: true)
        let repo = root.appending(path: "big")
        _ = try await git.run(["init", "-q"], in: repo)
        let suffix = String(repeating: "x", count: 60)
        for i in 0..<3000 {
            try Data().write(to: repo.appending(path: "files/f\(i)-\(suffix)"))
        }
        _ = try await git.run(["add", "."], in: repo)
        let listing = try await git.run(["ls-files"], in: repo)
        XCTAssertGreaterThan(listing.utf8.count, 65_536)
        XCTAssertEqual(listing.split(separator: "\n").count, 3000)
    }

    /// A git that never returns is terminated after `timeout` and reported as a failure, not a hang.
    func testHangingGitIsTerminatedAfterTimeout() async throws {
        let fake = root.appending(path: "fake-git")
        try "#!/bin/sh\nsleep 30\n".write(to: fake, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fake.path)
        let git = ProcessGitRunner(gitPath: fake.path, timeout: 1)
        let started = Date()
        do {
            _ = try await git.run(["status"], in: root)
            XCTFail("expected a failure")
        } catch let error as GitError {
            guard case .failed = error else { return XCTFail("unexpected \(error)") }
        }
        XCTAssertLessThan(Date().timeIntervalSince(started), 10)
    }
}
